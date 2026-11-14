import BeadsCore
import BeadsPresentation
import Foundation
import Testing

private let origin = DoltRemote(name: "origin", url: "git+https://github.com/org/repo.git")

private func facts(ahead: Int? = 0, behind: Int? = 0, reachable: Bool = true, storage: StorageMode = .embedded) -> SharingFacts {
    SharingFacts(
        remotes: [origin],
        peers: [PeerStatus(name: "origin", isReachable: reachable, reachError: reachable ? nil : "Could not read from remote repository.", ahead: ahead, behind: behind)],
        isLocalOnly: false, storage: storage
    )
}

@Suite("The words for each sharing state")
struct SharingSummaryTests {
    @Test("each state has a word, a symbol and a sentence, and offers only what would do something")
    func everyState() {
        let cases: [(SharingState, SharingSummary.Tone, [SharingAction])] = [
            (.keptLocal, .quiet, []),
            (.notShared, .quiet, [.share]),
            (.neverPublished(origin), .waiting, [.share]),
            (.unreachable(origin, reason: "no route"), .problem, [.checkAgain]),
            (.unknown(origin), .quiet, [.sync, .checkAgain]),
            (.pending(origin, toSend: 2, toReceive: 1), .waiting, [.sync]),
            (.inSync(origin), .good, [.sync]),
            (.conflict(origin, canChooseSide: true), .problem, [.settleConflict(keeping: .mine), .settleConflict(keeping: .theirs)]),
            (.conflict(origin, canChooseSide: false), .problem, []),
            (.unrelated(origin), .problem, []),
        ]
        for (state, tone, actions) in cases {
            let summary = state.summary()
            #expect(summary.tone == tone, "\(state)")
            #expect(summary.actions == actions, "\(state)")
            #expect(!summary.word.isEmpty && !summary.symbol.isEmpty && !summary.detail.isEmpty, "\(state)")
            #expect((tone == .problem) == state.needsAttention, "\(state)")
        }
    }

    @Test("what is waiting is counted each way, and only the ways that have something")
    func counts() {
        #expect(SharingState.pending(origin, toSend: 2, toReceive: 1).summary().word == "2 to send · 1 to receive")
        #expect(SharingState.pending(origin, toSend: 3, toReceive: 0).summary().word == "3 to send")
        #expect(SharingState.pending(origin, toSend: 0, toReceive: 4).summary().word == "4 to receive")
        let both = SharingState.pending(origin, toSend: 2, toReceive: 3).summary().detail
        #expect(both == "2 changes here aren't on origin yet. 3 changes on origin aren't here yet.")
        // One of something is said as one.
        #expect(SharingState.pending(origin, toSend: 1, toReceive: 1).summary().detail == "1 change here isn't on origin yet. 1 change on origin isn't here yet.")
        #expect(!SharingState.pending(origin, toSend: 2, toReceive: 0).summary().detail.contains("aren't here yet"))
    }

    @Test("an unreachable remote keeps bd's reason under the plain sentence")
    func unreachable() {
        let summary = SharingState.unreachable(origin, reason: "fatal: Could not read from remote repository.").summary()
        #expect(summary.word == "Can't reach origin")
        #expect(summary.detail.hasSuffix("fatal: Could not read from remote repository."))
        #expect(!SharingState.unreachable(origin, reason: nil).summary().detail.contains("\n"))
    }

    @Test("while bd is working the word says so and nothing else can be started")
    func working() {
        let summary = SharingState.pending(origin, toSend: 1, toReceive: 0).summary(isWorking: true)
        #expect(summary.word == "Syncing…")
        #expect(summary.isWorking)
        #expect(summary.actions.isEmpty)
    }

    @Test("the buttons keep their places while bd works, so the popover doesn't change size under the pointer")
    func workingKeepsItsButtons() {
        for state in [SharingState.pending(origin, toSend: 1, toReceive: 0), .inSync(origin), .unknown(origin), .notShared] {
            let settled = state.summary()
            let working = state.summary(isWorking: true)
            #expect(working.buttons == settled.actions)
            #expect(working.detail == settled.detail)
            #expect(settled.buttons == settled.actions && !settled.isWorking)
        }
    }

    @Test("a conflict says plainly that nothing was lost, and that a side applies to every bead in conflict")
    func conflict() {
        let detail = SharingState.conflict(origin, canChooseSide: true).summary().detail
        #expect(detail.contains("nothing was sent and nothing here was lost"))
        #expect(detail.contains("every bead in conflict"))
        #expect(SharingState.conflict(origin, canChooseSide: false).summary().detail.contains("bd conflicts"))
    }

    @Test("only outcomes the status can't show get a notice, and it carries bd's words")
    func notices() {
        #expect(SyncOutcome.synced.notice == nil)
        #expect(SyncOutcome.conflict(tables: ["issues"]).notice == nil)
        #expect(SyncOutcome.unrelated("no common ancestor").notice == nil)
        #expect(SyncOutcome.busy.notice?.contains("sync again") == true)
        #expect(SyncOutcome.failed("fetch failed: no branches found").notice?.contains("fetch failed: no branches found") == true)
        #expect(SyncOutcome.stuck("pending graph edits").notice?.contains("pending graph edits") == true)
    }
}

@Suite("What Share Beads will do")
struct SharePlanTests {
    let gitOrigin = "https://github.com/org/repo.git"

    @Test("with no remote: add the origin with bd's consent flag, then publish with a push, never a sync")
    func fromNothing() {
        let plan = SharePlan.make(facts: .none, gitOrigin: gitOrigin, url: gitOrigin, audience: .team)
        #expect(plan.steps == [.addRemote(name: "origin", url: gitOrigin, allowGitOrigin: true), .publish])
        #expect(plan.canShare)
        #expect(plan.destination == gitOrigin)
    }

    @Test("a remote that is already set up is used as it is: publishing is the only step")
    func alreadyWired() {
        // What `bd init` leaves in a repository that has an origin.
        let wired = SharingFacts(remotes: [origin], peers: [], isLocalOnly: false, storage: .embedded)
        let plan = SharePlan.make(facts: wired, gitOrigin: gitOrigin, url: "ignored", audience: .severalMacs)
        #expect(plan.steps == [.publish])
        #expect(!plan.consequences.contains { $0.contains("sync.remote") }, "nothing is written to config.yaml this time")
    }

    @Test("another URL is added without the git-origin flag, and its surrounding space is dropped")
    func otherRemote() {
        let plan = SharePlan.make(facts: .none, gitOrigin: gitOrigin, url: "  https://doltremoteapi.dolthub.com/org/beads\n", audience: .team)
        #expect(plan.steps.first == .addRemote(name: "origin", url: "https://doltremoteapi.dolthub.com/org/beads", allowGitOrigin: false))
        #expect(!plan.consequences.contains { $0.contains("refs/dolt/data") }, "a Dolt service has no git refs")
    }

    @Test("who can read comes first, and a git remote is told about the ref and the branch bd adds")
    func consequences() {
        let plan = SharePlan.make(facts: .none, gitOrigin: gitOrigin, url: gitOrigin, audience: .team)
        #expect(plan.consequences.first?.contains("Anyone who can read \(gitOrigin)") == true)
        #expect(plan.consequences.contains { $0.contains("refs/dolt/data") && $0.contains("__dolt_remote_info__") })
        #expect(plan.consequences.contains { $0.contains(".beads/config.yaml") && $0.contains("Commit") })
        #expect(plan.consequences.contains { $0.contains("bd bootstrap") && $0.contains("same bd version") })
        #expect(plan.consequences.last?.contains("never by itself") == true)
    }

    @Test("credentials typed into the URL are not echoed back")
    func credentials() {
        let plan = SharePlan.make(facts: .none, gitOrigin: nil, url: "https://user:token@github.com/org/repo.git", audience: .team)
        #expect(!plan.destination.contains("token"))
        #expect(!plan.consequences.joined().contains("token"))
    }

    @Test("only me shares nothing and runs nothing")
    func onlyMe() {
        let plan = SharePlan.make(facts: .none, gitOrigin: gitOrigin, url: gitOrigin, audience: .onlyMe)
        #expect(plan.steps.isEmpty && !plan.canShare && plan.problem == nil)
    }

    @Test("nothing to share to, a URL bd would refuse, and local-only are each said, not run")
    func problems() {
        #expect(SharePlan.make(facts: .none, gitOrigin: nil, url: "  ", audience: .team).problem != nil)
        #expect(SharePlan.make(facts: .none, gitOrigin: nil, url: "--upload-pack=x", audience: .team).problem != nil)
        let local = SharingFacts(remotes: [], peers: [], isLocalOnly: true, storage: .embedded)
        let plan = SharePlan.make(facts: local, gitOrigin: gitOrigin, url: gitOrigin, audience: .team)
        #expect(plan.problem?.contains("dolt.local-only") == true)
        #expect(!plan.canShare)
    }
}

@Suite("The Workspace Setup rows")
struct WorkspaceSetupRowsTests {
    let context = WorkspaceContext(
        bdVersion: "1.3.4", storage: .embedded, role: "maintainer", isWorktree: false,
        repoRoot: "/repo", beadsDirectory: "/repo/.beads", isRedirected: false
    )

    func rows(sharing: SharingState? = .notShared, backup: BackupStatus = .none, setup: WorkspaceSetup) -> [SetupRow] {
        WorkspaceSetupRows.rows(sharing: sharing, backup: backup, backupSummary: "not backed up", setup: setup, beadCount: 212)
    }

    @Test("with nothing from bd there is still a database row and a backup row, and nothing made up")
    func bare() {
        let rows = rows(sharing: nil, setup: .unknown)
        #expect(rows.map(\.kind) == [.database, .backup])
        #expect(rows[0].detail == "212 beads.")
    }

    @Test("everything bd reports gets its row, in reading order")
    func full() {
        let setup = WorkspaceSetup(
            context: context,
            checkouts: [Checkout(name: "repo", path: "/repo", branch: "master", isMain: true), Checkout(name: "wt", path: "/repo/wt", branch: "claude/x", isMain: false)],
            hooks: [GitHook(name: "pre-commit", isInstalled: false)], exportsIssuesFile: true
        )
        let rows = rows(setup: setup)
        #expect(rows.map(\.kind) == [.database, .checkouts, .sharing, .backup, .commits, .bd])
        #expect(rows[0].detail.contains("/repo/.beads") && rows[0].detail.contains("No database server to run"))
        #expect(rows[1].detail.contains("2 working copies") && rows[1].detail.contains("master, claude/x"))
        #expect(rows[5].detail.contains("1.3.4") && rows[5].detail.contains("maintainer"))
    }

    @Test("a few checkouts are named; many are counted, because ninety branch names tell nobody anything")
    func manyCheckouts() throws {
        func setup(_ count: Int) -> WorkspaceSetup {
            let worktrees = (1..<count).map { Checkout(name: "wt\($0)", path: "/repo/wt\($0)", branch: "fix/agent-\($0)", isMain: false) }
            return WorkspaceSetup(
                context: context,
                checkouts: [Checkout(name: "repo", path: "/repo", branch: "main", isMain: true)] + worktrees,
                hooks: [], exportsIssuesFile: nil
            )
        }
        let few = try #require(rows(setup: setup(WorkspaceSetupRows.namedCheckoutLimit)).first { $0.kind == .checkouts })
        #expect(few.title == "Worktrees on this Mac")
        #expect(few.detail.contains("git worktrees: main, fix/agent-1") && few.detail.contains("share this one database"))

        let many = try #require(rows(setup: setup(91)).first { $0.kind == .checkouts })
        #expect(many.detail == "91 working copies of this repository (git worktrees, such as the ones agents work in) are on this Mac. They share this one database, so a bead changed in one is changed in all.")
        #expect(!many.detail.contains("fix/agent"))

        let justOver = try #require(rows(setup: setup(WorkspaceSetupRows.namedCheckoutLimit + 1)).first { $0.kind == .checkouts })
        #expect(!justOver.detail.contains("fix/agent"))
    }

    @Test("the sheet's facts take what they need on a big screen and leave room for Done on a small one")
    func factsHeight() {
        #expect(WorkspaceSetupRows.factsMaxHeight(visibleScreenHeight: 1400) == 520)
        #expect(WorkspaceSetupRows.factsMaxHeight(visibleScreenHeight: 640) == 360)
        #expect(WorkspaceSetupRows.factsMaxHeight(visibleScreenHeight: 300) == 200)
        #expect(WorkspaceSetupRows.factsMaxHeight(visibleScreenHeight: nil) == 420)
    }

    @Test("one checkout is not worth a row")
    func singleCheckout() {
        let setup = WorkspaceSetup(context: context, checkouts: [Checkout(name: "repo", path: "/repo", branch: "master", isMain: true)], hooks: [], exportsIssuesFile: nil)
        #expect(!rows(setup: setup).contains { $0.kind == .checkouts })
    }

    @Test("the sharing row carries the state's word, sentence and first action")
    func sharingRow() throws {
        let notShared = try #require(rows(setup: .unknown).first { $0.kind == .sharing })
        #expect(notShared.detail.hasPrefix("Only on this Mac."))
        #expect(notShared.action == .sharing(.share))
        #expect(notShared.level == .info)
        let conflict = try #require(rows(sharing: .conflict(origin, canChooseSide: true), setup: .unknown).first { $0.kind == .sharing })
        #expect(conflict.level == .attention)
        let synced = try #require(rows(sharing: .inSync(origin), setup: .unknown).first { $0.kind == .sharing })
        #expect(synced.level == .good && synced.action == .sharing(.sync))
    }

    @Test("no backup is a worry only while the beads are on this Mac alone")
    func backupRow() throws {
        let alone = try #require(rows(setup: .unknown).first { $0.kind == .backup })
        #expect(alone.level == .attention && alone.action == .setUpBackup)
        let shared = try #require(rows(sharing: .inSync(origin), setup: .unknown).first { $0.kind == .backup })
        #expect(shared.level == .info)
        // Set up but never sent is still on this Mac alone.
        let unsent = try #require(rows(sharing: .neverPublished(origin), setup: .unknown).first { $0.kind == .backup })
        #expect(unsent.level == .attention)
        let backedUp = BackupStatus(destination: "/Volumes/Disk/beads", lastSync: t0, databaseSize: "1 MB")
        let configured = try #require(WorkspaceSetupRows.rows(sharing: .notShared, backup: backedUp, backupSummary: "backed up 6 minutes ago", setup: .unknown, beadCount: 1).first { $0.kind == .backup })
        #expect(configured.level == .good && configured.action == .backUpNow)
        #expect(configured.detail == "Backed up 6 minutes ago, to /Volumes/Disk/beads.")
    }

    @Test("the commits row says whether beads can end up in a commit, which is what the hooks decide")
    func commitsRow() throws {
        func row(_ hooks: [GitHook], exports: Bool?) throws -> SetupRow {
            try #require(rows(setup: WorkspaceSetup(context: nil, checkouts: [], hooks: hooks, exportsIssuesFile: exports)).first { $0.kind == .commits })
        }
        let none = try row([GitHook(name: "pre-commit", isInstalled: false)], exports: true)
        #expect(none.title == "Git commits")
        #expect(none.level == .good && none.detail.hasPrefix("Beads stay out of git commits."))
        let exporting = try row([GitHook(name: "pre-commit", isInstalled: true), GitHook(name: "pre-push", isInstalled: true)], exports: true)
        #expect(exporting.level == .info && exporting.detail.contains("pre-commit, pre-push") && exporting.detail.contains(".beads/issues.jsonl"))
        #expect(exporting.detail.hasPrefix("Each git commit carries a copy of the beads"))
        let quiet = try row([GitHook(name: "pre-commit", isInstalled: true)], exports: false)
        #expect(quiet.detail.hasPrefix("Beads stay out of git commits.") && quiet.detail.contains("export.auto is off"))
        let old = try row([GitHook(name: "pre-commit", isInstalled: true, isOutdated: true)], exports: false)
        #expect(old.level == .attention && old.detail.contains("bd hooks install"))
        // bd wouldn't list its hooks: no row, rather than a claim that there are none.
        #expect(!rows(setup: .unknown).contains { $0.kind == .commits })
    }

    @Test("a database kept outside the folder is said to be")
    func redirected() {
        let elsewhere = WorkspaceContext(bdVersion: nil, storage: .other("server"), role: nil, isWorktree: false, repoRoot: "/repo", beadsDirectory: "/Users/ada/project-beads/.beads", isRedirected: true)
        let rows = rows(setup: WorkspaceSetup(context: elsewhere, checkouts: [], hooks: [], exportsIssuesFile: nil))
        #expect(rows[0].detail.contains("Kept outside this folder, in /Users/ada/project-beads/.beads."))
        #expect(rows[0].detail.contains("Dolt server (server)"))
        #expect(!rows.contains { $0.kind == .bd }, "no version from bd, no row")
    }
}

@MainActor
@Suite("Sharing, as the window uses it")
struct SharingModelTests {
    func model(_ store: StubStore, allowsWriting: Bool = true) async -> WorkspaceModel {
        let model = WorkspaceModel(title: "engine", store: store, allowsWriting: allowsWriting, now: { t0 })
        await model.load()
        await model.refreshSharing()
        return model
    }

    @Test("until bd has been asked, and when it won't say, there is no status at all")
    func unknown() async {
        let store = StubStore([makeIssue("a")])
        let fresh = WorkspaceModel(title: "engine", store: store, now: { t0 })
        #expect(fresh.sharingSummary == nil)
        store.sharing = nil
        #expect(await model(store).sharingSummary == nil)
    }

    @Test("loading doesn't ask the remote; only refreshSharing does")
    func loadIsLocal() async {
        let store = StubStore([makeIssue("a")])
        store.sharing = facts(ahead: 1)
        let model = WorkspaceModel(title: "engine", store: store, now: { t0 })
        await model.load()
        #expect(model.sharing == nil)
        await model.refreshSharing()
        #expect(model.sharingState == .pending(origin, toSend: 1, toReceive: 0))
    }

    @Test("a sync that goes through is recorded, re-reads the standing, and reloads the beads it may have brought")
    func syncs() async {
        let store = StubStore([makeIssue("a")])
        store.sharing = facts(ahead: 2, behind: 1)
        store.sharingAfterAction = facts()
        let model = await model(store)
        let loads = store.calls
        await model.syncNow()
        #expect(store.syncs == 1)
        #expect(model.sharingState == .inSync(origin))
        #expect(model.activity.first?.summary == "Synced with origin")
        #expect(model.activity.first?.succeeded == true)
        #expect(store.calls == loads + 1)
        #expect(model.sharingNotice == nil && !model.isSyncing)
    }

    @Test("a conflict stays on screen after bd has aborted the merge, until it is settled")
    func conflictPersists() async {
        let store = StubStore([makeIssue("a")])
        store.sharing = facts(ahead: 1, behind: 2)
        store.syncOutcomes = [.conflict(tables: ["issues"])]
        let model = await model(store)
        await model.syncNow()
        #expect(model.sharingState == .conflict(origin, canChooseSide: true))
        #expect(model.activity.first?.succeeded == false)
        // bd still reports plain counts; the conflict is the model's to remember.
        await model.refreshSharing()
        #expect(model.sharingState == .conflict(origin, canChooseSide: true))
    }

    @Test("settling a conflict pulls for the chosen side and then syncs, which is what publishes it")
    func settles() async {
        let store = StubStore([makeIssue("a")])
        store.sharing = facts(ahead: 1, behind: 2)
        store.syncOutcomes = [.conflict(tables: ["issues"])]
        let model = await model(store)
        await model.syncNow()
        store.sharingAfterAction = facts()
        await model.settleConflict(keeping: .theirs)
        #expect(store.sharingSteps == [.settleConflict(keeping: .theirs)])
        #expect(store.syncs == 2)
        #expect(model.sharingState == .inSync(origin))
        #expect(model.activity.contains { $0.summary == "Settled the conflict with origin, taking its beads" })
    }

    @Test("a side can't be chosen where there is no conflict, or where bd doesn't offer one")
    func settleRefused() async {
        let store = StubStore([makeIssue("a")])
        store.sharing = facts()
        let model = await model(store)
        await model.settleConflict(keeping: .mine)
        #expect(store.sharingSteps.isEmpty)

        let server = StubStore([makeIssue("a")])
        server.sharing = facts(storage: .other("server"))
        server.syncOutcomes = [.conflict(tables: ["issues"])]
        let onServer = await self.model(server)
        await onServer.syncNow()
        await onServer.settleConflict(keeping: .mine)
        #expect(server.sharingSteps.isEmpty)
    }

    @Test("a failed sync says why in bd's words and leaves the status to what bd reports")
    func syncFails() async {
        let store = StubStore([makeIssue("a")])
        store.sharing = facts(ahead: 1)
        store.syncOutcomes = [.failed("sync failed: push: rejected")]
        let model = await model(store)
        await model.syncNow()
        #expect(model.sharingNotice?.contains("sync failed: push: rejected") == true)
        #expect(model.sharingState == .pending(origin, toSend: 1, toReceive: 0))
        #expect(model.activity.first?.succeeded == false)
        model.dismissSharingNotice()
        #expect(model.sharingNotice == nil)
    }

    @Test("two separate backlogs are named as that after a sync finds them")
    func unrelated() async {
        let store = StubStore([makeIssue("a")])
        store.sharing = facts(ahead: 77, behind: 88)
        store.syncOutcomes = [.unrelated("no common ancestor")]
        let model = await model(store)
        await model.syncNow()
        #expect(model.sharingState == .unrelated(origin))
    }

    @Test("sharing runs the plan's steps in order and the status follows")
    func shares() async {
        let store = StubStore([makeIssue("a")])
        store.origin = "https://github.com/org/repo.git"
        store.sharingAfterAction = facts()
        let model = await model(store)
        await model.refreshSetup()
        #expect(model.gitOrigin == "https://github.com/org/repo.git")
        #expect(model.sharingState == .notShared)
        let plan = model.sharePlan(url: model.gitOrigin ?? "", audience: .team)
        #expect(model.commands(for: plan) == [
            "bd dolt remote add --allow-git-origin -- origin https://github.com/org/repo.git", "bd dolt push",
        ])
        #expect(await model.share(plan))
        #expect(store.sharingSteps == [.addRemote(name: "origin", url: "https://github.com/org/repo.git", allowGitOrigin: true), .publish])
        #expect(model.sharingState == .inSync(origin))
        #expect(model.activity.first?.summary == "Shared beads with https://github.com/org/repo.git")
    }

    @Test("a share stops at the step bd refuses, says why, and still shows a remote that was added")
    func shareFails() async {
        let store = StubStore([makeIssue("a")])
        store.stepFailures = [1: LoadFailure()]
        store.sharingAfterAction = SharingFacts(remotes: [origin], peers: [PeerStatus(name: "origin", isReachable: true, ahead: nil, behind: nil)], isLocalOnly: false, storage: .embedded)
        let model = await model(store)
        let plan = model.sharePlan(url: "https://github.com/org/repo.git", audience: .team)
        #expect(await model.share(plan) == false)
        #expect(store.sharingSteps.count == 2)
        #expect(model.sharingNotice == "bd exploded")
        #expect(model.sharingState == .neverPublished(origin))
        #expect(model.activity.first?.succeeded == false)
    }

    @Test("a plan with a problem, or for only me, runs nothing")
    func shareRefused() async {
        let store = StubStore([makeIssue("a")])
        let model = await model(store)
        #expect(await model.share(model.sharePlan(url: "", audience: .team)) == false)
        #expect(await model.share(model.sharePlan(url: "x", audience: .onlyMe)) == false)
        #expect(store.sharingSteps.isEmpty)
    }

    @Test("a window that can't write never syncs, shares or settles")
    func readOnly() async {
        let store = StubStore([makeIssue("a")])
        store.sharing = facts(ahead: 1)
        let model = await model(store, allowsWriting: false)
        await model.syncNow()
        #expect(await model.share(SharePlan.make(facts: .none, gitOrigin: nil, url: "https://x/y.git", audience: .team)) == false)
        #expect(store.syncs == 0 && store.sharingSteps.isEmpty)
    }

    @Test("the commands behind the popover's buttons are the ones that run")
    func commands() async {
        let model = await model(StubStore([makeIssue("a")]))
        #expect(model.command(for: .sync) == "bd sync --json")
        #expect(model.command(for: .settleConflict(keeping: .mine)) == "bd dolt pull --strategy=ours")
        #expect(model.command(for: .share) == nil)
    }

    @Test("the palette offers what the state allows, and Workspace Setup always")
    func palette() async {
        let store = StubStore([makeIssue("a")])
        let notShared = await model(store)
        var commands = CommandCatalog.all(for: notShared)
        #expect(commands.contains(.shareBeads) && !commands.contains(.syncNow) && commands.contains(.workspaceSetup))
        store.sharing = facts(ahead: 1)
        await notShared.refreshSharing()
        commands = CommandCatalog.all(for: notShared)
        #expect(commands.contains(.syncNow) && !commands.contains(.shareBeads))
    }
}

@Suite("Joining: a folder with bd's configuration and no database")
struct JoiningTests {
    @Test("configuration without a database is bd's question to answer, not a workspace to open blind")
    func asks() {
        let clone = ChosenFolder(path: "/Users/ada/code/engine", hasBeadsDatabase: true, isGitRepository: true, hasDatabaseFiles: false)
        #expect(WorkspaceOpening.decide(clone) == .askBootstrapPlan)
        let full = ChosenFolder(path: "/Users/ada/code/engine", hasBeadsDatabase: true, isGitRepository: true, hasDatabaseFiles: true)
        #expect(WorkspaceOpening.decide(full) == .open)
    }

    @Test("nothing for bootstrap to do, or no answer from bd, opens the folder as before")
    func opens() {
        let existing = BootstrapPlan(action: "none", hasExistingDatabase: true, reason: "Database already exists")
        #expect(WorkspaceOpening.decide(existing, for: "/repo") == .open)
        #expect(WorkspaceOpening.decide(nil, for: "/repo") == .open)
    }

    @Test("beads on the remote are offered as getting them, with bd's reason and the exact command")
    func clone() throws {
        let plan = BootstrapPlan(action: "sync", hasExistingDatabase: false, reason: "Found Dolt data on git origin (refs/dolt/data)")
        guard case .offer(let offer) = WorkspaceOpening.decide(plan, for: "/Users/ada/code/engine") else {
            Issue.record("expected an offer")
            return
        }
        #expect(offer.title == "Get the beads for engine?")
        #expect(offer.confirmTitle == "Get Beads")
        let message = offer.message(command: "cd /Users/ada/code/engine && bd bootstrap --yes")
        #expect(message.contains("Found Dolt data on git origin (refs/dolt/data)"))
        #expect(message.contains("cd /Users/ada/code/engine && bd bootstrap --yes"))
        #expect(message.contains("Nothing here is replaced"))
    }

    @Test("an empty database is offered with the warning that it would be a separate backlog")
    func fresh() throws {
        let plan = BootstrapPlan(action: "init", hasExistingDatabase: false, reason: "No existing database, remote, or backup")
        guard case .offer(let offer) = WorkspaceOpening.decide(plan, for: "/repo/engine") else {
            Issue.record("expected an offer")
            return
        }
        #expect(offer.title == "Start an empty beads database in engine?")
        #expect(offer.message(command: "x").contains("a separate backlog"))
    }

    @Test("any other plan bd has is offered in bd's own words")
    func other() throws {
        let plan = BootstrapPlan(action: "restore", hasExistingDatabase: false, reason: "Found backup in .beads/backup")
        guard case .offer(let offer) = WorkspaceOpening.decide(plan, for: "/repo/engine") else {
            Issue.record("expected an offer")
            return
        }
        #expect(offer.confirmTitle == "Set Up")
        #expect(offer.message(command: "x").contains("Found backup in .beads/backup"))
    }
}
