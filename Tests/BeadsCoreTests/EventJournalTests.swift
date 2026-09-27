import BeadsCore
import Foundation
import Testing

@Suite("bd's version")
struct BeadsVersionTests {
    @Test("reads the forms bd and people write a version in")
    func parsing() {
        #expect(BeadsVersion(parsing: "1.3.0") == BeadsVersion(1, 3, 0))
        #expect(BeadsVersion(parsing: "v1.3.0") == BeadsVersion(1, 3, 0))
        #expect(BeadsVersion(parsing: "bd version 1.3.0 (f45b249ce: HEAD@f45b249ce6b4)") == BeadsVersion(1, 3, 0))
        #expect(BeadsVersion(parsing: "1.4.0-rc.1") == BeadsVersion(1, 4, 0))
        #expect(BeadsVersion(parsing: "0.62") == BeadsVersion(0, 62, 0))
        #expect(BeadsVersion(parsing: "dev") == nil)
        #expect(BeadsVersion(parsing: "") == nil)
    }

    @Test("compares numerically, so 1.10 is newer than 1.3")
    func ordering() {
        #expect(BeadsVersion(1, 10, 0) > BeadsVersion(1, 3, 0))
        #expect(BeadsVersion(1, 3, 1) > BeadsVersion(1, 3, 0))
        #expect(BeadsVersion(2, 0, 0) > BeadsVersion(1, 99, 99))
    }

    @Test("the journal arrived in 1.3.0")
    func journalSupport() {
        #expect(!BeadsVersion(1, 2, 9).supportsEventsJournal)
        #expect(!BeadsVersion(0, 62, 1).supportsEventsJournal)
        #expect(BeadsVersion(1, 3, 0).supportsEventsJournal)
        #expect(BeadsVersion(2, 0, 0).supportsEventsJournal)
        #expect(BeadsVersion(1, 3, 0).description == "1.3.0")
    }
}

@Suite("Whether the journal can be used")
struct JournalStatusTests {
    let off = JournalSettings(isEnabled: false, retainDays: 7, retainRows: 100_000)
    let on = JournalSettings(isEnabled: true, retainDays: 1, retainRows: 1_000)

    @Test("an old or unknown bd has no journal to turn on, so the file watcher is all there is")
    func unsupported() {
        for status in [JournalStatus.unsupported(BeadsVersion(1, 2, 0)), .unsupported(nil)] {
            #expect(!status.isOn)
            #expect(!status.canBeTurnedOn)
        }
    }

    @Test("a new enough bd with the journal off can have it turned on; with it on, it's in use")
    func supported() {
        #expect(JournalStatus.supported(BeadsVersion(1, 3, 0), off).canBeTurnedOn)
        #expect(!JournalStatus.supported(BeadsVersion(1, 3, 0), off).isOn)
        #expect(JournalStatus.supported(BeadsVersion(1, 3, 0), on).isOn)
        #expect(!JournalStatus.supported(BeadsVersion(1, 3, 0), on).canBeTurnedOn)
    }
}

@Suite("Journal retention")
struct JournalRetentionTests {
    @Test("turning it on also shrinks bd's week-long default to what Beady reads: a day")
    func fromDefaults() {
        let current = JournalSettings(isEnabled: false, retainDays: 7, retainRows: 100_000)
        #expect(JournalRetention.settings(toEnable: current) == [
            ConfigSetting(key: "events-journal", value: "true"),
            ConfigSetting(key: "events-journal-retain-days", value: "1"),
            ConfigSetting(key: "events-journal-retain-rows", value: "1000"),
        ])
    }

    @Test("retention someone chose is theirs: only bd's own defaults are replaced")
    func respectsChoices() {
        let chosen = JournalSettings(isEnabled: false, retainDays: 30, retainRows: 500)
        #expect(JournalRetention.settings(toEnable: chosen) == [ConfigSetting(key: "events-journal", value: "true")])

        let mixed = JournalSettings(isEnabled: false, retainDays: 7, retainRows: 0)
        #expect(JournalRetention.settings(toEnable: mixed) == [
            ConfigSetting(key: "events-journal", value: "true"),
            ConfigSetting(key: "events-journal-retain-days", value: "1"),
        ])
    }

    @Test("an unreadable setting is left alone rather than guessed at")
    func unknownValues() {
        let unknown = JournalSettings(isEnabled: false, retainDays: nil, retainRows: nil)
        #expect(JournalRetention.settings(toEnable: unknown) == [ConfigSetting(key: "events-journal", value: "true")])
    }

    @Test("the retained day covers the window Beady warns about, with room to spare")
    func coversActivityWindow() {
        #expect(TimeInterval(JournalRetention.days) * 86_400 > 600)
        #expect(JournalRetention.days < JournalRetention.bdDefaultDays)
        #expect(JournalRetention.rows < JournalRetention.bdDefaultRows)
        #expect(JournalRetention.days > 0, "0 turns the floor off; with rows also 0 the journal would never be pruned")
    }
}

@Suite("Following the journal")
struct JournalFeedTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func record(_ seq: Int64, _ id: IssueID, _ op: String = "update", actor: String? = "agent-7", ago: TimeInterval = 0) -> JournalRecord {
        JournalRecord(seq: seq, date: now.addingTimeInterval(-ago), op: op, issueID: id, actor: actor)
    }

    @Test("records become activity, newest first, and the checkpoint moves to the last one read")
    func applying() {
        let feed = JournalFeed().applying(
            .records([record(1, "demo-1", "create", ago: 30), record(2, "demo-2", ago: 20), record(3, "demo-1", "close", ago: 10)]),
            keepingSince: now.addingTimeInterval(-3_600)
        )
        #expect(feed.checkpoint == 3)
        #expect(feed.activity.entries.map(\.issueID) == ["demo-1", "demo-2", "demo-1"])
        #expect(feed.activity.entries.map(\.actor) == ["agent-7", "agent-7", "agent-7"])
        #expect(feed.activity.latestChange(to: "demo-2", since: now.addingTimeInterval(-60))?.date == now.addingTimeInterval(-20))
    }

    @Test("a create names who created the bead, so History can say so")
    func createdField() {
        let feed = JournalFeed().applying(.records([record(1, "demo-1", "create")]), keepingSince: .distantPast)
        #expect(feed.activity.entries.first?.field == "created")
    }

    @Test("bd's own follow-on writes carry no actor and aren't reported as someone's work")
    func actorless() {
        let feed = JournalFeed().applying(
            .records([record(1, "demo-1", "close"), record(2, "demo-9", actor: nil), record(3, "demo-8", actor: "")]),
            keepingSince: .distantPast
        )
        #expect(feed.checkpoint == 3, "they still move the checkpoint on")
        #expect(feed.activity.entries.map(\.issueID) == ["demo-1"])
    }

    @Test("reading the same records twice changes nothing")
    func idempotent() {
        let read = JournalRead.records([record(1, "demo-1"), record(2, "demo-2")])
        let once = JournalFeed().applying(read, keepingSince: .distantPast)
        #expect(once.applying(read, keepingSince: .distantPast) == once)
    }

    @Test("activity older than what's kept is let go, so a long session doesn't grow without bound")
    func trims() {
        let first = JournalFeed().applying(.records([record(1, "demo-1", ago: 7_200)]), keepingSince: .distantPast)
        let later = first.applying(.records([record(2, "demo-2")]), keepingSince: now.addingTimeInterval(-3_600))
        #expect(later.activity.entries.map(\.issueID) == ["demo-2"])
        #expect(later.checkpoint == 2)
    }

    @Test("a checkpoint bd has pruned past resumes from the oldest record left, keeping what was known")
    func truncated() {
        let known = JournalFeed().applying(.records([record(4, "demo-1")]), keepingSince: .distantPast)
        let resumed = known.applying(.truncated(floor: 41), keepingSince: .distantPast)
        #expect(resumed.checkpoint == 40)
        #expect(resumed.activity == known.activity)
    }

    @Test("an empty read is caught up, not a reason to move")
    func empty() {
        let feed = JournalFeed().applying(.records([record(7, "demo-1")]), keepingSince: .distantPast)
        #expect(feed.applying(.records([]), keepingSince: .distantPast) == feed)
    }
}
