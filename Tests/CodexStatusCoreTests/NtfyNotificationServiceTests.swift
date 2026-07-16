import Foundation
import Testing
@testable import CodexStatusCore

@Test func generatesPrivateTopicAndSubscriptionURL() {
    let service = NtfyNotificationService()
    let topic = NtfyNotificationService.generateTopic()
    #expect(topic.hasPrefix("codex-monitor-"))
    #expect(topic.count == 46)
    #expect(service.subscriptionURL(topic: topic)?.absoluteString == "https://ntfy.sh/\(topic)")
}

@Test func buildsNtfyJSONPublishRequest() throws {
    let service = NtfyNotificationService()
    let topic = NtfyNotificationService.generateTopic()
    let request = try #require(service.publishRequest(
        topic: topic,
        title: "Codex task completed",
        message: "One task finished"
    ))
    #expect(request.url?.absoluteString == "https://ntfy.sh")
    #expect(request.httpMethod == "POST")
    let body = try #require(request.httpBody)
    let payload = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
    #expect(payload["topic"] as? String == topic)
    #expect(payload["title"] as? String == "Codex task completed")
    #expect(payload["message"] as? String == "One task finished")
}
