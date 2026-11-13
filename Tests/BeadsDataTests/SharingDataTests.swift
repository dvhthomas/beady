import BeadsCore
import BeadsData
import Foundation
import Testing

// The JSON in these tests is what bd 1.3.4 printed in throwaway repositories (plan 0006).

@Suite("Sharing: the bd commands")
struct SharingCommandTests {
    @Test("each step is the command bd's docs give for it")
    func arguments() {
        #expect(BDCommand.remoteList.arguments == ["--readonly", "dolt", "remote", "list", "--json"])
        #expect(BDCommand.sync.arguments == ["sync", "--json"])
        #expect(BDCommand.push.arguments == ["dolt", "push"])
        #expect(BDCommand.pull(keeping: .mine).arguments == ["dolt", "pull", "--strategy=ours"])
        #expect(BDCommand.pull(keeping: .theirs).arguments == ["dolt", "pull", "--strategy=theirs"])
        #expect(BDCommand.bootstrapPlan.arguments == ["--readonly", "bootstrap", "--dry-run", "--json"])
        #expect(BDCommand.bootstrap.arguments == ["bootstrap", "--yes"])
        #expect(BDCommand.context.arguments == ["--readonly", "context", "--json"])
        #expect(BDCommand.worktrees.arguments == ["--readonly", "worktree", "list", "--json"])
        #expect(BDCommand.hooks.arguments == ["--readonly", "hooks", "list", "--json"])
    }

    @Test("asking how the database stands against its remotes is not --readonly: bd would skip the fetch and call every remote unreachable")
    func peerStatus() {
        #expect(BDCommand.peerStatus.arguments == ["federation", "status", "--json"])
        #expect(!BDCommand.peerStatus.isReadOnly)
    }

    @Test("a remote's name and URL go after --, and the git origin's own URL needs bd's consent flag")
    func remoteAdd() {
        #expect(BDCommand.remoteAdd(name: "origin", url: "https://github.com/org/repo.git", allowGitOrigin: true).arguments == [
            "dolt", "remote", "add", "--allow-git-origin", "--", "origin", "https://github.com/org/repo.git",
        ])
        #expect(BDCommand.remoteAdd(name: "hub", url: "--force", allowGitOrigin: false).arguments == [
            "dolt", "remote", "add", "--", "hub", "--force",
        ])
    }

    @Test("nothing here forces, migrates or ignores a schema mismatch")
    func nothingDangerous() {
        let all: [BDCommand] = [
            .remoteList, .peerStatus, .sync, .remoteAdd(name: "origin", url: "u", allowGitOrigin: true), .push,
            .pull(keeping: .mine), .pull(keeping: .theirs), .bootstrapPlan, .bootstrap, .context, .worktrees, .hooks,
        ]
        for command in all {
            let joined = command.arguments.joined(separator: " ")
            for forbidden in ["--force", "migrate", "--ignore-schema-skew", "--discard-remote", "--reinit-local", "remove"] {
                #expect(!joined.contains(forbidden), "\(command) carries \(forbidden)")
            }
        }
    }

    @Test("reads carry --readonly and writes never do")
    func classification() {
        let reads: [BDCommand] = [.remoteList, .bootstrapPlan, .context, .worktrees, .hooks]
        let writes: [BDCommand] = [.peerStatus, .sync, .remoteAdd(name: "o", url: "u", allowGitOrigin: false), .push, .pull(keeping: .mine), .bootstrap]
        #expect(reads.allSatisfy { $0.isReadOnly && $0.arguments.first == "--readonly" })
        #expect(writes.allSatisfy { !$0.isReadOnly && !$0.arguments.contains("--readonly") })
    }
}

@Suite("Sharing: where the commands run")
struct SharingGatewayTests {
    let workspace = BeadsWorkspace(projectDirectory: URL(fileURLWithPath: "/tmp/project"))
    let bd = URL(fileURLWithPath: "/opt/homebrew/bin/bd")

    @Test("bootstrap and its plan run inside the folder: with -C bd misses the origin's data and plans a fresh, separate database")
    func bootstrapRunsInFolder() async throws {
        let runner = FakeRunner { _ in ok(#"{"action":"sync","has_existing":false,"reason":"Found Dolt data on git origin (refs/dolt/data)"}"#) }
        let gateway = BDGateway(workspace: workspace, executable: bd, runner: runner)
        let plan = try await gateway.bootstrapPlan()
        _ = try await gateway.run(.bootstrap)
        #expect(plan.clonesFromRemote)
        #expect(runner.invocations.map(\.arguments) == [BDCommand.bootstrapPlan.arguments, BDCommand.bootstrap.arguments])
        #expect(runner.invocations.allSatisfy { $0.directory == workspace.projectDirectory && !$0.arguments.contains("-C") })
        #expect(gateway.preview(.bootstrap) == "cd /tmp/project && bd bootstrap --yes")
    }

    @Test("the worktree list runs inside the folder too; bd -C reports no repository")
    func worktreesRunInFolder() async throws {
        let runner = FakeRunner { _ in ok("[]") }
        _ = try await BDGateway(workspace: workspace, executable: bd, runner: runner).run(.worktrees)
        #expect(runner.invocations.map(\.directory) == [workspace.projectDirectory])
    }

    @Test("sync, push and the remote commands go through -C like every other command")
    func theRestUseC() async throws {
        let runner = FakeRunner { _ in ok("{}") }
        let gateway = BDGateway(workspace: workspace, executable: bd, runner: runner)
        _ = try await gateway.run(.sync)
        _ = try await gateway.run(.push)
        #expect(runner.invocations.allSatisfy { $0.directory == nil && Array($0.arguments.prefix(2)) == ["-C", "/tmp/project"] })
        #expect(gateway.preview(.remoteAdd(name: "origin", url: "git@github.com:org/repo.git", allowGitOrigin: true))
            == "bd -C /tmp/project dolt remote add --allow-git-origin -- origin git@github.com:org/repo.git")
    }

    @Test("the git origin is asked of git, and no origin is an answer")
    func gitOrigin() async {
        let has = FakeRunner { _ in ok("https://github.com/org/repo.git\n") }
        #expect(await BDGateway(workspace: workspace, executable: bd, runner: has).gitOriginURL() == "https://github.com/org/repo.git")
        #expect(has.invocations.map(\.arguments) == [["git", "-C", "/tmp/project", "remote", "get-url", "origin"]])
        #expect(has.invocations.map(\.executable.path) == ["/usr/bin/env"])
        let none = FakeRunner { _ in CommandResult(exitCode: 2, stdout: Data(), stderr: "error: No such remote 'origin'") }
        #expect(await BDGateway(workspace: workspace, executable: bd, runner: none).gitOriginURL() == nil)
    }
}

@Suite("Sharing: reading what bd reports")
struct SharingDecodingTests {
    @Test("remotes come with bd's own URL form")
    func remotes() throws {
        let json = """
        [{"name": "origin", "url": "git+https://github.com/org/repo.git", "sql_url": "git+https://github.com/org/repo.git", "status": "ok"}]
        """
        #expect(try BDJSON.decodeRemotes(Data(json.utf8)) == [DoltRemote(name: "origin", url: "git+https://github.com/org/repo.git")])
        #expect(try BDJSON.decodeRemotes(Data("[]".utf8)).isEmpty)
        #expect(throws: BDJSON.DecodingFailure.self) { try BDJSON.decodeRemotes(Data("No remotes configured.".utf8)) }
    }

    @Test("counts against a remote are read as they are, and -1 as unknown")
    func peers() throws {
        let json = """
        {"peers": [
          {"ReachError": "", "Reachable": true,
           "Status": {"HasConflicts": false, "LastSync": "0001-01-01T00:00:00Z", "LocalAhead": 1, "LocalBehind": 2, "Peer": "origin"},
           "URL": "git+file:///srv/origin.git"},
          {"ReachError": "", "Reachable": true,
           "Status": {"HasConflicts": false, "LocalAhead": -1, "LocalBehind": -1, "Peer": "empty"}, "URL": "x"}
        ], "pendingChanges": 0, "schema_version": 1}
        """
        #expect(try BDJSON.decodePeers(Data(json.utf8)) == [
            PeerStatus(name: "origin", isReachable: true, ahead: 1, behind: 2),
            PeerStatus(name: "empty", isReachable: true, ahead: nil, behind: nil),
        ])
        #expect(try BDJSON.decodePeers(Data(#"{"peers": [], "pendingChanges": 0}"#.utf8)).isEmpty)
    }

    @Test("an unreachable remote keeps bd's reason")
    func unreachablePeer() throws {
        let json = """
        {"peers": [{"ReachError": "fetch from origin: Error 1105: fatal: Could not read from remote repository.\\n", "Reachable": false,
          "Status": {"LocalAhead": 0, "LocalBehind": 0, "Peer": "origin"}, "URL": "x"}]}
        """
        let peer = try #require(try BDJSON.decodePeers(Data(json.utf8)).first)
        #expect(!peer.isReachable)
        #expect(peer.reachError == "fetch from origin: Error 1105: fatal: Could not read from remote repository.")
    }

    func result(_ exit: Int32, _ stdout: String, stderr: String = "") -> CommandResult {
        CommandResult(exitCode: exit, stdout: Data(stdout.utf8), stderr: stderr)
    }

    @Test("a sync that went through, had no remote, or was told to stay local")
    func syncStatuses() {
        #expect(BDJSON.decodeSyncOutcome(result(0, #"{"attempts": 1, "pulled": true, "pushed": true, "rows_corrected": 0, "status": "ok"}"#)) == .synced)
        #expect(BDJSON.decodeSyncOutcome(result(0, #"{"attempts": 0, "pushed": false, "status": "no-remote"}"#)) == .noRemote)
        #expect(BDJSON.decodeSyncOutcome(result(0, #"{"attempts": 0, "pushed": false, "status": "disabled"}"#)) == .localOnly)
    }

    @Test("a conflict names its tables, from the words or from exit status 2 alone")
    func syncConflict() {
        let json = #"{"attempts": 1, "conflicts": ["issues"], "pushed": false, "rows_corrected": 0, "status": "conflict"}"#
        #expect(BDJSON.decodeSyncOutcome(result(2, json)) == .conflict(tables: ["issues"]))
        #expect(BDJSON.decodeSyncOutcome(result(2, "")) == .conflict(tables: []))
    }

    @Test("exit statuses 3 and 4 are busy and stuck, which bd's JSON doesn't say")
    func syncBusyAndStuck() {
        #expect(BDJSON.decodeSyncOutcome(result(3, #"{"error": "retries exhausted"}"#)) == .busy)
        #expect(BDJSON.decodeSyncOutcome(result(4, #"{"error": "pending graph edits"}"#)) == .stuck("pending graph edits"))
    }

    @Test("a failure keeps bd's message; two separate histories are told apart from it")
    func syncFailures() {
        let empty = #"{"error": "sync failed: pull: fetch from origin/main: Error 1105: fetch failed: no branches found in remote 'origin'"}"#
        #expect(BDJSON.decodeSyncOutcome(result(1, empty)) == .failed("sync failed: pull: fetch from origin/main: Error 1105: fetch failed: no branches found in remote 'origin'"))
        let unrelated = #"{"error": "sync failed: pull: merge origin/main: Error 1105: no common ancestor"}"#
        #expect(BDJSON.decodeSyncOutcome(result(1, unrelated)) == .unrelated("sync failed: pull: merge origin/main: Error 1105: no common ancestor"))
        #expect(BDJSON.decodeSyncOutcome(result(1, "", stderr: "Error: database locked\n")) == .failed("Error: database locked"))
        #expect(BDJSON.decodeSyncOutcome(result(1, "")) == .failed("bd sync exited with status 1"))
        // Status 0 with nothing readable is not a success.
        #expect(BDJSON.decodeSyncOutcome(result(0, "Synced!")) == .failed("bd sync exited with status 0"))
    }

    @Test("a bootstrap plan says whether bd would clone, create or leave alone")
    func bootstrapPlan() throws {
        let clone = #"{"action": "sync", "has_existing": false, "reason": "Found Dolt data on git origin (refs/dolt/data) — will clone from /srv/origin.git"}"#
        #expect(try BDJSON.decodeBootstrapPlan(Data(clone.utf8)).clonesFromRemote)
        let fresh = #"{"action": "init", "has_existing": false, "reason": "No existing database, remote, or backup — will create fresh database"}"#
        #expect(try BDJSON.decodeBootstrapPlan(Data(fresh.utf8)).createsFreshDatabase)
        let existing = #"{"action": "none", "has_existing": true, "reason": "Database already exists"}"#
        #expect(try BDJSON.decodeBootstrapPlan(Data(existing.utf8)).isNothingToDo)
        #expect(throws: BDJSON.DecodingFailure.self) { try BDJSON.decodeBootstrapPlan(Data("{}".utf8)) }
    }

    @Test("context reports the storage, the role and whether this is a worktree; bd's error object is not a context")
    func context() throws {
        let json = """
        {"backend": "dolt", "bd_version": "1.3.4", "beads_dir": "/repo/.beads", "cwd_repo_root": "/repo/.claude/worktrees/x",
         "database": "bdv", "dolt_mode": "embedded", "is_redirected": false, "is_worktree": true, "repo_root": "/repo", "role": "maintainer"}
        """
        let context = try BDJSON.decodeContext(Data(json.utf8))
        #expect(context == WorkspaceContext(
            bdVersion: "1.3.4", storage: .embedded, role: "maintainer", isWorktree: true,
            repoRoot: "/repo", beadsDirectory: "/repo/.beads", isRedirected: false
        ))
        #expect(throws: BDJSON.DecodingFailure.self) {
            try BDJSON.decodeContext(Data(#"{"error": "cannot resolve repo context: BEADS_DIR points to unsafe location"}"#.utf8))
        }
    }

    @Test("checkouts and hooks")
    func checkoutsAndHooks() throws {
        let worktrees = """
        [{"name": "a", "path": "/lab/a", "branch": "master", "is_main": true, "beads_state": "none"},
         {"name": "a-wt", "path": "/lab/a-wt", "branch": "wt", "is_main": false, "beads_state": "none"}]
        """
        #expect(try BDJSON.decodeCheckouts(Data(worktrees.utf8)) == [
            Checkout(name: "a", path: "/lab/a", branch: "master", isMain: true),
            Checkout(name: "a-wt", path: "/lab/a-wt", branch: "wt", isMain: false),
        ])
        let hooks = """
        {"hooks": [{"Name": "pre-commit", "Installed": true, "Version": "1.3.4", "IsShim": true, "Outdated": false},
                   {"Name": "post-merge", "Installed": false, "Version": "", "IsShim": false, "Outdated": false}]}
        """
        #expect(try BDJSON.decodeHooks(Data(hooks.utf8)) == [
            GitHook(name: "pre-commit", isInstalled: true), GitHook(name: "post-merge", isInstalled: false),
        ])
    }
}

@Suite("Sharing: the store")
struct SharingStoreTests {
    let workspace = BeadsWorkspace(projectDirectory: URL(fileURLWithPath: "/tmp/project"))
    let bd = URL(fileURLWithPath: "/opt/homebrew/bin/bd")

    func store(_ runner: FakeRunner) -> BDStore {
        BDStore(gateway: BDGateway(workspace: workspace, executable: bd, runner: runner))
    }

    static let remote = #"[{"name": "origin", "url": "git+https://github.com/org/repo.git"}]"#
    static let peer = #"{"peers": [{"Reachable": true, "ReachError": "", "Status": {"LocalAhead": 2, "LocalBehind": 0, "Peer": "origin"}}]}"#
    static let context = #"{"dolt_mode": "embedded", "bd_version": "1.3.4"}"#

    @Test("with no remote, the remote is never asked about")
    func noRemoteNoNetwork() async throws {
        let runner = FakeRunner { args in
            if args.contains("remote") { return ok("[]") }
            if args.contains("context") { return ok(Self.context) }
            return ok(#"{"key": "dolt.local-only", "value": ""}"#)
        }
        let facts = try await store(runner).sharingFacts()
        #expect(facts == SharingFacts(remotes: [], peers: [], isLocalOnly: false, storage: .embedded))
        #expect(!runner.invocations.contains { $0.arguments.contains("federation") })
    }

    @Test("with a remote, its standing is read too")
    func withRemote() async throws {
        let runner = FakeRunner { args in
            if args.contains("remote") { return ok(Self.remote) }
            if args.contains("federation") { return ok(Self.peer) }
            if args.contains("context") { return ok(Self.context) }
            return ok(#"{"value": "false"}"#)
        }
        let facts = try await store(runner).sharingFacts()
        #expect(SharingState.derive(facts) == .pending(DoltRemote(name: "origin", url: "git+https://github.com/org/repo.git"), toSend: 2, toReceive: 0))
    }

    @Test("local-only keeps the app off the network as well")
    func localOnly() async throws {
        let runner = FakeRunner { args in
            if args.contains("remote") { return ok(Self.remote) }
            if args.contains("context") { return ok(Self.context) }
            return ok(#"{"key": "dolt.local-only", "value": "true"}"#)
        }
        let facts = try await store(runner).sharingFacts()
        #expect(SharingState.derive(facts) == .keptLocal)
        #expect(!runner.invocations.contains { $0.arguments.contains("federation") })
    }

    @Test("when bd won't say how it stores the database, no conflict side is offered")
    func unknownStorage() async throws {
        let runner = FakeRunner { args in
            if args.contains("remote") { return ok(Self.remote) }
            if args.contains("federation") { return ok(Self.peer) }
            if args.contains("context") { return ok(#"{"error": "cannot resolve repo context"}"#) }
            return ok(#"{"value": ""}"#)
        }
        let facts = try await store(runner).sharingFacts()
        #expect(SharingState.derive(facts, lastSync: .conflict(tables: ["issues"])) == .conflict(facts.remote!, canChooseSide: false))
    }

    @Test("a bd that can't list remotes as JSON is an error, not 'not shared'")
    func unreadableRemotes() async {
        let runner = FakeRunner { _ in ok("No remotes configured.") }
        await #expect(throws: BeadsDataError.self) { try await store(runner).sharingFacts() }
    }

    @Test("sync reads bd's exit status as part of the answer instead of throwing on it")
    func sync() async throws {
        let runner = FakeRunner { _ in CommandResult(exitCode: 2, stdout: Data(#"{"status": "conflict", "conflicts": ["issues"]}"#.utf8), stderr: "") }
        #expect(try await store(runner).sync() == .conflict(tables: ["issues"]))
    }

    @Test("each step runs one command, and its preview is that command")
    func steps() async throws {
        let runner = FakeRunner { _ in ok("") }
        let store = store(runner)
        let steps: [SharingStep] = [
            .addRemote(name: "origin", url: "https://github.com/org/repo.git", allowGitOrigin: true), .publish, .settleConflict(keeping: .theirs),
        ]
        for step in steps { try await store.perform(step) }
        #expect(runner.invocations.map { Array($0.arguments.dropFirst(2)) } == [
            ["dolt", "remote", "add", "--allow-git-origin", "--", "origin", "https://github.com/org/repo.git"],
            ["dolt", "push"],
            ["dolt", "pull", "--strategy=theirs"],
        ])
        #expect(store.commandPreview(for: .publish) == "bd -C /tmp/project dolt push")
        #expect(store.commandPreview(for: .sync) == "bd -C /tmp/project sync --json")
    }

    @Test("a failed step throws bd's own message")
    func failedStep() async {
        let runner = FakeRunner { _ in CommandResult(exitCode: 1, stdout: Data(), stderr: "Error: refusing to add") }
        await #expect(throws: BeadsDataError.commandFailed(exitCode: 1, message: "Error: refusing to add")) {
            try await store(runner).perform(.publish)
        }
    }

    @Test("the setup facts are whatever bd will say; a part it won't is left out")
    func setup() async {
        let runner = FakeRunner { args in
            if args.contains("context") { return ok(#"{"error": "cannot resolve"}"#) }
            if args.contains("worktree") { return ok(#"[{"name": "main", "path": "/repo", "branch": "master", "is_main": true}]"#) }
            if args.contains("hooks") { return ok(#"{"hooks": [{"Name": "pre-commit", "Installed": true}]}"#) }
            return ok(#"{"key": "export.auto", "value": "true"}"#)
        }
        let setup = await store(runner).workspaceSetup()
        #expect(setup.context == nil)
        #expect(setup.checkouts.map(\.branch) == ["master"])
        #expect(setup.installedHooks.map(\.name) == ["pre-commit"])
        #expect(setup.exportsIssuesFile == true)
    }
}
