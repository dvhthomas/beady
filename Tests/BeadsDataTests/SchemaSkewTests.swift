import BeadsCore
import BeadsData
import Foundation
import Testing

// Output captured from bd 1.3.0 (behind) and bd 1.2.2 (ahead) on the same workspace.
let schemaBehindError = "Error: failed to open database: schema version mismatch: database is at v53, binary expects v66, and the read-only open cannot migrate it; run any bd write command in that workspace to migrate, or set BD_IGNORE_SCHEMA_SKEW=1 to read anyway (queries touching newer schema may fail)"

let schemaAheadJSON = """
{
  "error": "schema version mismatch: database is at v66, binary knows up to v53 (13 migrations ahead)",
  "hint": "BD_IGNORE_SCHEMA_SKEW=1 bd \\u003ccommand\\u003e  or  bd --ignore-schema-skew \\u003ccommand\\u003e",
  "schema_skew": {
    "current_version": 66,
    "delta": 13,
    "required_version": 53
  },
  "schema_version": 1
}
"""

// bd 1.3.0's refusal when another clone has already migrated the shared remote
// (internal/storage/schema/remote_migrate_gate.go).
let remoteRefusal = "Error: refusing to migrate a remote-backed database (v53 -> v66): the remote is already migrated — adopt it instead of migrating here (#4259)"

@Suite("Recognising a schema mismatch")
struct SchemaMismatchDecodingTests {
    @Test("a database older than this bd: it can be upgraded here")
    func behind() {
        #expect(BDJSON.schemaMismatch(in: schemaBehindError) == SchemaMismatch(.behind, database: 53, bd: 66))
    }

    @Test("a database a newer bd has upgraded: this bd is the one out of date")
    func ahead() {
        #expect(BDJSON.schemaMismatch(in: schemaAheadJSON) == SchemaMismatch(.ahead, database: 66, bd: 53))
        #expect(BDJSON.schemaMismatch(in: "schema version mismatch: database is at v66, binary knows up to v53 (13 migrations ahead)")
            == SchemaMismatch(.ahead, database: 66, bd: 53))
    }

    @Test("any other failure is not a mismatch")
    func otherErrors() {
        #expect(BDJSON.schemaMismatch(in: "Error: database locked") == nil)
        #expect(BDJSON.schemaMismatch(in: "") == nil)
    }
}

@Suite("bd commands for schema upgrades")
struct SchemaCommandTests {
    @Test("upgrading is bd's own explicit migration, and it's a write")
    func migrate() {
        #expect(BDCommand.migrateSchema.arguments == ["migrate", "schema"])
        #expect(!BDCommand.migrateSchema.isReadOnly)
    }
}

@Suite("bd store: schema mismatches")
struct BDStoreSchemaTests {
    let workspace = BeadsWorkspace(projectDirectory: URL(fileURLWithPath: "/tmp/project"))
    let bd = URL(fileURLWithPath: "/opt/homebrew/bin/bd")

    func store(_ runner: FakeRunner, workspace: BeadsWorkspace? = nil) -> BDStore {
        BDStore(gateway: BDGateway(workspace: workspace ?? self.workspace, executable: bd, runner: runner))
    }

    func commands(_ runner: FakeRunner) -> [[String]] {
        runner.invocations.map { Array($0.arguments.dropFirst(2)) }
    }

    @Test("a load that fails on the schema says so, rather than passing bd's message along")
    func loadThrowsMismatch() async {
        let runner = FakeRunner { _ in CommandResult(exitCode: 1, stdout: Data(), stderr: schemaBehindError) }
        await #expect(throws: SchemaMismatch(.behind, database: 53, bd: 66)) {
            try await store(runner).loadSnapshot()
        }
    }

    @Test("bd reports a newer database as JSON on stderr; that's recognised too")
    func loadThrowsAhead() async {
        let runner = FakeRunner { _ in CommandResult(exitCode: 1, stdout: Data(), stderr: schemaAheadJSON) }
        await #expect(throws: SchemaMismatch(.ahead, database: 66, bd: 53)) {
            try await store(runner).loadSnapshot()
        }
    }

    @Test("reading past a mismatch asks bd to, on every read it makes")
    func ignoringSkew() async throws {
        let runner = FakeRunner { args in args.contains("statuses") ? ok("{}") : ok(sampleListJSON) }
        _ = try await store(runner).loadSnapshot(ignoringSchemaSkew: true)
        #expect(commands(runner) == [
            ["--ignore-schema-skew"] + BDCommand.list.arguments,
            ["--ignore-schema-skew"] + BDCommand.statuses.arguments,
        ])
    }

    @Test("an ordinary load doesn't ask bd to ignore anything")
    func notIgnoringSkew() async throws {
        let runner = FakeRunner { args in args.contains("statuses") ? ok("{}") : ok(sampleListJSON) }
        _ = try await store(runner).loadSnapshot(ignoringSchemaSkew: false)
        #expect(commands(runner) == [BDCommand.list.arguments, BDCommand.statuses.arguments])
    }

    @Test("upgrading runs bd's migration and nothing else")
    func upgrade() async throws {
        let runner = FakeRunner { _ in ok("✓ Schema already at v66\n") }
        let store = store(runner)
        try await store.upgradeSchema()
        #expect(commands(runner) == [BDCommand.migrateSchema.arguments])
        #expect(store.schemaUpgradePreview() == ["bd -C /tmp/project migrate schema"])
    }

    @Test("bd refusing to migrate a shared remote is a decision for a person, not an error to retry")
    func refused() async {
        let runner = FakeRunner { _ in CommandResult(exitCode: 1, stdout: Data(), stderr: remoteRefusal) }
        await #expect(throws: SchemaUpgradeRefused(message: String(remoteRefusal.dropFirst("Error: ".count)))) {
            try await store(runner).upgradeSchema()
        }
    }

    @Test("any other upgrade failure is bd's own error")
    func upgradeFails() async {
        let runner = FakeRunner { _ in CommandResult(exitCode: 1, stdout: Data(), stderr: "Error: disk full") }
        await #expect(throws: BeadsDataError.commandFailed(exitCode: 1, message: "Error: disk full")) {
            try await store(runner).upgradeSchema()
        }
    }

    @Test("the copy taken before an upgrade is the whole .beads folder, untouched by bd, with the old schema in its name")
    func copyBeforeUpgrade() async throws {
        let project = try makeTempDirectory().appendingPathComponent("my-project")
        let beads = project.appendingPathComponent(".beads")
        try FileManager.default.createDirectory(at: beads.appendingPathComponent("embeddeddolt/db"), withIntermediateDirectories: true)
        try Data("noms".utf8).write(to: beads.appendingPathComponent("embeddeddolt/db/journal"))
        try Data("x: 1".utf8).write(to: beads.appendingPathComponent("config.yaml"))
        let destination = try makeTempDirectory()

        let runner = FakeRunner { _ in Testing.Issue.record("copying must not run bd"); return ok("") }
        let moment = Date(timeIntervalSince1970: 1_800_000_000)
        let copy = try await store(runner, workspace: BeadsWorkspace(projectDirectory: project))
            .copyDatabase(into: destination.path, schema: 53, at: moment)

        let expectedName = "my-project-beads-v53-" + BDGateway.copyStamp(moment)
        #expect(URL(fileURLWithPath: copy).lastPathComponent == expectedName)
        #expect(try String(contentsOfFile: copy + "/embeddeddolt/db/journal", encoding: .utf8) == "noms")
        #expect(try String(contentsOfFile: copy + "/config.yaml", encoding: .utf8) == "x: 1")
        #expect(FileManager.default.fileExists(atPath: beads.appendingPathComponent("config.yaml").path), "the original stays put")
        #expect(runner.invocations.isEmpty)
    }

    @Test("a copy never overwrites an earlier one")
    func copyRefusesToOverwrite() async throws {
        let project = try makeTempDirectory().appendingPathComponent("p")
        try FileManager.default.createDirectory(at: project.appendingPathComponent(".beads"), withIntermediateDirectories: true)
        let destination = try makeTempDirectory()
        let moment = Date(timeIntervalSince1970: 1_800_000_000)
        let gatewayStore = store(FakeRunner { _ in ok("") }, workspace: BeadsWorkspace(projectDirectory: project))
        _ = try await gatewayStore.copyDatabase(into: destination.path, schema: 53, at: moment)
        await #expect(throws: (any Error).self) {
            _ = try await gatewayStore.copyDatabase(into: destination.path, schema: 53, at: moment)
        }
    }
}
