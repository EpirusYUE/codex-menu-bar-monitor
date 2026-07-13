import Foundation
import Testing
@testable import CodexStatusCore

@Test func parsesTaskStarted() {
    let line = Data(#"{"timestamp":"2026-07-13T09:05:51.262Z","type":"event_msg","payload":{"type":"task_started"}}"#.utf8)
    guard case let .started(date) = RolloutLifecycleParser.event(inLine: line) else {
        Issue.record("Expected task_started")
        return
    }
    #expect(date != nil)
}

@Test func parsesTaskComplete() {
    let line = Data(#"{"timestamp":"2026-07-13T09:10:00Z","type":"event_msg","payload":{"type":"task_complete"}}"#.utf8)
    guard case .completed = RolloutLifecycleParser.event(inLine: line) else {
        Issue.record("Expected task_complete")
        return
    }
}

@Test func ignoresUnrelatedEvents() {
    let line = Data(#"{"timestamp":"2026-07-13T09:10:00Z","type":"event_msg","payload":{"type":"token_count"}}"#.utf8)
    #expect(RolloutLifecycleParser.event(inLine: line) == nil)
}

@Test func parsesTurnAbortedAsTerminal() {
    let line = Data(#"{"timestamp":"2026-07-13T09:30:41.043Z","type":"event_msg","payload":{"type":"turn_aborted","reason":"interrupted"}}"#.utf8)
    guard case .aborted = RolloutLifecycleParser.event(inLine: line) else {
        Issue.record("Expected turn_aborted")
        return
    }
}
