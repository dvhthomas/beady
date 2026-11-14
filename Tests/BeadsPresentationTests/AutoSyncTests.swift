import BeadsCore
import Foundation
import Testing
@testable import BeadsPresentation

/// The timer's rules (plan 0007), which are bd's own table for a sync timer: what each outcome
/// of `bd sync` means for the next tick.
@Suite("Automatic sync: when a tick is due, and what each outcome does to the next")
struct AutoSyncTests {
    let origin = DoltRemote(name: "origin", url: "git+https://github.com/org/repo.git")
    let t0 = Date(timeIntervalSince1970: 1_000_000)

    func due(_ auto: AutoSync, after seconds: TimeInterval = 10_000, state: SharingState?, isBusy: Bool = false, canWrite: Bool = true) -> Bool {
        auto.isDue(at: t0.addingTimeInterval(seconds), state: state, isBusy: isBusy, canWrite: canWrite)
    }

    @Test("nothing is automatic until chosen")
    func manualByDefault() {
        let auto = AutoSync()
        #expect(auto.cadence == .manual && auto.cadence.interval == nil)
        #expect(!due(auto, state: .inSync(origin)))
    }

    @Test("the choices are bd's comfortable minute, its own five, and fifteen")
    func cadences() {
        #expect(SyncCadence.allCases.map(\.interval) == [nil, 60, 300, 900])
        #expect(SyncCadence.allCases.map(\.title) == ["When I ask", "Every minute", "Every 5 minutes", "Every 15 minutes"])
        #expect(SyncCadence(seconds: 300) == .everyFiveMinutes && SyncCadence(seconds: 7) == .manual)
    }

    @Test("a tick is due at once when a workspace opens, then once per interval after any sync")
    func timing() {
        var auto = AutoSync(cadence: .everyFiveMinutes)
        #expect(due(auto, after: 0, state: .inSync(origin)))
        auto.record(.synced, at: t0, automatic: true)
        #expect(!due(auto, after: 299, state: .inSync(origin)))
        #expect(due(auto, after: 300, state: .inSync(origin)))
        // A sync asked for by hand counts: the interval runs from the last attempt of any kind.
        auto.record(.synced, at: t0.addingTimeInterval(200), automatic: false)
        #expect(!due(auto, after: 499, state: .inSync(origin)))
    }

    @Test("a tick runs only where bd sync is the right command, and only when nothing else is going on")
    func eligibility() {
        let auto = AutoSync(cadence: .everyMinute)
        for state in [SharingState.inSync(origin), .pending(origin, toSend: 1, toReceive: 0), .unknown(origin), .unreachable(origin, reason: nil)] {
            #expect(due(auto, state: state), "\(state)")
        }
        // Not shared, kept local, and never sent: the first publish is Share Beads's, with its warnings.
        for state in [SharingState.notShared, .keptLocal, .neverPublished(origin), .conflict(origin, canChooseSide: true), .unrelated(origin)] {
            #expect(!due(auto, state: state), "\(state)")
        }
        #expect(!due(auto, state: nil))
        #expect(!due(auto, state: .inSync(origin), isBusy: true))
        #expect(!due(auto, state: .inSync(origin), canWrite: false))
    }

    @Test("exit 0 and exit 3 need nobody: the next tick comes round")
    func quietOutcomes() {
        var auto = AutoSync(cadence: .everyMinute)
        #expect(auto.record(.synced, at: t0, automatic: true) == .quiet)
        #expect(auto.record(.busy, at: t0, automatic: true) == .quiet)
        #expect(auto.hold == nil && due(auto, state: .inSync(origin)))
        // The same race, when a person pressed the button, is worth a sentence.
        #expect(auto.record(.busy, at: t0, automatic: false) == .show)
    }

    @Test("exit 1 is shown when it repeats, and the timer keeps going so a Mac back on the network recovers by itself")
    func failures() {
        var auto = AutoSync(cadence: .everyMinute)
        #expect(auto.record(.failed("offline"), at: t0, automatic: true) == .quiet)
        #expect(auto.record(.failed("offline"), at: t0, automatic: true) == .quiet)
        #expect(auto.record(.failed("offline"), at: t0, automatic: true) == .show)
        #expect(auto.record(.failed("offline"), at: t0, automatic: true) == .show)
        #expect(auto.hold == nil && due(auto, state: .unreachable(origin, reason: nil)))
        // One good sync and the count starts again.
        auto.record(.synced, at: t0, automatic: true)
        #expect(auto.record(.failed("offline"), at: t0, automatic: true) == .quiet)
        // A failure the person watched happen is always shown.
        #expect(AutoSync(cadence: .everyMinute).recording(.failed("no"), at: t0, automatic: false).report == .show)
    }

    @Test("exit 2, exit 4 and two unrelated backlogs stop the timer until a person has dealt with them")
    func holds() {
        for (outcome, hold) in [
            (SyncOutcome.conflict(tables: ["issues"]), AutoSync.Hold.conflict),
            (.stuck("pending graph edits"), .stuck),
            (.unrelated("no common ancestor"), .unrelated),
        ] {
            var auto = AutoSync(cadence: .everyMinute)
            #expect(auto.record(outcome, at: t0, automatic: true) == .show)
            #expect(auto.hold == hold)
            #expect(!due(auto, state: .inSync(origin)))
            // A sync asked for by hand that goes through lifts it.
            auto.record(.synced, at: t0, automatic: false)
            #expect(auto.hold == nil && due(auto, state: .inSync(origin)))
        }
    }

    @Test("stopping a sync pauses the timer: the person's last word wins until they sync by hand or choose again")
    func stopped() {
        var auto = AutoSync(cadence: .everyMinute)
        #expect(auto.record(.stopped, at: t0, automatic: true) == .show)
        #expect(auto.hold == .stopped && !due(auto, state: .inSync(origin)))
        // An automatic outcome can't lift a hold; only a person can.
        var chosenAgain = auto
        chosenAgain.choose(.everyFiveMinutes)
        #expect(chosenAgain.hold == nil && due(chosenAgain, state: .inSync(origin)))
        auto.record(.synced, at: t0, automatic: false)
        #expect(auto.hold == nil)
    }

    @Test("the line under the choice says what will happen, and repeats bd's caution for a git-hosted remote")
    func captions() {
        let bucket = DoltRemote(name: "origin", url: "gs://bucket/beads")
        #expect(AutoSync().caption(remote: origin) == "Beady syncs when you press Sync Now.")
        #expect(AutoSync(cadence: .everyMinute).caption(remote: bucket) == "Syncs by itself while this workspace is open.")
        #expect(AutoSync(cadence: .everyMinute).caption(remote: origin)
            == "Syncs by itself while this workspace is open. bd advises care when several writers push to a git-hosted remote; a lost race is retried.")
        var auto = AutoSync(cadence: .everyMinute)
        auto.record(.stopped, at: t0, automatic: true)
        #expect(auto.caption(remote: origin) == "Paused, because you stopped a sync. Sync Now starts it again.")
        auto.record(.conflict(tables: []), at: t0, automatic: false)
        #expect(auto.caption(remote: origin) == "Paused until this is settled.")
    }
}

private extension AutoSync {
    func recording(_ outcome: SyncOutcome, at date: Date, automatic: Bool) -> (auto: AutoSync, report: AutoSync.Report) {
        var copy = self
        let report = copy.record(outcome, at: date, automatic: automatic)
        return (copy, report)
    }
}
