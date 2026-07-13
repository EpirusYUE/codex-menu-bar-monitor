import Foundation
import Testing
@testable import CodexStatusCore

@Test func prefersFiveHourQuota() {
    let line = Data(#"{"id":2,"result":{"rateLimits":{"primary":{"usedPercent":22,"windowDurationMins":10080},"secondary":{"usedPercent":31,"windowDurationMins":300}}}}"#.utf8)
    let quota = RateLimitResponseParser.quota(inLine: line)
    #expect(quota?.remainingPercent == 69)
    #expect(quota?.windowLabel == "5h")
}

@Test func fallsBackToWeeklyQuota() {
    let line = Data(#"{"id":2,"result":{"rateLimits":{"primary":{"usedPercent":22,"windowDurationMins":10080},"secondary":null}}}"#.utf8)
    let quota = RateLimitResponseParser.quota(inLine: line)
    #expect(quota?.remainingPercent == 78)
    #expect(quota?.windowLabel == "w")
}
