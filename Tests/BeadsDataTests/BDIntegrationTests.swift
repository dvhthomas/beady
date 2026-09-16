import BeadsCore
import BeadsData
import Foundation
import Testing

private let integrationWorkspace = ProcessInfo.processInfo.environment["BEADY_IT_WORKSPACE"]

/// Opt-in: BEADY_IT_WORKSPACE=/path/to/project scripts/test.sh
/// Uses the real bd binary against an existing workspace, read-only.
@Suite("bd integration", .enabled(if: integrationWorkspace != nil))
struct BDIntegrationTests {
    func open() throws -> (BDGateway, BDStore) {
        let path = try #require(integrationWorkspace)
        let gateway = try BDGateway.open(URL(fileURLWithPath: path))
        return (gateway, BDStore(gateway: gateway))
    }

    @Test("loads a real workspace, and reading doesn't register as a change")
    func realWorkspace() async throws {
        let (_, store) = try open()
        let snapshot = try await store.loadSnapshot()
        #expect(!snapshot.issues.isEmpty)
        #expect(snapshot.catalog.category(of: "in_progress") == .wip)
        #expect(snapshot.issues.allSatisfy { $0.createdAt != .distantPast })

        let before = await store.changeToken()
        _ = try await store.loadSnapshot()
        #expect(await store.changeToken() == before, "a read must not look like a write, or auto-refresh would loop")
    }

    @Test("Ready and Blocked match bd's own `bd ready` and `bd blocked`")
    func parityWithBd() async throws {
        let (gateway, store) = try open()
        let before = try await store.loadSnapshot()
        let bdReady = try ids(await gateway.run(.ready))
        let bdBlocked = try ids(await gateway.run(.blocked))
        let after = try await store.loadSnapshot()
        // Other sessions may be writing to the database; only compare a quiet moment.
        guard before.issues == after.issues else {
            print("parity check skipped: the database changed while comparing")
            return
        }
        print("parity check compared \(after.issues.count) issues")

        let now = Date()
        let ready = Set(after.issues.filter { Scope.ready.includes($0, in: after, now: now) }.map(\.id.rawValue))
        let blocked = Set(after.issues.filter { Scope.blocked.includes($0, in: after, now: now) }.map(\.id.rawValue))
        #expect(ready == bdReady, "only ours: \(ready.subtracting(bdReady)); only bd: \(bdReady.subtracting(ready))")
        #expect(blocked == bdBlocked, "only ours: \(blocked.subtracting(bdBlocked)); only bd: \(bdBlocked.subtracting(blocked))")
    }

    private func ids(_ output: Data) throws -> Set<String> {
        let records = try JSONSerialization.jsonObject(with: output) as? [[String: Any]] ?? []
        return Set(records.compactMap { record in
            (record["id"] as? String) ?? ((record["issue"] as? [String: Any])?["id"] as? String)
        })
    }
}
