import BeadsCore
import Foundation
import Testing

@Suite("Where the beads live, and whether that is current")
struct SharingStateTests {
    let origin = DoltRemote(name: "origin", url: "git+https://github.com/org/repo.git")

    func facts(
        remotes: [DoltRemote]? = nil, peer: PeerStatus? = nil, localOnly: Bool = false, storage: StorageMode = .embedded
    ) -> SharingFacts {
        SharingFacts(remotes: remotes ?? [origin], peers: peer.map { [$0] } ?? [], isLocalOnly: localOnly, storage: storage)
    }

    func peer(reachable: Bool = true, error: String? = nil, ahead: Int? = 0, behind: Int? = 0) -> PeerStatus {
        PeerStatus(name: "origin", isReachable: reachable, reachError: error, ahead: ahead, behind: behind)
    }

    @Test("no remote is beads on this Mac and nowhere else")
    func notShared() {
        #expect(SharingState.derive(facts(remotes: [])) == .notShared)
        #expect(SharingState.derive(.none) == .notShared)
    }

    @Test("bd's local-only setting wins over a remote that is still listed")
    func keptLocal() {
        #expect(SharingState.derive(facts(peer: peer(), localOnly: true)) == .keptLocal)
    }

    @Test("a remote bd can reach but can't compare with has had nothing published to it")
    func neverPublished() {
        // What bd reports after `bd init` wired origin and before the first `bd dolt push`.
        #expect(SharingState.derive(facts(peer: peer(ahead: nil, behind: nil))) == .neverPublished(origin))
    }

    @Test("level with the remote is in sync; anything else counts what's waiting each way")
    func counts() {
        #expect(SharingState.derive(facts(peer: peer())) == .inSync(origin))
        #expect(SharingState.derive(facts(peer: peer(ahead: 2, behind: 0))) == .pending(origin, toSend: 2, toReceive: 0))
        #expect(SharingState.derive(facts(peer: peer(ahead: 0, behind: 3))) == .pending(origin, toSend: 0, toReceive: 3))
        #expect(SharingState.derive(facts(peer: peer(ahead: 1, behind: 1))) == .pending(origin, toSend: 1, toReceive: 1))
    }

    @Test("an unreachable remote says so with bd's reason, whatever the counts were")
    func unreachable() {
        let state = SharingState.derive(facts(peer: peer(reachable: false, error: "Could not read from remote repository", ahead: 0, behind: 0)))
        #expect(state == .unreachable(origin, reason: "Could not read from remote repository"))
        #expect(state.needsAttention)
    }

    @Test("a remote with no status from bd is unknown, not in sync")
    func unknown() {
        #expect(SharingState.derive(facts()) == .unknown(origin))
    }

    @Test("a conflict is remembered from the last sync, because bd reports nothing after aborting the merge")
    func conflict() {
        let level = facts(peer: peer(ahead: 1, behind: 2))
        #expect(SharingState.derive(level, lastSync: .conflict(tables: ["issues"])) == .conflict(origin, canChooseSide: true))
        #expect(SharingState.derive(level, lastSync: .synced) == .pending(origin, toSend: 1, toReceive: 2))
    }

    @Test("picking a side in one pull is offered on embedded storage only")
    func conflictOnAServer() {
        let server = facts(peer: peer(), storage: .other("server"))
        #expect(SharingState.derive(server, lastSync: .conflict(tables: ["issues"])) == .conflict(origin, canChooseSide: false))
    }

    @Test("two separately made databases are named as that, not as an ordinary failure")
    func unrelated() {
        let message = "sync failed: pull: merge origin/main: Error 1105: no common ancestor"
        #expect(SyncOutcome.isUnrelatedHistory(message))
        #expect(!SyncOutcome.isUnrelatedHistory("fetch failed: no branches found in remote 'origin'"))
        #expect(SharingState.derive(facts(peer: peer(ahead: 77, behind: 88)), lastSync: .unrelated(message)) == .unrelated(origin))
    }

    @Test("a failed or busy sync leaves the state to what bd reports")
    func otherOutcomes() {
        for outcome in [SyncOutcome.failed("x"), .busy, .stuck("y"), .noRemote, .localOnly] {
            #expect(SharingState.derive(facts(peer: peer()), lastSync: outcome) == .inSync(origin))
        }
    }

    @Test("origin is the default remote; otherwise the first one listed")
    func defaultRemote() {
        let backup = DoltRemote(name: "backup", url: "file:///Volumes/Disk/beads")
        #expect(facts(remotes: [backup, origin]).remote == origin)
        #expect(facts(remotes: [backup]).remote == backup)
        // The state is read against that remote's own status, not another's.
        let other = PeerStatus(name: "backup", isReachable: true, ahead: 5, behind: 0)
        #expect(SharingState.derive(SharingFacts(remotes: [backup, origin], peers: [other], isLocalOnly: false, storage: .embedded)) == .unknown(origin))
    }
}

@Suite("A remote's URL, as shown")
struct DoltRemoteTests {
    @Test("Dolt's git+ prefix is dropped, and a file remote is shown as its path")
    func plain() {
        #expect(DoltRemote(name: "origin", url: "git+https://github.com/org/repo.git").displayURL == "https://github.com/org/repo.git")
        #expect(DoltRemote(name: "origin", url: "git+ssh://git@github.com/./org/repo.git").displayURL == "ssh://github.com/./org/repo.git")
        #expect(DoltRemote(name: "origin", url: "git+file:///srv/git/repo.git").displayURL == "/srv/git/repo.git")
        #expect(DoltRemote(name: "hub", url: "https://doltremoteapi.dolthub.com/org/beads").displayURL == "https://doltremoteapi.dolthub.com/org/beads")
        #expect(DoltRemote(name: "s3", url: "aws://[bucket]/path").displayURL == "aws://[bucket]/path")
    }

    @Test("credentials in a URL are never shown")
    func credentials() {
        let remote = DoltRemote(name: "origin", url: "git+https://x-access-token:ghp_secret@github.com/org/repo")
        #expect(remote.displayURL == "https://github.com/org/repo")
        #expect(!remote.displayURL.contains("secret"))
        // An @ in the path is not a credential.
        #expect(DoltRemote(name: "o", url: "https://host/org/repo@v2").displayURL == "https://host/org/repo@v2")
    }

    @Test("git-hosted remotes are the ones whose data rides in a git repository")
    func gitHosted() {
        #expect(DoltRemote(name: "origin", url: "git+ssh://git@github.com/org/repo.git").isGitHosted)
        #expect(!DoltRemote(name: "hub", url: "https://doltremoteapi.dolthub.com/org/beads").isGitHosted)
    }
}

@Suite("What bd bootstrap would do in a folder")
struct BootstrapPlanTests {
    @Test("a database that is already there leaves nothing to do, whatever the action says")
    func existing() {
        #expect(BootstrapPlan(action: "none", hasExistingDatabase: true, reason: "").isNothingToDo)
        let odd = BootstrapPlan(action: "sync", hasExistingDatabase: true, reason: "")
        #expect(odd.isNothingToDo && !odd.clonesFromRemote)
    }

    @Test("sync clones the shared database; init would make a separate one")
    func actions() {
        let clone = BootstrapPlan(action: "sync", hasExistingDatabase: false, reason: "Found Dolt data on git origin")
        #expect(clone.clonesFromRemote && !clone.createsFreshDatabase && !clone.isNothingToDo)
        let fresh = BootstrapPlan(action: "init", hasExistingDatabase: false, reason: "No existing database, remote, or backup")
        #expect(fresh.createsFreshDatabase && !fresh.clonesFromRemote)
        let restore = BootstrapPlan(action: "restore", hasExistingDatabase: false, reason: "backup found")
        #expect(!restore.isNothingToDo && !restore.clonesFromRemote && !restore.createsFreshDatabase)
    }
}

@Suite("bd's storage mode")
struct StorageModeTests {
    @Test("embedded is bd's default, so a missing mode reads as embedded")
    func modes() {
        #expect(StorageMode(doltMode: "embedded") == .embedded)
        #expect(StorageMode(doltMode: nil) == .embedded)
        #expect(StorageMode(doltMode: "server") == .other("server"))
    }
}
