import Foundation
import Darwin

public struct CodexQuota: Equatable, Sendable {
    public let remainingPercent: Int
    public let windowLabel: String
    public let windowDurationMinutes: Int

    public init(remainingPercent: Int, windowLabel: String, windowDurationMinutes: Int) {
        self.remainingPercent = remainingPercent
        self.windowLabel = windowLabel
        self.windowDurationMinutes = windowDurationMinutes
    }

    public var compactLabel: String {
        "\(remainingPercent)% \(windowLabel)"
    }
}

public enum RateLimitResponseParser {
    public static func quota(inLine data: Data) -> CodexQuota? {
        guard
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            numericID(object["id"]) == 2,
            let result = object["result"] as? [String: Any],
            let rateLimits = result["rateLimits"] as? [String: Any]
        else { return nil }

        let windows = ["primary", "secondary"].compactMap { key -> (used: Int, duration: Int)? in
            guard
                let window = rateLimits[key] as? [String: Any],
                let used = window["usedPercent"] as? Int,
                let duration = window["windowDurationMins"] as? Int
            else { return nil }
            return (used, duration)
        }

        // Codex plans can expose the 5-hour and weekly windows in either slot.
        // Prefer the short window, then fall back to the weekly/longest window.
        let selected = windows.first(where: { $0.duration <= 360 })
            ?? windows.max(by: { $0.duration < $1.duration })
        guard let selected else { return nil }

        let remaining = min(100, max(0, 100 - selected.used))
        let label = selected.duration <= 360 ? "5h" : "w"
        return CodexQuota(
            remainingPercent: remaining,
            windowLabel: label,
            windowDurationMinutes: selected.duration
        )
    }

    private static func numericID(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        return nil
    }
}

public final class CodexRateLimitReader: @unchecked Sendable {
    private let codexExecutable: String?

    public init(codexExecutable: String? = nil) {
        self.codexExecutable = codexExecutable ?? CodexInstallationLocator.codexExecutablePath()
    }

    public func readQuota() -> CodexQuota? {
        guard
            let codexExecutable,
            FileManager.default.isExecutableFile(atPath: codexExecutable)
        else { return nil }

        let initialize = #"{"id":1,"method":"initialize","params":{"clientInfo":{"name":"codex-menubar","version":"0.2.0"}}}"#
        let request = #"{"id":2,"method":"account/rateLimits/read","params":null}"#
        let process = Process()
        let input = Pipe()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: codexExecutable)
        process.arguments = [
            "app-server",
            "-c", "features.plugins=false",
            "-c", "features.remote_plugin=false",
            "--stdio"
        ]
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            defer {
                try? input.fileHandleForWriting.close()
                try? output.fileHandleForReading.close()
                if process.isRunning {
                    process.terminate()
                    process.waitUntilExit()
                }
            }

            try input.fileHandleForWriting.write(contentsOf: Data((initialize + "\n").utf8))
            var buffer = Data()
            guard waitForResponse(
                id: 1,
                fileDescriptor: output.fileHandleForReading.fileDescriptor,
                buffer: &buffer,
                timeout: 30
            ) != nil else { return nil }

            try input.fileHandleForWriting.write(contentsOf: Data((request + "\n").utf8))
            let deadline = Date().addingTimeInterval(20)
            while let line = readLine(
                fileDescriptor: output.fileHandleForReading.fileDescriptor,
                buffer: &buffer,
                deadline: deadline
            ) {
                if let quota = RateLimitResponseParser.quota(inLine: line) { return quota }
            }
        } catch {
            return nil
        }
        return nil
    }

    private func waitForResponse(
        id: Int,
        fileDescriptor: Int32,
        buffer: inout Data,
        timeout: TimeInterval
    ) -> Data? {
        let deadline = Date().addingTimeInterval(timeout)
        while let line = readLine(fileDescriptor: fileDescriptor, buffer: &buffer, deadline: deadline) {
            guard
                let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                let responseID = object["id"] as? Int
            else { continue }
            if responseID == id { return line }
        }
        return nil
    }

    private func readLine(
        fileDescriptor: Int32,
        buffer: inout Data,
        deadline: Date
    ) -> Data? {
        while true {
            if let newline = buffer.firstIndex(of: 0x0A) {
                let line = Data(buffer[..<newline])
                buffer.removeSubrange(...newline)
                return line
            }

            let remainingMilliseconds = Int32(max(0, min(30_000, deadline.timeIntervalSinceNow * 1_000)))
            guard remainingMilliseconds > 0 else { return nil }
            var descriptor = pollfd(fd: fileDescriptor, events: Int16(POLLIN), revents: 0)
            let pollResult = Darwin.poll(&descriptor, 1, remainingMilliseconds)
            guard pollResult > 0, descriptor.revents & Int16(POLLIN) != 0 else { return nil }

            var chunk = [UInt8](repeating: 0, count: 8_192)
            let count = chunk.withUnsafeMutableBytes { bytes in
                Darwin.read(fileDescriptor, bytes.baseAddress, bytes.count)
            }
            guard count > 0 else { return nil }
            buffer.append(contentsOf: chunk.prefix(count))
        }
    }
}
