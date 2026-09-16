import Foundation

// BeadsData: the adapter between the app and a beads database. Everything that reads or writes
// beads goes through BDGateway (BDGateway.swift); this file holds errors and finding bd.

public enum BeadsDataError: Error, Equatable, LocalizedError {
    case notAWorkspace(path: String)
    case bdNotFound(searched: [String])
    case commandFailed(exitCode: Int32, message: String)
    case timedOut(seconds: Int)
    case unreadableOutput(detail: String)

    public var errorDescription: String? {
        switch self {
        case .notAWorkspace(let path):
            "\(path) has no initialised .beads folder. Choose a project that uses beads, or its .beads folder."
        case .bdNotFound(let searched):
            "Couldn't find the bd executable. Looked in: \(searched.joined(separator: ", ")). Set BD_PATH to override."
        case .commandFailed(let exitCode, let message):
            "bd exited with status \(exitCode): \(message.isEmpty ? "no error output" : message)"
        case .timedOut(let seconds):
            "bd didn't answer within \(seconds) seconds."
        case .unreadableOutput(let detail):
            "bd returned output that couldn't be read: \(detail)"
        }
    }
}

public struct BDExecutableLocator: Sendable {
    private let environment: [String: String]
    private let homeDirectory: URL
    private let isExecutable: @Sendable (String) -> Bool

    public init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        isExecutable: @escaping @Sendable (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }
    ) {
        self.environment = environment
        self.homeDirectory = homeDirectory
        self.isExecutable = isExecutable
    }

    /// PATH first, then common install locations. Apps launched from Finder get a
    /// minimal PATH, so the fallbacks matter in practice.
    public func candidates() -> [String] {
        let fromPath = (environment["PATH"] ?? "").split(separator: ":").map { "\($0)/bd" }
        let wellKnown = [
            "/opt/homebrew/bin/bd",
            "/usr/local/bin/bd",
            homeDirectory.appendingPathComponent("go/bin/bd").path,
            homeDirectory.appendingPathComponent(".local/bin/bd").path,
        ]
        var seen: Set<String> = []
        return (fromPath + wellKnown).filter { seen.insert($0).inserted }
    }

    public func locate() throws -> URL {
        if let override = environment["BD_PATH"], !override.isEmpty, isExecutable(override) {
            return URL(fileURLWithPath: override)
        }
        let all = candidates()
        guard let found = all.first(where: isExecutable) else {
            throw BeadsDataError.bdNotFound(searched: all)
        }
        return URL(fileURLWithPath: found)
    }
}
