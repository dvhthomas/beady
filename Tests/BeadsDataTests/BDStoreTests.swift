import BeadsCore
import BeadsData
import Foundation
import Testing

/// BDStore is BeadsCore's `BeadsStore` port implemented entirely through `BDGateway`.
@Suite("bd store: loading")
struct BDStoreLoadingTests {
    let workspace = BeadsWorkspace(projectDirectory: URL(fileURLWithPath: "/tmp/project"))
    let bd = URL(fileURLWithPath: "/opt/homebrew/bin/bd")

    func store(_ runner: FakeRunner) -> BDStore {
        BDStore(gateway: BDGateway(workspace: workspace, executable: bd, runner: runner))
    }

    @Test("loading runs only read-only list and statuses")
    func readOnlyInvocations() async throws {
        let runner = FakeRunner { args in args.contains("statuses") ? ok(sampleStatusesJSON) : ok(sampleListJSON) }
        _ = try await store(runner).loadSnapshot()
        #expect(runner.invocations.map { Array($0.arguments.dropFirst(2)) } == [BDCommand.list.arguments, BDCommand.statuses.arguments])
    }

    @Test("builds a snapshot using the database's own status categories")
    func snapshot() async throws {
        let runner = FakeRunner { args in args.contains("statuses") ? ok(sampleStatusesJSON) : ok(sampleListJSON) }
        let snapshot = try await store(runner).loadSnapshot()
        #expect(snapshot.issues.map(\.id) == ["demo-ep1", "demo-ep1.1", "demo-ep1.2", "demo-xyz"])
        #expect(snapshot.catalog.category(of: "review") == .wip)
        #expect(snapshot.children(of: "demo-ep1").count == 2)
    }

    @Test("warnings on stderr don't fail a successful command")
    func stderrWarnings() async throws {
        let runner = FakeRunner { _ in ok(sampleListJSON, stderr: "warning: beads.role not configured") }
        #expect(try await store(runner).loadSnapshot().issues.count == 4)
    }

    @Test("falls back to built-in statuses if bd can't list them")
    func statusesFallback() async throws {
        let runner = FakeRunner { args in
            args.contains("statuses") ? CommandResult(exitCode: 1, stdout: Data(), stderr: "unknown command") : ok(sampleListJSON)
        }
        let snapshot = try await store(runner).loadSnapshot()
        #expect(snapshot.catalog == .builtIn)
        #expect(snapshot.issues.count == 4)
    }

    @Test("a failing list surfaces bd's own error message")
    func listFailure() async {
        let runner = FakeRunner { _ in CommandResult(exitCode: 1, stdout: Data(), stderr: "Error: no beads database found\n") }
        await #expect(throws: BeadsDataError.commandFailed(exitCode: 1, message: "Error: no beads database found")) {
            try await store(runner).loadSnapshot()
        }
    }

    @Test("unreadable output is reported; unreadable records are counted, not fatal")
    func unreadable() async throws {
        await #expect(throws: BeadsDataError.self) { try await store(FakeRunner { _ in ok("not json") }).loadSnapshot() }
        let partial = FakeRunner { _ in ok(#"[{"id": "ok-1", "title": "Fine", "status": "open"}, {"title": "no id"}]"#) }
        let snapshot = try await store(partial).loadSnapshot()
        #expect(snapshot.issues.map(\.id) == ["ok-1"])
        #expect(snapshot.unreadableRecordCount == 1)
    }
}

@Suite("bd store: reading live and writing")
struct BDStoreWritingTests {
    let workspace = BeadsWorkspace(projectDirectory: URL(fileURLWithPath: "/tmp/project"))
    let bd = URL(fileURLWithPath: "/opt/homebrew/bin/bd")

    func store(_ runner: FakeRunner) -> BDStore {
        BDStore(gateway: BDGateway(workspace: workspace, executable: bd, runner: runner))
    }

    func commands(_ runner: FakeRunner) -> [[String]] {
        runner.invocations.map { Array($0.arguments.dropFirst(2)) }
    }

    @Test("an edit becomes one update with only the changed fields")
    func edit() async throws {
        let runner = FakeRunner { _ in ok("[]") }
        let id = try await store(runner).apply(.edit("demo-1", IssueEdit(title: "-p 0 --force", description: "two\nlines", priority: 1)))
        #expect(id == "demo-1")
        #expect(commands(runner) == [
            BDCommand.updateFields("demo-1", IssueEdit(title: "-p 0 --force", description: "two\nlines", priority: 1)).arguments,
        ])
    }

    @Test("closing uses close with the reason; plain moves use update --status; leaving closed reopens first")
    func statuses() async throws {
        let runner = FakeRunner { _ in ok("[]") }
        let s = store(runner)
        _ = try await s.apply(.setStatus("demo-1", from: "open", to: "closed", reason: "shipped"))
        _ = try await s.apply(.setStatus("demo-2", from: "open", to: "in_progress", reason: nil))
        _ = try await s.apply(.setStatus("demo-3", from: "closed", to: "in_progress", reason: "not done"))
        _ = try await s.apply(.setStatus("demo-4", from: "closed", to: "open", reason: nil))
        #expect(commands(runner) == [
            BDCommand.close("demo-1", reason: "shipped").arguments,
            BDCommand.setStatus("demo-2", "in_progress").arguments,
            BDCommand.reopen("demo-3", reason: "not done").arguments,
            BDCommand.setStatus("demo-3", "in_progress").arguments,
            BDCommand.reopen("demo-4", reason: nil).arguments,
        ])
    }

    @Test("reparenting sets the parent, and removing it passes an empty parent")
    func parent() async throws {
        let runner = FakeRunner { _ in ok("[]") }
        _ = try await store(runner).apply(.setParent("demo-1", from: "epic-a", to: "epic-b"))
        _ = try await store(runner).apply(.setParent("demo-1", from: "epic-b", to: nil))
        #expect(commands(runner) == [BDCommand.setParent("demo-1", "epic-b").arguments, BDCommand.setParent("demo-1", nil).arguments])
    }

    @Test("creating runs bd's dry run first, then creates and returns the new id")
    func create() async throws {
        let runner = FakeRunner { args in
            args.contains("--dry-run") ? ok(#"{"id": "", "title": "New"}"#) : ok(#"{"id": "demo-9", "title": "New"}"#)
        }
        let new = NewIssue(title: "New", type: "bug", priority: 1, description: "why", parent: "epic-a")
        #expect(try await store(runner).apply(.create(new)) == "demo-9")
        #expect(commands(runner) == [BDCommand.create(new, dryRun: true).arguments, BDCommand.create(new, dryRun: false).arguments])
    }

    @Test("a failed dry run stops the create")
    func createDryRunFails() async {
        let runner = FakeRunner { _ in CommandResult(exitCode: 1, stdout: Data(), stderr: "Error: parent not found") }
        await #expect(throws: BeadsDataError.commandFailed(exitCode: 1, message: "Error: parent not found")) {
            try await store(runner).apply(.create(NewIssue(title: "New", parent: "ghost")))
        }
        #expect(runner.invocations.count == 1)
    }

    @Test("live reads use read-only show and understand its dependency shape")
    func currentIssue() async throws {
        let showJSON = """
        [{"id": "demo-1", "title": "Child", "status": "open", "priority": 2, "issue_type": "task",
          "created_at": "2026-09-14T01:00:00Z", "updated_at": "2026-09-14T02:00:00Z", "parent": "epic-a",
          "dependencies": [
            {"id": "epic-a", "dependency_type": "parent-child", "title": "Epic", "status": "open"},
            {"id": "demo-0", "dependency_type": "blocks", "title": "Blocker", "status": "open"}
          ]}]
        """
        let runner = FakeRunner { _ in ok(showJSON) }
        let issue = try #require(try await store(runner).currentIssue("demo-1"))
        #expect(issue.parentID == "epic-a")
        #expect(issue.dependencies.contains(Dependency(issueID: "demo-1", dependsOnID: "demo-0", kind: .blocks)))
        #expect(commands(runner) == [BDCommand.show("demo-1").arguments])
    }

    @Test("a missing issue reads as nil; other failures throw")
    func currentIssueMissing() async throws {
        let missing = FakeRunner { _ in CommandResult(exitCode: 1, stdout: Data(), stderr: "Error: no issue found matching \"demo-x\"") }
        #expect(try await store(missing).currentIssue("demo-x") == nil)
        let broken = FakeRunner { _ in CommandResult(exitCode: 1, stdout: Data(), stderr: "Error: database locked") }
        await #expect(throws: BeadsDataError.self) { try await store(broken).currentIssue("demo-x") }
    }

    @Test("finding beads created since a moment matches the title exactly")
    func issuesCreated() async throws {
        let listJSON = """
        [
          {"id": "demo-1", "title": "New", "status": "open", "created_at": "2026-09-14T10:00:00Z", "updated_at": "2026-09-14T10:00:00Z"},
          {"id": "demo-2", "title": "New", "status": "open", "created_at": "2026-09-14T09:00:00Z", "updated_at": "2026-09-14T09:00:00Z"},
          {"id": "demo-3", "title": "New and improved", "status": "open", "created_at": "2026-09-14T10:00:00Z", "updated_at": "2026-09-14T10:00:00Z"}
        ]
        """
        let runner = FakeRunner { _ in ok(listJSON) }
        let since = try #require(ISO8601DateFormatter().date(from: "2026-09-14T09:59:58Z"))
        #expect(try await store(runner).issuesCreated(titled: "New", since: since).map(\.id) == ["demo-1"])
        #expect(commands(runner) == [BDCommand.listTitled("New").arguments])
    }

    @Test("the preview lists every command the change will run, including a create's dry run")
    func preview() {
        let s = store(FakeRunner { _ in ok("") })
        #expect(s.commandPreview(for: .setStatus("demo-1", from: "closed", to: "in_progress", reason: "it's back")) == [
            "bd -C /tmp/project reopen '--reason=it'\\''s back' --json -- demo-1",
            "bd -C /tmp/project update --status=in_progress --json -- demo-1",
        ])
        #expect(s.commandPreview(for: .create(NewIssue(title: "New bead"))) == [
            "bd -C /tmp/project create '--title=New bead' --type=task --priority=2 --dry-run --json",
            "bd -C /tmp/project create '--title=New bead' --type=task --priority=2 --json",
        ])
    }
}
