import BeadsCore
import BeadsData
import Foundation
import Testing

private func scratch(_ variable: String) -> String? {
    guard let path = ProcessInfo.processInfo.environment[variable] else { return nil }
    let marker = URL(fileURLWithPath: path).appendingPathComponent(".beady-scratch")
    return FileManager.default.fileExists(atPath: marker.path) ? path : nil
}

private let olderSchemaWorkspace = scratch("BEADY_IT_OLDER_SCHEMA_WORKSPACE")
private let newerSchemaWorkspace = scratch("BEADY_IT_NEWER_SCHEMA_WORKSPACE")

/// Opt-in, and destructive to its target, so each needs a `.beady-scratch` marker:
///     BEADY_IT_OLDER_SCHEMA_WORKSPACE=/path  a workspace written by an older bd than BD_PATH
///     BEADY_IT_NEWER_SCHEMA_WORKSPACE=/path  a workspace upgraded by a newer bd than BD_PATH
@Suite("bd integration: schema mismatches", .serialized)
struct SchemaIntegrationTests {
    @Test("an older database is reported, copied as it is, upgraded, and then reads",
          .enabled(if: olderSchemaWorkspace != nil))
    func upgradesOlder() async throws {
        let path = try #require(olderSchemaWorkspace)
        let store = BDStore(gateway: try BDGateway.open(URL(fileURLWithPath: path)))

        // Everything the window asks for around a load. Before --readonly was added to two of
        // these, bd 1.3 upgraded the schema here without asking.
        _ = await store.journalStatus()
        _ = try? await store.backupStatus()
        _ = try? await store.journalRecords(after: 0)
        _ = try? await store.recentActivity(since: .distantPast)

        var mismatch: SchemaMismatch?
        do { _ = try await store.loadSnapshot() } catch let error as SchemaMismatch { mismatch = error }
        let found = try #require(mismatch, "still on the older schema: nothing above may upgrade it")
        #expect(found.direction == .behind)

        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("beady-it-copy-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let copy = try await store.copyDatabase(into: folder.path, schema: found.databaseVersion, at: Date())

        try await store.upgradeSchema()
        #expect(!(try await store.loadSnapshot().issues.isEmpty))

        // The copy is still the old database: this bd, which just upgraded the original, refuses it.
        let copied = URL(fileURLWithPath: copy)
        let project = folder.appendingPathComponent("copy-project")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: copied, to: project.appendingPathComponent(".beads"))
        let copyStore = BDStore(gateway: try BDGateway.open(project))
        await #expect(throws: SchemaMismatch.self) { _ = try await copyStore.loadSnapshot() }
    }

    @Test("a newer database is reported, and can still be read past it",
          .enabled(if: newerSchemaWorkspace != nil))
    func readsNewer() async throws {
        let path = try #require(newerSchemaWorkspace)
        let store = BDStore(gateway: try BDGateway.open(URL(fileURLWithPath: path)))
        var mismatch: SchemaMismatch?
        do { _ = try await store.loadSnapshot() } catch let error as SchemaMismatch { mismatch = error }
        #expect(mismatch?.direction == .ahead)
        #expect(!(try await store.loadSnapshot(ignoringSchemaSkew: true).issues.isEmpty))
    }
}
