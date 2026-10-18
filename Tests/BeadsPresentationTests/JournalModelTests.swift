import BeadsCore
import BeadsPresentation
import Foundation
import Testing

@Suite("Whether Beady turns bd's change journal on")
struct JournalPolicyTests {
    let v130 = BeadsVersion(1, 3, 0)
    let off = JournalSettings(isEnabled: false, retainDays: 7, retainRows: 100_000)
    var on: JournalSettings { JournalSettings(isEnabled: true, retainDays: 1, retainRows: 1_000) }

    @Test("it's turned on only when every condition holds; each one missing, alone, stops it")
    func everyCombination() {
        let choices = [true, false]
        for newEnough in choices {
            for isOff in choices {
                for canEdit in choices {
                    for setting in choices {
                        for byHand in choices {
                            let version = newEnough ? v130 : BeadsVersion(1, 2, 9)
                            let decision = JournalPolicy.shouldTurnOn(
                                journal: .supported(version, isOff ? off : on),
                                canEdit: canEdit, turnsOnAutomatically: setting, wasTurnedOffByHand: byHand
                            )
                            let expected = newEnough && isOff && canEdit && setting && !byHand
                            #expect(
                                decision == expected,
                                "bd \(version), off=\(isOff), canEdit=\(canEdit), setting=\(setting), byHand=\(byHand)"
                            )
                        }
                    }
                }
            }
        }
    }

    @Test("a bd that is too old, or wouldn't say, never qualifies")
    func unsupported() {
        for journal in [JournalStatus.unsupported(nil), .unsupported(BeadsVersion(1, 2, 0))] {
            #expect(!JournalPolicy.shouldTurnOn(
                journal: journal, canEdit: true, turnsOnAutomatically: true, wasTurnedOffByHand: false
            ))
        }
    }

    @Test("newer bds qualify too: the check is a floor, not a match")
    func newer() {
        #expect(JournalPolicy.shouldTurnOn(
            journal: .supported(BeadsVersion(1, 10, 0), off), canEdit: true, turnsOnAutomatically: true, wasTurnedOffByHand: false
        ))
    }

    @Test("the manual policy never turns it on by itself")
    func manual() {
        #expect(!JournalPolicy.manual.turnsOnAutomatically)
        #expect(!JournalPolicy.manual.shouldTurnOn(journal: .supported(v130, off), canEdit: true))
    }
}

@MainActor
@Suite("The events journal, as the window uses it")
struct JournalModelTests {
    let v130 = BeadsVersion(1, 3, 0)
    let defaults = JournalSettings(isEnabled: false, retainDays: 7, retainRows: 100_000)
    var on: JournalSettings { JournalSettings(isEnabled: true, retainDays: 1, retainRows: 1_000) }
    let beadyRetention = [
        ConfigSetting(key: "events-journal", value: "true"),
        ConfigSetting(key: "events-journal-retain-days", value: "1"),
        ConfigSetting(key: "events-journal-retain-rows", value: "1000"),
    ]
    let backOff = [
        ConfigSetting(key: "events-journal", value: "false"),
        ConfigSetting(key: "events-journal-retain-days", value: "7"),
        ConfigSetting(key: "events-journal-retain-rows", value: "100000"),
    ]

    func record(_ seq: Int64, _ id: IssueID, actor: String? = "agent-7", ago: TimeInterval = 30) -> JournalRecord {
        JournalRecord(seq: seq, date: t0 - ago, op: "update", issueID: id, actor: actor)
    }

    func makeModel(
        _ journal: JournalStatus,
        reads: [Result<JournalRead, Error>] = [],
        policy: JournalPolicy = .manual,
        allowsWriting: Bool = true
    ) -> (WorkspaceModel, StubStore) {
        let store = StubStore([makeIssue("demo-1"), makeIssue("demo-2")])
        store.journal = journal
        store.journalReads = reads
        store.interactions = ActivityLog(entries: [
            ActivityEntry(issueID: "demo-2", actor: "from-interactions", date: t0 - 10, field: "status"),
        ])
        let model = WorkspaceModel(
            title: "demo", store: store, allowsWriting: allowsWriting, now: { t0 }, journalPolicy: policy
        )
        return (model, store)
    }

    /// The app's default: the setting on, and nobody has turned this workspace's journal off.
    func automatic(turnedOffByHand: Bool = false, noting: Mutable<Int>? = nil) -> JournalPolicy {
        JournalPolicy(turnsOnAutomatically: true, wasTurnedOffByHand: turnedOffByHand) { noting?.value += 1 }
    }

    @Test("with a bd older than 1.3 nothing changes: the interaction log reports activity, and nothing is written")
    func unsupported() async {
        let (model, store) = makeModel(.unsupported(BeadsVersion(1, 2, 0)), policy: automatic())
        await model.load()
        #expect(model.journal == .unsupported(BeadsVersion(1, 2, 0)))
        #expect(store.journalWrites.isEmpty)
        #expect(store.journalCheckpoints.isEmpty)
        #expect(model.activity.isEmpty)
        #expect(model.recentChange(to: "demo-2")?.actor == "from-interactions")
        #expect(!CommandCatalog.all(for: model).contains(.turnOnJournal))
    }

    @Test("bd's version is checked when the workspace opens, not on every refresh")
    func checkedOnce() async {
        let (model, store) = makeModel(.supported(v130, defaults))
        await model.load()
        store.setToken("t1")
        await model.refreshIfChanged()
        await model.load()
        #expect(store.journalStatusChecks == 1)
    }

    @Test("opening a writable 1.3 workspace with the journal off turns it on, once, with Beady's retention")
    func turnedOnAtOpen() async {
        let noted = Mutable(0)
        let (model, store) = makeModel(
            .supported(v130, defaults), reads: [.success(.records([record(3, "demo-1")]))],
            policy: automatic(noting: noted)
        )
        await model.load()
        #expect(store.journalWrites == [beadyRetention], "one set-many, with the day and the thousand rows")
        #expect(model.journal.isOn)
        #expect(model.pendingChange == nil, "no confirmation sheet: this is Beady's own setting, not a bead")
        #expect(noted.value == 1, "the app is told, so it can remember this workspace")
        #expect(model.recentChange(to: "demo-1")?.actor == "agent-7", "and the journal is followed from then on")

        store.setToken("t1")
        await model.refreshIfChanged()
        await model.load()
        #expect(store.journalWrites.count == 1, "later reloads don't write again")
    }

    @Test("a retention someone chose is left alone when Beady turns it on")
    func chosenRetentionKept() async {
        let chosen = JournalSettings(isEnabled: false, retainDays: 30, retainRows: 500)
        let (model, store) = makeModel(.supported(v130, chosen), policy: automatic())
        await model.load()
        #expect(store.journalWrites == [[ConfigSetting(key: "events-journal", value: "true")]])
        #expect(model.journal.isOn)
    }

    @Test("the Changes list names the workspace and offers an Undo")
    func listedWithUndo() async throws {
        let (model, _) = makeModel(.supported(v130, defaults), policy: automatic())
        await model.load()
        let entry = try #require(model.activity.first)
        #expect(entry.summary == "Turned on bd's change journal in demo")
        #expect(entry.succeeded)
        #expect(entry.issueID == nil)
        #expect(entry.undo == .journalSettings(backOff))
        #expect(model.activity.count == 1)
    }

    @Test("Undo writes the settings back to off, and the interaction log answers again")
    func undone() async throws {
        let (model, store) = makeModel(
            .supported(v130, defaults), reads: [.success(.records([record(3, "demo-2")]))], policy: automatic()
        )
        await model.load()
        #expect(model.recentChange(to: "demo-2")?.actor == "agent-7")
        let entry = try #require(model.activity.first)

        #expect(await model.undo(entry) == nil)
        #expect(store.journalWrites == [beadyRetention, backOff], "the reverse set-many")
        #expect(!model.journal.isOn)
        #expect(model.activity.first?.summary == "Turned bd's change journal off in demo")
        #expect(model.activity.last?.undo == nil, "undone is undone: the entry no longer offers it")
        #expect(model.recentChange(to: "demo-2")?.actor == "from-interactions")
        #expect(CommandCatalog.all(for: model).contains(.turnOnJournal), "the palette can turn it back on")
    }

    @Test("a workspace whose owner turned the journal off by hand is left off")
    func leftOffByHand() async {
        let (model, store) = makeModel(.supported(v130, defaults), policy: automatic(turnedOffByHand: true))
        await model.load()
        #expect(store.journalWrites.isEmpty)
        #expect(!model.journal.isOn)
        #expect(model.activity.isEmpty)
        #expect(CommandCatalog.all(for: model).contains(.turnOnJournal), "but ⌘P still can")
    }

    @Test("with the setting off nothing is written, and the palette command remains")
    func settingOff() async {
        let (model, store) = makeModel(.supported(v130, defaults), policy: .manual)
        await model.load()
        #expect(store.journalWrites.isEmpty)
        #expect(model.activity.isEmpty)
        #expect(model.recentChange(to: "demo-2")?.actor == "from-interactions", "the old way still works")
        #expect(CommandCatalog.all(for: model).contains(.turnOnJournal))
    }

    @Test("a read-only workspace writes nothing")
    func readOnly() async {
        let (model, store) = makeModel(.supported(v130, defaults), policy: automatic(), allowsWriting: false)
        await model.load()
        #expect(store.journalWrites.isEmpty)
        #expect(model.activity.isEmpty)
        #expect(await model.enableJournal() == nil)
        #expect(store.journalWrites.isEmpty)
        #expect(!CommandCatalog.all(for: model).contains(.turnOnJournal))
    }

    @Test("a journal already on is followed, not written to")
    func alreadyOn() async {
        let (model, store) = makeModel(.supported(v130, on), policy: automatic())
        await model.load()
        #expect(store.journalWrites.isEmpty)
        #expect(model.activity.isEmpty)
        #expect(model.journal.isOn)
    }

    @Test("a write that fails is listed as failed, and bd is left as it was")
    func writeFails() async throws {
        let (model, store) = makeModel(.supported(v130, defaults), policy: automatic())
        store.journalWriteFailure = LoadFailure()
        await model.load()
        let entry = try #require(model.activity.first)
        #expect(!entry.succeeded)
        #expect(entry.message == "bd exploded")
        #expect(entry.undo == nil)
        #expect(!model.journal.isOn)
    }

    @Test("turning it on from the palette takes the same path: written, listed, undoable, then followed")
    func enabling() async {
        let noted = Mutable(0)
        let policy = JournalPolicy(turnsOnAutomatically: false) { noted.value += 1 }
        let (model, store) = makeModel(
            .supported(v130, defaults), reads: [.success(.records([record(3, "demo-1")]))], policy: policy
        )
        await model.load()
        #expect(store.journalWrites.isEmpty)
        #expect(await model.enableJournal() == nil)
        #expect(store.journalWrites == [beadyRetention])
        #expect(noted.value == 1)
        #expect(model.journal.isOn)
        #expect(model.activity.first?.undo == .journalSettings(backOff))
        #expect(model.recentChange(to: "demo-1")?.actor == "agent-7")
    }

    @Test("with the journal on, activity comes from it, and each read resumes from the last record seen")
    func following() async {
        let (model, store) = makeModel(.supported(v130, on), reads: [
            .success(.records([record(1, "demo-1", ago: 60), record(3, "demo-2", ago: 20)])),
            .success(.records([record(4, "demo-1", actor: "agent-9", ago: 5)])),
        ])
        await model.load()
        #expect(model.recentChange(to: "demo-2")?.actor == "agent-7", "the journal, not the interaction log")
        #expect(model.beadsChangedElsewhere == ["demo-1", "demo-2"])

        store.setToken("t1")
        await model.refreshIfChanged()
        #expect(store.journalCheckpoints == [0, 3])
        #expect(model.recentChange(to: "demo-1")?.actor == "agent-9")
        #expect(model.recentChange(to: "demo-2")?.actor == "agent-7", "earlier records are kept, not replaced")
    }

    @Test("a checkpoint bd has pruned past resumes from what's left, straight away")
    func truncated() async {
        let (model, store) = makeModel(.supported(v130, on), reads: [
            .success(.records([record(3, "demo-1")])),
            .success(.truncated(floor: 41)),
            .success(.records([record(41, "demo-2")])),
        ])
        await model.load()
        store.setToken("t1")
        await model.refreshIfChanged()
        #expect(store.journalCheckpoints == [0, 3, 40])
        #expect(model.recentChange(to: "demo-2")?.actor == "agent-7")
    }

    @Test("if the journal can't be read, the interaction log still answers")
    func fallsBack() async {
        let (model, _) = makeModel(.supported(v130, on), reads: [.failure(LoadFailure())])
        await model.load()
        #expect(model.recentChange(to: "demo-2")?.actor == "from-interactions")
    }
}
