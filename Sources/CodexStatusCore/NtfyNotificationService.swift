import Foundation

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
