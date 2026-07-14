import Foundation
import Testing
@testable import CodexStatusCore

@Test func prefersChatGPTAndFindsBundledCodexExecutable() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let chatGPT = root.appendingPathComponent("ChatGPT.app", isDirectory: true)
    let legacyCodex = root.appendingPathComponent("Codex.app", isDirectory: true)
    let executable = chatGPT.appendingPathComponent("Contents/Resources/codex")
    try FileManager.default.createDirectory(
        at: executable.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try Data().write(to: executable)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
    try FileManager.default.createDirectory(at: legacyCodex, withIntermediateDirectories: true)

    let candidates = [chatGPT, legacyCodex]
    #expect(CodexInstallationLocator.applicationURL(candidates: candidates) == chatGPT)
    #expect(CodexInstallationLocator.codexExecutablePath(candidates: candidates) == executable.path)
}
