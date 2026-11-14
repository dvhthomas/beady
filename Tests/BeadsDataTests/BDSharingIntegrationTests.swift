import BeadsCore
import BeadsData
import Foundation
import Testing

private let writableWorkspace: String? = {
    guard let path = ProcessInfo.processInfo.environment["BEADY_IT_WRITABLE_WORKSPACE"] else { return nil }
    let marker = URL(fileURLWithPath: path).appendingPathComponent(".beady-scratch")
    return FileManager.default.fileExists(atPath: marker.path) ? path : nil
}()

/// Opt-in, behind the same gate as the other tests that run the real bd and write to disk:
///     BEADY_IT_WRITABLE_WORKSPACE=/path/to/scratch scripts/test.sh
/// It never touches that workspace. It makes a bare git repository and two clones of it in a
/// temporary folder, shares beads from one, joins from the other, and syncs both ways — the
/// whole of plan 0006's journey, the way the app runs it.
@Suite("bd sharing integration", .enabled(if: writableWorkspace != nil), .serialized)
struct BDSharingIntegrationTests {
    let runner = ProcessCommandRunner()

    func git(_ arguments: [String], in directory: URL? = nil) async throws {
        let identity = ["-c", "user.name=Beady Tests", "-c", "user.email=tests@example.invalid"]
        let result = try await runner.run(URL(fileURLWithPath: "/usr/bin/git"), arguments: identity + arguments, directory: directory, timeout: 60)
        #expect(result.exitCode == 0, Comment(rawValue: "git \(arguments.joined(separator: " ")): \(result.stderr)"))
    }

    @Test("share from one clone, join from a fresh one, and sync a change each way")
    func roundTrip() async throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let origin = root.appendingPathComponent("origin.git")
        let first = root.appendingPathComponent("first")
        let second = root.appendingPathComponent("second")

        try await git(["init", "-q", "--bare", origin.path])
        try await git(["clone", "-q", origin.path, first.path])
        try await git(["commit", "-q", "--allow-empty", "-m", "start"], in: first)
        // The origin has code on it, as a real one does: bd refuses to publish to a git remote
        // with no branch at all ("initialize the repository with an initial branch/commit first").
        try await git(["push", "-q", "origin", "HEAD"], in: first)

        // A database made the way the app makes one: bd wires the origin and publishes nothing.
        _ = try await BDGateway.forNewWorkspace(at: first).run(.initDatabase(prefix: "share"))
        let firstStore = BDStore(gateway: try BDGateway.open(first))
        let wired = try await firstStore.sharingFacts()
        #expect(wired.remote?.name == "origin")
        #expect(SharingState.derive(wired) == .neverPublished(try #require(wired.remote)))
        #expect(await firstStore.gitOriginURL() == origin.path)

        // The first publish is a push; a sync against an empty remote fails, in bd's words.
        let created = try await ChangeRunner(writer: firstStore).run(
            .create(NewIssue(title: "shared bead")), seenIn: try await firstStore.loadSnapshot()
        )
        guard case .failed = try await firstStore.sync() else {
            Issue.record("bd sync was expected to refuse an empty remote; the first publish may no longer need bd dolt push")
            return
        }
        try await firstStore.perform(.publish)
        let published = try await firstStore.sharingFacts()
        #expect(SharingState.derive(published) == .inSync(try #require(published.remote)))

        // bd's config travels with the code, so the second clone knows it uses beads.
        try await git(["push", "-q", "origin", "HEAD"], in: first)
        try await git(["clone", "-q", origin.path, second.path])
        let fresh = BeadsWorkspace.inspect(second)
        #expect(fresh.hasBeadsDatabase, "the tracked configuration arrived")
        #expect(!fresh.hasDatabaseFiles, "the database did not")

        // Joining: bd's plan is to clone, and running it inside the folder does.
        let joining = try BDGateway.forNewWorkspace(at: second)
        #expect(try await joining.bootstrapPlan().clonesFromRemote)
        _ = try await joining.run(.bootstrap)
        #expect(BeadsWorkspace.inspect(second).hasDatabaseFiles)
        let secondStore = BDStore(gateway: try BDGateway.open(second))
        #expect(try await secondStore.loadSnapshot().issues.map(\.id) == [created])

        // A change in the second clone reaches the first: counted before the pull, there after it.
        _ = try await BDGateway.open(second).run(.updateFields(created, IssueEdit(title: "renamed in the second clone")))
        #expect(try await secondStore.sync() == .synced)
        let behind = try await firstStore.sharingFacts()
        guard case .pending(_, toSend: 0, toReceive: let toReceive) = SharingState.derive(behind), toReceive > 0 else {
            Issue.record("the first clone should be behind: \(SharingState.derive(behind))")
            return
        }
        #expect(try await firstStore.sync() == .synced)
        #expect(try await firstStore.currentIssue(created)?.title == "renamed in the second clone")
        let level = try await firstStore.sharingFacts()
        #expect(SharingState.derive(level) == .inSync(try #require(level.remote)))
    }
}
