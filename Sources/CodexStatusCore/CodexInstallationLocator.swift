import Foundation

public enum CodexInstallationLocator {
    public static var defaultApplicationCandidates: [URL] {
        let homeApplications = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications", isDirectory: true)
        return [
            URL(fileURLWithPath: "/Applications/ChatGPT.app", isDirectory: true),
            URL(fileURLWithPath: "/Applications/Codex.app", isDirectory: true),
            homeApplications.appendingPathComponent("ChatGPT.app", isDirectory: true),
            homeApplications.appendingPathComponent("Codex.app", isDirectory: true)
        ]
    }

    public static func applicationURL(
        candidates: [URL] = defaultApplicationCandidates,
        fileManager: FileManager = .default
    ) -> URL? {
        candidates.first { candidate in
            var isDirectory: ObjCBool = false
            return fileManager.fileExists(atPath: candidate.path, isDirectory: &isDirectory)
                && isDirectory.boolValue
        }
    }

    public static func codexExecutablePath(
        candidates: [URL] = defaultApplicationCandidates,
        fileManager: FileManager = .default
    ) -> String? {
        candidates
            .map { $0.appendingPathComponent("Contents/Resources/codex").path }
            .first(where: fileManager.isExecutableFile(atPath:))
    }
}
