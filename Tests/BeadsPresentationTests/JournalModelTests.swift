import BeadsCore
import BeadsPresentation
import Foundation
import Testing

@MainActor
@Suite("The events journal, as the window uses it")
struct JournalModelTests {
    let v130 = BeadsVersion(1, 3, 0)
    let defaults = JournalSettings(isEnabled: false, retainDays: 7, retainRows: 100_000)
    var on: JournalSettings { JournalSettings(isEnabled: true, retainDays: 1, retainRows: 1_000) }

    func record(_ seq: Int64, _ id: IssueID, actor: String? = "agent-7", ago: TimeInterval = 30) -> JournalRecord {
        JournalRecord(seq: seq, date: t0 - ago, op: "update", issueID: id, actor: actor)
    }

    func makeModel(
        _ journal: JournalStatus,
        reads: [Result<JournalRead, Error>] = [],
        declined: Bool = false,
        allowsWriting: Bool = true
    ) -> (WorkspaceModel, StubStore) {
        let store = StubStore([makeIssue("demo-1"), makeIssue("demo-2")])
        store.journal = journal
        store.journalReads = reads
        store.interactions = ActivityLog(entries: [
            ActivityEntry(issueID: "demo-2", actor: "from-interactions", date: t0 - 10, field: "status"),
        ])
        let model = WorkspaceModel(
            title: "demo", store: store, allowsWriting: allowsWriting, now: { t0 }, declinedJournal: declined
        )
        return (model, store)
    }

    @Test("with a bd older than 1.3 nothing changes: the interaction log reports activity, and nothing is offered")
    func unsupported() async {
        let (model, store) = makeModel(.unsupported(BeadsVersion(1, 2, 0)))
        await model.load()
        #expect(model.journal == .unsupported(BeadsVersion(1, 2, 0)))
        #expect(!model.offersJournal)
        #expect(store.journalCheckpoints.isEmpty)
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

    @Test("with 1.3 and the journal off, turning it on is offered, and it's the user's call")
    func offered() async {
        let (model, store) = makeModel(.supported(v130, defaults))
        await model.load()
        #expect(model.offersJournal)
        #expect(CommandCatalog.all(for: model).contains(.turnOnJournal))
        #expect(store.enabledJournal.isEmpty, "nothing is written until they agree")
        #expect(model.recentChange(to: "demo-2")?.actor == "from-interactions", "until then, the old way still works")
        #expect(model.journalCommands == [
            "bd config set-many events-journal=true events-journal-retain-days=1 events-journal-retain-rows=1000",
        ])
    }

    @Test("the offer says what changes for everyone, how long records are kept, and the exact command")
    func offerWording() async throws {
        let (model, _) = makeModel(.supported(v130, defaults))
        await model.load()
        let message = try #require(model.journalOffer)
        #expect(message.contains("bd 1.3.0"))
        #expect(message.contains("every bd command in this workspace, agents' included"))
        #expect(message.contains("a day"))
        #expect(message.contains("bd config set-many events-journal=true"))

        let (custom, _) = makeModel(.supported(v130, JournalSettings(isEnabled: false, retainDays: 30, retainRows: 500)))
        await custom.load()
        let kept = try #require(custom.journalOffer)
        #expect(kept.contains("Your retention settings are kept"))
        #expect(!kept.contains("a day"))

        let (old, _) = makeModel(.unsupported(BeadsVersion(1, 2, 0)))
        await old.load()
        #expect(old.journalOffer == nil)
    }

    @Test("saying no stops the offer, but the palette can still turn it on later")
    func declined() async {
        let (model, _) = makeModel(.supported(v130, defaults))
        await model.load()
        model.declineJournal()
        #expect(!model.offersJournal)
        #expect(model.journalDeclined)
        #expect(CommandCatalog.all(for: model).contains(.turnOnJournal))

        let (remembered, _) = makeModel(.supported(v130, defaults), declined: true)
        await remembered.load()
        #expect(!remembered.offersJournal)
    }

    @Test("a window that can't write can't turn it on")
    func readOnly() async {
        let (model, _) = makeModel(.supported(v130, defaults), allowsWriting: false)
        await model.load()
        #expect(!model.offersJournal)
        #expect(await model.enableJournal() == nil)
        #expect(!CommandCatalog.all(for: model).contains(.turnOnJournal))
    }

    @Test("turning it on writes the journal setting with Beady's retention, then uses the journal")
    func enabling() async {
        let (model, store) = makeModel(.supported(v130, defaults), reads: [.success(.records([record(3, "demo-1")]))])
        await model.load()
        #expect(await model.enableJournal() == nil)
        #expect(store.enabledJournal == [JournalRetention.settings(toEnable: defaults)])
        #expect(model.journal.isOn)
        #expect(!model.offersJournal)
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
