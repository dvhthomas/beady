import BeadsCore
import BeadsData
import Foundation
import Testing

// Output captured from bd 1.3.0 (f45b249ce).
let versionJSON = """
{
  "branch": "HEAD",
  "build": "f45b249ce",
  "commit": "f45b249ce6b40ba62aecc03949e6371e8f7c79d8",
  "schema_version": 1,
  "version": "1.3.0"
}
"""

func configJSON(_ key: String, _ value: String) -> String {
    #"{"key": "\#(key)", "location": "config.yaml", "schema_version": 1, "value": "\#(value)"}"#
}

let journalLines = """
{"seq":1,"ts":"2026-09-27T16:11:12Z","op":"create","issue_id":"demo-3km","actor":"tester","issue":{"id":"demo-3km","title":"two","status":"open","priority":2,"issue_type":"task"}}
{"seq":2,"ts":"2026-09-27T16:11:13Z","op":"update","issue_id":"demo-3km","actor":"tester","issue":{"id":"demo-3km","title":"two","status":"in_progress"}}
{"seq":3,"ts":"2026-09-27T16:11:14Z","op":"update","issue_id":"demo-9zz","issue":{"id":"demo-9zz","title":"unblocked"}}

"""

let truncatedJSON = """
{
  "code": "events_journal_truncated",
  "error": "events journal truncated: checkpoint 0 is below the retained window [2..2]; records 1..1 were pruned",
  "floor": 2,
  "head": 2,
  "schema_version": 1,
  "since": 0
}
"""

@Suite("bd commands for the events journal")
struct JournalCommandTests {
    @Test("reading the version, settings and journal never writes")
    func reads() {
        #expect(BDCommand.version.arguments == ["version", "--json"])
        // Without --readonly, bd 1.3 upgrades an older database's schema just to read a setting.
        #expect(BDCommand.configGet("events-journal").arguments == ["--readonly", "config", "get", "events-journal", "--json"])
        #expect(BDCommand.eventsTail(since: 42).arguments == ["--readonly", "events", "tail", "--since", "42", "--json"])
        #expect([BDCommand.version, .configGet("x"), .eventsTail(since: 0)].allSatisfy { $0.isReadOnly })
    }

    @Test("turning the journal on is one write, with every setting as key=value")
    func enable() {
        let command = BDCommand.configSet([
            ConfigSetting(key: "events-journal", value: "true"),
            ConfigSetting(key: "events-journal-retain-days", value: "1"),
        ])
        #expect(command.arguments == ["config", "set-many", "events-journal=true", "events-journal-retain-days=1"])
        #expect(!command.isReadOnly)
    }
}

@Suite("Decoding the journal")
struct JournalDecodingTests {
    @Test("bd's version, from `bd version --json`")
    func version() throws {
        #expect(try BDJSON.decodeVersion(Data(versionJSON.utf8)) == BeadsVersion(1, 3, 0))
        #expect(throws: BDJSON.DecodingFailure.self) { try BDJSON.decodeVersion(Data("bd version 1.3.0".utf8)) }
    }

    @Test("a setting's value, from `bd config get --json`")
    func config() throws {
        #expect(try BDJSON.decodeConfigValue(Data(configJSON("events-journal", "false").utf8)) == "false")
        #expect(throws: BDJSON.DecodingFailure.self) { try BDJSON.decodeConfigValue(Data("[]".utf8)) }
    }

    @Test("one record per line, with bd's follow-on writes keeping their missing actor")
    func records() throws {
        let read = try BDJSON.decodeJournal(Data(journalLines.utf8))
        guard case .records(let records) = read else { Testing.Issue.record("expected records, got \(read)"); return }
        #expect(records.map(\.seq) == [1, 2, 3])
        #expect(records.map(\.op) == ["create", "update", "update"])
        #expect(records.map(\.issueID) == ["demo-3km", "demo-3km", "demo-9zz"])
        #expect(records.map(\.actor) == ["tester", "tester", nil])
        #expect(records.first?.date == (try Date("2026-09-27T16:11:12Z", strategy: .iso8601)))
    }

    @Test("nothing new is an empty read")
    func empty() throws {
        #expect(try BDJSON.decodeJournal(Data()) == .records([]))
    }

    @Test("a pruned checkpoint is reported with the oldest record bd still has")
    func truncated() throws {
        #expect(try BDJSON.decodeJournal(Data(truncatedJSON.utf8)) == .truncated(floor: 2))
    }

    @Test("a line that isn't a record is skipped, not fatal")
    func oddLine() throws {
        let read = try BDJSON.decodeJournal(Data((journalLines + "not json\n{\"seq\":4}\n").utf8))
        guard case .records(let records) = read else { Testing.Issue.record("expected records"); return }
        #expect(records.map(\.seq) == [1, 2, 3])
    }
}

@Suite("bd store: the events journal")
struct BDStoreJournalTests {
    let workspace = BeadsWorkspace(projectDirectory: URL(fileURLWithPath: "/tmp/project"))
    let bd = URL(fileURLWithPath: "/opt/homebrew/bin/bd")

    func store(_ runner: FakeRunner) -> BDStore {
        BDStore(gateway: BDGateway(workspace: workspace, executable: bd, runner: runner))
    }

    func commands(_ runner: FakeRunner) -> [[String]] {
        runner.invocations.map { Array($0.arguments.dropFirst(2)) }
    }

    @Test("a bd older than 1.3 is left to the file watcher, without asking about settings it doesn't have")
    func oldVersion() async {
        let runner = FakeRunner { _ in ok(#"{"version": "0.62.1"}"#) }
        #expect(await store(runner).journalStatus() == .unsupported(BeadsVersion(0, 62, 1)))
        #expect(commands(runner) == [BDCommand.version.arguments])
    }

    @Test("a version bd won't give is treated as too old")
    func unknownVersion() async {
        let runner = FakeRunner { _ in CommandResult(exitCode: 1, stdout: Data(), stderr: "unknown command") }
        #expect(await store(runner).journalStatus() == .unsupported(nil))
    }

    @Test("with 1.3, reads whether the journal is on and how long it keeps records")
    func settings() async {
        let runner = FakeRunner { args in
            if args.contains("version") { return ok(versionJSON) }
            if args.contains("events-journal") { return ok(configJSON("events-journal", "false")) }
            if args.contains("events-journal-retain-days") { return ok(configJSON("events-journal-retain-days", "7")) }
            return ok(configJSON("events-journal-retain-rows", "100000"))
        }
        let status = await store(runner).journalStatus()
        #expect(status == .supported(BeadsVersion(1, 3, 0), JournalSettings(isEnabled: false, retainDays: 7, retainRows: 100_000)))
        #expect(commands(runner) == [
            BDCommand.version.arguments,
            BDCommand.configGet("events-journal").arguments,
            BDCommand.configGet("events-journal-retain-days").arguments,
            BDCommand.configGet("events-journal-retain-rows").arguments,
        ])
    }

    @Test("reads the journal after a checkpoint")
    func reading() async throws {
        let runner = FakeRunner { _ in ok(journalLines) }
        let read = try await store(runner).journalRecords(after: 7)
        #expect(commands(runner) == [BDCommand.eventsTail(since: 7).arguments])
        guard case .records(let records) = read else { Testing.Issue.record("expected records"); return }
        #expect(records.count == 3)
    }

    @Test("bd exits 1 for a pruned checkpoint; that's an answer, not a failure")
    func truncated() async throws {
        let runner = FakeRunner { _ in CommandResult(exitCode: 1, stdout: Data(truncatedJSON.utf8), stderr: "") }
        #expect(try await store(runner).journalRecords(after: 0) == .truncated(floor: 2))
    }

    @Test("any other failure is bd's own error")
    func failure() async {
        let runner = FakeRunner { _ in CommandResult(exitCode: 1, stdout: Data(), stderr: "Error: database locked") }
        await #expect(throws: BeadsDataError.commandFailed(exitCode: 1, message: "Error: database locked")) {
            try await store(runner).journalRecords(after: 0)
        }
    }

    @Test("turning it on writes exactly the settings asked for, and says so beforehand")
    func enabling() async throws {
        let runner = FakeRunner { _ in ok("") }
        let settings = [ConfigSetting(key: "events-journal", value: "true")]
        let store = store(runner)
        try await store.enableJournal(settings)
        #expect(commands(runner) == [["config", "set-many", "events-journal=true"]])
        #expect(store.journalCommandPreview(settings) == ["bd -C /tmp/project config set-many events-journal=true"])
    }
}
