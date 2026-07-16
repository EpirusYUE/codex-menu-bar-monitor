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

@Test func formatsCompletionDetails() {
    let task = CodexTask(
        id: "thread-1",
        title: "Test task",
        rolloutPath: "/tmp/rollout.jsonl",
        workingDirectory: "/Users/test/Documents/sample-project",
        startedAt: nil
    )
    let quota = CodexQuota(remainingPercent: 72, windowLabel: "5h", windowDurationMinutes: 300)
    let content = CompletionNotificationFormatter.content(
        task: task,
        quota: quota,
        remainingTaskCount: 2
    )
    #expect(content.title == "Codex 任务完成")
    #expect(content.message == "sample-project 72% 5h 剩余任务 2")
}

@Test func abbreviatesLongProjectFolder() {
    let task = CodexTask(
        id: "thread-1",
        title: "Test task",
        rolloutPath: "/tmp/rollout.jsonl",
        workingDirectory: "/Users/test/Documents/this-is-a-very-long-project-name",
        startedAt: nil
    )
    let content = CompletionNotificationFormatter.content(
        task: task,
        quota: nil,
        remainingTaskCount: 0
    )
    #expect(content.message == "this-is-a-very-lo… 用量暂不可用")
}

@Test func formatsWeeklyQuotaWithNoRemainingTasks() {
    let task = CodexTask(
        id: "thread-1",
        title: "Test task",
        rolloutPath: "/tmp/rollout.jsonl",
        workingDirectory: "/Users/test/Documents/sample-project",
        startedAt: nil
    )
    let quota = CodexQuota(remainingPercent: 24, windowLabel: "w", windowDurationMinutes: 10_080)
    let content = CompletionNotificationFormatter.content(
        task: task,
        quota: quota,
        remainingTaskCount: 0
    )
    #expect(content.message == "sample-project 24% w")
}
