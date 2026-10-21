import BeadsCore
import BeadsData
import Foundation
import Testing

private let writableWorkspace: String? = {
    guard let path = ProcessInfo.processInfo.environment["BEADY_IT_WRITABLE_WORKSPACE"] else { return nil }
    let marker = URL(fileURLWithPath: path).appendingPathComponent(".beady-scratch")
    return FileManager.default.fileExists(atPath: marker.path) ? path : nil
}()

/// Opt-in, behind the same gate as the other write test, since it runs the real bd and writes
/// to disk:
///     BEADY_IT_WRITABLE_WORKSPACE=/path/to/scratch scripts/test.sh
/// It never touches that workspace, though: it makes a fresh git repository in a temporary
/// folder, creates a database there the way the app does, and removes the folder afterwards.
@Suite("bd init integration", .enabled(if: writableWorkspace != nil), .serialized)
struct BDInitIntegrationTests {
    @Test("init in a temporary git repository, through the real bd, gives a workspace the app accepts")
    func initMakesAnOpenableWorkspace() async throws {
        let project = try makeTempDirectory().appendingPathComponent("Tile Engine")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: project.deletingLastPathComponent()) }
        // A real repository, not just a .git folder: bd commits its files there.
        let git = try await ProcessCommandRunner().run(
            URL(fileURLWithPath: "/usr/bin/git"), arguments: ["init", "-q", project.path], timeout: 30
        )
        #expect(git.exitCode == 0, Comment(rawValue: git.stderr))

        let before = BeadsWorkspace.inspect(project)
        #expect(!before.hasBeadsDatabase)
        #expect(before.isGitRepository)
        #expect(throws: BeadsDataError.self) { try BeadsWorkspace.resolve(project) }

        let gateway = try BDGateway.forNewWorkspace(at: project)
        _ = try await gateway.run(.initDatabase(prefix: "tile-engine"))

        let opened = try BDGateway.open(project)
        #expect(opened.workspace.projectDirectory == project.standardizedFileURL)
        #expect(BeadsWorkspace.inspect(project).hasBeadsDatabase)

        // The defaults held: no agent files or hooks, and a database that takes the prefix.
        let contents = try FileManager.default.contentsOfDirectory(atPath: project.path)
        #expect(!contents.contains("AGENTS.md"))
        #expect(!contents.contains("CLAUDE.md"))
        #expect(!FileManager.default.fileExists(atPath: opened.workspace.beadsDirectory.appendingPathComponent("hooks").path))
        let store = BDStore(gateway: opened)
        let created = try await ChangeRunner(writer: store).run(
            .create(NewIssue(title: "first bead")), seenIn: try await store.loadSnapshot()
        )
        #expect(created.rawValue.hasPrefix("tile-engine-"))
    }
}
