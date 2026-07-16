import Foundation
import SQLite3
import Testing
@testable import CodexStatusCore

@Test func reportsEveryNewCompletionEvent() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let databaseURL = root.appendingPathComponent("state.sqlite")
    let rolloutURL = root.appendingPathComponent("rollout.jsonl")
    var database: OpaquePointer?
    #expect(sqlite3_open(databaseURL.path, &database) == SQLITE_OK)
    defer { sqlite3_close(database) }

    let schema = """
        CREATE TABLE threads (
            id TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            rollout_path TEXT NOT NULL,
            cwd TEXT NOT NULL,
            archived INTEGER NOT NULL,
            updated_at INTEGER NOT NULL
        );
        """
    #expect(sqlite3_exec(database, schema, nil, nil, nil) == SQLITE_OK)

    let insert = """
        INSERT INTO threads VALUES (
            'thread-1', 'Test task', '\(rolloutURL.path)', '/tmp/sample-project', 0,
            CAST(strftime('%s','now') AS INTEGER)
        );
        """
    #expect(sqlite3_exec(database, insert, nil, nil, nil) == SQLITE_OK)

    let started = #"{"timestamp":"2026-07-13T09:00:00Z","type":"event_msg","payload":{"type":"task_started"}}"# + "\n"
    try Data(started.utf8).write(to: rolloutURL)

    let reader = CodexActivityReader(databaseURL: databaseURL)
    let baseline = try reader.readSnapshot()
    #expect(baseline.runningTasks.count == 1)
    #expect(baseline.newlyCompletedEventCount == 0)

    let complete = #"{"timestamp":"2026-07-13T09:00:01Z","type":"event_msg","payload":{"type":"task_complete"}}"# + "\n"
    try append(complete, to: rolloutURL)
    let completed = try reader.readSnapshot()
    #expect(completed.runningTasks.isEmpty)
    #expect(completed.newlyCompletedEventCount == 1)
    #expect(completed.newlyCompletedTasks.count == 1)
    #expect(completed.newlyCompletedTasks.first?.workingDirectory == "/tmp/sample-project")

    // A complete event must still be reported if a new turn starts before the
    // next sample and the thread remains in the running set.
    try append(started + complete + started, to: rolloutURL)
    let completedThenRestarted = try reader.readSnapshot()
    #expect(completedThenRestarted.runningTasks.count == 1)
    #expect(completedThenRestarted.newlyCompletedEventCount == 1)
    #expect(completedThenRestarted.newlyCompletedTasks.count == 1)
}

private func append(_ text: String, to url: URL) throws {
    let handle = try FileHandle(forWritingTo: url)
    defer { try? handle.close() }
    try handle.seekToEnd()
    try handle.write(contentsOf: Data(text.utf8))
}
