import Foundation
import SQLite3

public struct CodexTask: Equatable, Sendable {
    public let id: String
    public let title: String
    public let rolloutPath: String
    public let startedAt: Date?

    public init(id: String, title: String, rolloutPath: String, startedAt: Date?) {
        self.id = id
        self.title = title
        self.rolloutPath = rolloutPath
        self.startedAt = startedAt
    }
}

public struct CodexActivitySnapshot: Equatable, Sendable {
    public let runningTasks: [CodexTask]
    public let completedTaskIDs: Set<String>
    public let abortedTaskIDs: Set<String>
    public let newlyCompletedEventCount: Int
    public let sampledAt: Date

    public init(
        runningTasks: [CodexTask],
        completedTaskIDs: Set<String> = [],
        abortedTaskIDs: Set<String> = [],
        newlyCompletedEventCount: Int = 0,
        sampledAt: Date = Date()
    ) {
        self.runningTasks = runningTasks
        self.completedTaskIDs = completedTaskIDs
        self.abortedTaskIDs = abortedTaskIDs
        self.newlyCompletedEventCount = newlyCompletedEventCount
        self.sampledAt = sampledAt
    }
}

public enum LifecycleEvent: Equatable, Sendable {
    case started(Date?)
    case completed(Date?)
    case aborted(Date?)
}

public enum RolloutLifecycleParser {
    public static func event(inLine data: Data) -> LifecycleEvent? {
        guard
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            object["type"] as? String == "event_msg",
            let payload = object["payload"] as? [String: Any],
            let payloadType = payload["type"] as? String
        else { return nil }

        let date = (object["timestamp"] as? String).flatMap(Self.parseDate)
        switch payloadType {
        case "task_started": return .started(date)
        case "task_complete": return .completed(date)
        case "turn_aborted": return .aborted(date)
        default: return nil
        }
    }

    private static func parseDate(_ value: String) -> Date? {
        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractionalFormatter.date(from: value)
            ?? ISO8601DateFormatter().date(from: value)
    }
}

public final class CodexActivityReader: @unchecked Sendable {
    private struct ThreadRecord {
        let id: String
        let title: String
        let rolloutPath: String
    }

    private struct FileCursor {
        var offset: UInt64
        var partialLine: Data
        var latestEvent: LifecycleEvent?
    }

    private let databaseURL: URL
    private let fileManager: FileManager
    private var cursors: [String: FileCursor] = [:]

    public init(
        databaseURL: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/state_5.sqlite"),
        fileManager: FileManager = .default
    ) {
        self.databaseURL = databaseURL
        self.fileManager = fileManager
    }

    public func readSnapshot() throws -> CodexActivitySnapshot {
        let records = try readRecentThreads()
        var tasks: [CodexTask] = []
        var completedTaskIDs: Set<String> = []
        var abortedTaskIDs: Set<String> = []
        var newlyCompletedEventCount = 0

        for record in records {
            let result = latestLifecycleEvent(atPath: record.rolloutPath)
            newlyCompletedEventCount += result.newCompletions
            guard let event = result.event else { continue }
            switch event {
            case let .started(date):
                tasks.append(CodexTask(
                    id: record.id,
                    title: record.title,
                    rolloutPath: record.rolloutPath,
                    startedAt: date
                ))
            case .completed:
                completedTaskIDs.insert(record.id)
            case .aborted:
                abortedTaskIDs.insert(record.id)
            }
        }

        tasks.sort {
            ($0.startedAt ?? .distantPast) > ($1.startedAt ?? .distantPast)
        }
        return CodexActivitySnapshot(
            runningTasks: tasks,
            completedTaskIDs: completedTaskIDs,
            abortedTaskIDs: abortedTaskIDs,
            newlyCompletedEventCount: newlyCompletedEventCount
        )
    }

    private func readRecentThreads() throws -> [ThreadRecord] {
        var database: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(databaseURL.path, &database, flags, nil) == SQLITE_OK else {
            defer { if database != nil { sqlite3_close(database) } }
            throw ReaderError.databaseUnavailable(databaseURL.path)
        }
        defer { sqlite3_close(database) }
        sqlite3_busy_timeout(database, 750)

        // A running task continually updates its rollout. Seven days keeps startup
        // bounded while still covering unusually long Codex runs.
        let query = """
            SELECT id, title, rollout_path
            FROM threads
            WHERE archived = 0 AND updated_at >= CAST(strftime('%s','now') AS INTEGER) - 604800
            ORDER BY updated_at DESC
            """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, query, -1, &statement, nil) == SQLITE_OK else {
            throw ReaderError.queryFailed
        }
        defer { sqlite3_finalize(statement) }

        var records: [ThreadRecord] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard
                let idText = sqlite3_column_text(statement, 0),
                let titleText = sqlite3_column_text(statement, 1),
                let pathText = sqlite3_column_text(statement, 2)
            else { continue }
            records.append(ThreadRecord(
                id: String(cString: idText),
                title: String(cString: titleText),
                rolloutPath: String(cString: pathText)
            ))
        }
        return records
    }

    private func latestLifecycleEvent(atPath path: String) -> (event: LifecycleEvent?, newCompletions: Int) {
        guard fileManager.fileExists(atPath: path), let handle = try? FileHandle(forReadingFrom: URL(fileURLWithPath: path)) else {
            return (nil, 0)
        }
        defer { try? handle.close() }

        let size = (try? handle.seekToEnd()) ?? 0
        let cursor = cursors[path]

        if cursor == nil || size < cursor!.offset {
            let event = scanBackwardsForLifecycleEvent(handle: handle, fileSize: size)
            cursors[path] = FileCursor(offset: size, partialLine: Data(), latestEvent: event)
            // Existing history is baseline state, not a new completion notification.
            return (event, 0)
        }

        guard var current = cursor else { return (nil, 0) }
        var newCompletions = 0
        if size > current.offset {
            do {
                try handle.seek(toOffset: current.offset)
                let appended = try handle.readToEnd() ?? Data()
                let combined = current.partialLine + appended
                let hasTrailingNewline = combined.last == 0x0A
                var lines = combined.split(separator: 0x0A, omittingEmptySubsequences: false)
                if !hasTrailingNewline, let partial = lines.popLast() {
                    current.partialLine = Data(partial)
                } else {
                    current.partialLine = Data()
                }
                for line in lines where !line.isEmpty {
                    if let event = RolloutLifecycleParser.event(inLine: Data(line)) {
                        current.latestEvent = event
                        if case .completed = event { newCompletions += 1 }
                    }
                }
                current.offset = size
                cursors[path] = current
            } catch {
                // Preserve the last known state and retry on the next poll.
            }
        }
        return (current.latestEvent, newCompletions)
    }

    private func scanBackwardsForLifecycleEvent(handle: FileHandle, fileSize: UInt64) -> LifecycleEvent? {
        let chunkSize: UInt64 = 256 * 1024
        var position = fileSize
        var suffix = Data()

        while position > 0 {
            let start = position > chunkSize ? position - chunkSize : 0
            do {
                try handle.seek(toOffset: start)
                let chunk = try handle.read(upToCount: Int(position - start)) ?? Data()
                let combined = chunk + suffix
                let parts = combined.split(separator: 0x0A, omittingEmptySubsequences: false)

                if parts.count > 1 {
                    for index in stride(from: parts.count - 1, through: 1, by: -1) {
                        let line = parts[index]
                        if !line.isEmpty, let event = RolloutLifecycleParser.event(inLine: Data(line)) {
                            return event
                        }
                    }
                    suffix = Data(parts[0])
                } else {
                    suffix = combined
                }
                position = start
            } catch {
                return nil
            }
        }

        return suffix.isEmpty ? nil : RolloutLifecycleParser.event(inLine: suffix)
    }
}

public enum ReaderError: LocalizedError {
    case databaseUnavailable(String)
    case queryFailed

    public var errorDescription: String? {
        switch self {
        case let .databaseUnavailable(path): return "无法读取 Codex 状态数据库：\(path)"
        case .queryFailed: return "无法查询 Codex 任务状态"
        }
    }
}
