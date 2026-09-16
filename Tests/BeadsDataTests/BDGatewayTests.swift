import BeadsCore
import BeadsData
import Foundation
import Testing

@Suite("bd commands")
struct BDCommandTests {
    @Test("reads always carry --readonly")
    func reads() {
        #expect(BDCommand.list.arguments == ["--readonly", "list", "--json", "--all", "--limit", "0", "--flat"])
        #expect(BDCommand.listTitled("New").arguments == [
            "--readonly", "list", "--json", "--all", "--limit", "0", "--flat", "--title-contains=New",
        ])
        #expect(BDCommand.statuses.arguments == ["--readonly", "statuses", "--json"])
        #expect(BDCommand.show("demo-1").arguments == ["--readonly", "show", "--id=demo-1", "--json"])
        #expect(BDCommand.ready.arguments == ["--readonly", "ready", "--json", "--limit", "0"])
        #expect(BDCommand.blocked.arguments == ["--readonly", "blocked", "--json"])
    }

    @Test("writes pass values with = and put the id after --, so nothing can be read as a flag")
    func writes() {
        #expect(BDCommand.updateFields("demo-1", title: "-p 0 --force", description: "two\nlines", notes: nil, priority: 1).arguments == [
            "update", "--title=-p 0 --force", "--description=two\nlines", "--priority=1", "--json", "--", "demo-1",
        ])
        #expect(BDCommand.setStatus("demo-1", "in_progress").arguments == ["update", "--status=in_progress", "--json", "--", "demo-1"])
        #expect(BDCommand.setParent("demo-1", "epic-b").arguments == ["update", "--parent=epic-b", "--json", "--", "demo-1"])
        #expect(BDCommand.setParent("demo-1", nil).arguments == ["update", "--parent=", "--json", "--", "demo-1"])
        #expect(BDCommand.close("demo-1", reason: "shipped").arguments == ["close", "--reason=shipped", "--json", "--", "demo-1"])
        #expect(BDCommand.reopen("demo-1", reason: nil).arguments == ["reopen", "--json", "--", "demo-1"])
        let new = NewIssue(title: "New", type: "bug", priority: 1, description: "why", parent: "epic-a")
        #expect(BDCommand.create(new, dryRun: true).arguments == [
            "create", "--title=New", "--type=bug", "--priority=1", "--parent=epic-a", "--description=why", "--dry-run", "--json",
        ])
        #expect(BDCommand.create(new, dryRun: false).arguments.last == "--json")
    }

    @Test("exactly the mutating commands are writes, and no write claims --readonly")
    func classification() {
        let reads: [BDCommand] = [.list, .listTitled("x"), .statuses, .show("x"), .ready, .blocked]
        let writes: [BDCommand] = [
            .updateFields("x", title: "t", description: nil, notes: nil, priority: nil),
            .setStatus("x", "open"), .setParent("x", "y"), .close("x", reason: "r"),
            .reopen("x", reason: nil), .create(NewIssue(title: "t"), dryRun: false),
        ]
        #expect(reads.allSatisfy { $0.isReadOnly && $0.arguments.first == "--readonly" })
        #expect(writes.allSatisfy { !$0.isReadOnly && !$0.arguments.contains("--readonly") })
    }
}

@Suite("bd gateway")
struct BDGatewayTests {
    let workspace = BeadsWorkspace(projectDirectory: URL(fileURLWithPath: "/tmp/project"))
    let bd = URL(fileURLWithPath: "/opt/homebrew/bin/bd")

    @Test("every command runs the one bd executable against the chosen workspace")
    func runsInWorkspace() async throws {
        let runner = FakeRunner { _ in ok("[]") }
        let gateway = BDGateway(workspace: workspace, executable: bd, runner: runner)
        _ = try await gateway.run(.list)
        _ = try await gateway.run(.close("demo-1", reason: "done"))
        #expect(runner.invocations.map(\.executable) == [bd, bd])
        #expect(runner.invocations.map { Array($0.arguments.prefix(2)) } == [["-C", "/tmp/project"], ["-C", "/tmp/project"]])
        #expect(runner.invocations.map { Array($0.arguments.dropFirst(2)) } == [
            BDCommand.list.arguments, BDCommand.close("demo-1", reason: "done").arguments,
        ])
    }

    @Test("a failing command surfaces bd's own error message")
    func failure() async {
        let runner = FakeRunner { _ in CommandResult(exitCode: 1, stdout: Data(), stderr: "Error: database locked\n") }
        await #expect(throws: BeadsDataError.commandFailed(exitCode: 1, message: "Error: database locked")) {
            try await BDGateway(workspace: workspace, executable: bd, runner: runner).run(.statuses)
        }
    }

    @Test("previews are the exact command lines, including -C, quoted for a shell")
    func preview() {
        let gateway = BDGateway(workspace: workspace, executable: bd, runner: FakeRunner { _ in ok("") })
        #expect(gateway.preview(.reopen("demo-1", reason: "it's back")) == "bd -C /tmp/project reopen '--reason=it'\\''s back' --json -- demo-1")
        #expect(gateway.preview(.setParent("demo-1", nil)) == "bd -C /tmp/project update --parent= --json -- demo-1")
    }
}

@Suite("Architecture: one way in and out of beads data")
struct ArchitectureTests {
    static let sources = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Sources")

    /// Source files (relative to Sources/) whose text contains `needle`.
    func files(containing needle: String) throws -> [String] {
        let enumerator = FileManager.default.enumerator(at: Self.sources, includingPropertiesForKeys: nil)
        var hits: [String] = []
        while let url = enumerator?.nextObject() as? URL {
            guard url.pathExtension == "swift" else { continue }
            if try String(contentsOf: url, encoding: .utf8).contains(needle) {
                hits.append(String(url.standardizedFileURL.path.dropFirst(Self.sources.standardizedFileURL.path.count + 1)))
            }
        }
        return hits.sorted()
    }

    @Test("only the process runner spawns processes")
    func processes() throws {
        #expect(try files(containing: "Process()") == ["BeadsData/CommandRunner.swift"])
    }

    @Test("only the gateway runs commands and builds bd arguments")
    func gatewayOnly() throws {
        #expect(try files(containing: "runner.run(") == ["BeadsData/BDGateway.swift"])
        #expect(try files(containing: "ProcessCommandRunner(") == ["BeadsData/BDGateway.swift"])
        #expect(try files(containing: "\"--readonly\"") == ["BeadsData/BDGateway.swift"])
    }

    @Test("only the gateway reads bd's storage files")
    func storageFiles() throws {
        #expect(try files(containing: "embeddeddolt") == ["BeadsData/BDGateway.swift"])
        #expect(try files(containing: "last-touched") == ["BeadsData/BDGateway.swift"])
    }

    @Test("only the composition root knows the data layer exists")
    func compositionRoot() throws {
        #expect(try files(containing: "import BeadsData") == ["Beady/AppSession.swift"])
    }
}

@Suite("bd gateway: activity and change events")
struct BDGatewayActivityTests {
    /// A `.beads` folder with an interactions log, as bd writes one.
    func makeWorkspace(interactions: String) throws -> (BeadsWorkspace, BDGateway) {
        let dir = try makeTempDirectory()
        let beads = dir.appendingPathComponent(".beads")
        try FileManager.default.createDirectory(at: beads, withIntermediateDirectories: true)
        try Data(#"{"backend": "dolt"}"#.utf8).write(to: beads.appendingPathComponent("metadata.json"))
        try Data(interactions.utf8).write(to: beads.appendingPathComponent("interactions.jsonl"))
        let workspace = BeadsWorkspace(projectDirectory: dir)
        return (workspace, BDGateway(
            workspace: workspace,
            executable: URL(fileURLWithPath: "/usr/bin/false"),
            runner: FakeRunner { _ in ok("") }
        ))
    }

    @Test("reads bd's interaction log, newest first, skipping anything unreadable")
    func recentActivity() async throws {
        let interactions = """
        {"id": "int-1", "kind": "field_change", "created_at": "2026-09-15T14:00:00Z", "actor": "Dylan Thomas", "issue_id": "demo-1", "extra": {"field": "status"}}
        not json at all
        {"id": "int-2", "kind": "field_change", "created_at": "2026-09-15T14:05:00Z", "actor": "agent-7", "issue_id": "demo-2", "extra": {"field": "title"}}
        {"id": "int-3", "created_at": "2026-09-15T13:00:00Z", "actor": "Dylan Thomas", "issue_id": "demo-3"}

        """
        let (_, gateway) = try makeWorkspace(interactions: interactions)
        let since = try #require(ISO8601DateFormatter().date(from: "2026-09-15T13:30:00Z"))
        let log = try await gateway.recentActivity(since: since)
        #expect(log.entries.map(\.issueID) == ["demo-2", "demo-1"])
        #expect(log.entries.first?.actor == "agent-7")
        #expect(log.entries.first?.field == "title")
    }

    @Test("a missing interaction log is simply no activity")
    func missingLog() async throws {
        let dir = try makeTempDirectory()
        let beads = dir.appendingPathComponent(".beads")
        try FileManager.default.createDirectory(at: beads, withIntermediateDirectories: true)
        let gateway = BDGateway(
            workspace: BeadsWorkspace(projectDirectory: dir),
            executable: URL(fileURLWithPath: "/usr/bin/false"),
            runner: FakeRunner { _ in ok("") }
        )
        #expect(try await gateway.recentActivity(since: Date()).entries.isEmpty)
    }

    @Test("watching the workspace reports writes without touching the database")
    func watchesForChanges() async throws {
        let (workspace, gateway) = try makeWorkspace(interactions: "")
        let hits = Mutable(0)
        let watcher = gateway.watchChanges { hits.value += 1 }
        defer { watcher.stop() }

        // Let the stream start before writing, as bd would.
        try await Task.sleep(for: .milliseconds(300))
        let tokenBefore = gateway.changeToken()
        try Data("touched".utf8).write(to: workspace.beadsDirectory.appendingPathComponent("last-touched"))

        #expect(await waitUntil(seconds: 5) { hits.value > 0 }, "no change event arrived")
        #expect(gateway.changeToken() != tokenBefore)
    }

    @Test("a burst of writes wakes the app once, not once per file")
    func watchCoalescesBursts() async throws {
        let (workspace, gateway) = try makeWorkspace(interactions: "")
        let hits = Mutable(0)
        let watcher = gateway.watchChanges { hits.value += 1 }
        defer { watcher.stop() }
        try await Task.sleep(for: .milliseconds(300))

        // What an agent writing several beads looks like on disk.
        for index in 0..<6 {
            try Data("write \(index)".utf8).write(to: workspace.beadsDirectory.appendingPathComponent("issues.jsonl"))
            try await Task.sleep(for: .milliseconds(40))
        }
        #expect(await waitUntil(seconds: 5) { hits.value > 0 })
        try await Task.sleep(for: .milliseconds(600))
        #expect(hits.value == 1, "six file writes in a burst should mean one reload, not six")
    }
}
