import Foundation

public struct CompletionNotificationContent: Equatable, Sendable {
    public let title: String
    public let message: String
}

public enum CompletionNotificationFormatter {
    public static func content(
        task: CodexTask,
        quota: CodexQuota?,
        remainingTaskCount: Int
    ) -> CompletionNotificationContent {
        let folderName = URL(fileURLWithPath: task.workingDirectory).lastPathComponent
        let rawFolder = folderName.isEmpty ? task.workingDirectory : folderName
        let displayFolder = abbreviated(rawFolder, maximumLength: 18)
        let quotaText = quota.map { "\($0.remainingPercent)% \($0.windowLabel)" }
            ?? "用量暂不可用"
        let remainingTasksText = remainingTaskCount > 0
            ? " 剩余任务 \(remainingTaskCount)"
            : ""
        return CompletionNotificationContent(
            title: "Codex 任务完成",
            message: "\(displayFolder) \(quotaText)\(remainingTasksText)"
        )
    }

    private static func abbreviated(_ value: String, maximumLength: Int) -> String {
        guard value.count > maximumLength else { return value }
        return String(value.prefix(maximumLength - 1)) + "…"
    }
}

public final class NtfyNotificationService: @unchecked Sendable {
    private let serverURL: URL
    private let session: URLSession

    public init(
        serverURL: URL = URL(string: "https://ntfy.sh")!,
        session: URLSession = .shared
    ) {
        self.serverURL = serverURL
        self.session = session
    }

    public static func generateTopic() -> String {
        "codex-monitor-" + UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    }

    public func subscriptionURL(topic: String) -> URL? {
        guard Self.isValid(topic: topic) else { return nil }
        return serverURL.appendingPathComponent(topic)
    }

    public func publishRequest(topic: String, title: String, message: String) -> URLRequest? {
        guard Self.isValid(topic: topic) else { return nil }
        let payload: [String: Any] = [
            "topic": topic,
            "title": title,
            "message": message,
            "priority": 3
        ]
        guard let body = try? JSONSerialization.data(withJSONObject: payload) else { return nil }

        var request = URLRequest(url: serverURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        request.timeoutInterval = 15
        return request
    }

    public func send(topic: String, title: String, message: String) {
        guard let request = publishRequest(topic: topic, title: title, message: message) else { return }
        session.dataTask(with: request).resume()
    }

    private static func isValid(topic: String) -> Bool {
        guard topic.count >= 16 else { return false }
        return topic.unicodeScalars.allSatisfy {
            CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == "_"
        }
    }
}
