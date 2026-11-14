import BeadsCore
import BeadsPresentation
import Foundation
import Testing

/// The Library over iCloud's Key-Value Store: last writer wins per view, deletions travel as
/// tombstones, and nothing is decided that a fake store can't exercise.
@Suite("Library sync")
struct LibrarySyncTests {
    final class FakeStore: LibrarySyncStore {
        var side = LibrarySync.Side()
        func read() -> LibrarySync.Side { side }
        func write(_ entry: LibrarySync.Entry, for id: IssueView.ID) { side.entries[id] = entry }
        func removeEntry(for id: IssueView.ID) { side.entries[id] = nil }
        func writeTombstone(_ date: Date, for id: IssueView.ID) { side.tombstones[id] = date }
        func removeTombstone(for id: IssueView.ID) { side.tombstones[id] = nil }
    }

    func entry(_ text: String, at offset: TimeInterval) -> LibrarySync.Entry {
        LibrarySync.Entry(document: Data(text.utf8), modified: t0.addingTimeInterval(offset))
    }

    let a = IssueView.ID("a"), b = IssueView.ID("b"), c = IssueView.ID("c")

    @Test("a view on one side only is copied to the other")
    func copies() {
        let plan = LibrarySync.plan(
            local: LibrarySync.Side(entries: [a: entry("A", at: 0)]),
            remote: LibrarySync.Side(entries: [b: entry("B", at: 0)]),
            synced: [], now: t0
        )
        #expect(Set(plan.writeRemote.keys) == [a])
        #expect(Set(plan.writeLocal.keys) == [b])
        #expect(plan.deleteLocal.isEmpty && plan.tombstoneRemote.isEmpty)
        #expect(plan.synced == [a, b])
    }

    @Test("the same document on both sides is nothing to do; a different one goes the newer way")
    func lastWriterWins() {
        let same = LibrarySync.plan(local: LibrarySync.Side(entries: [a: entry("A", at: 0)]), remote: LibrarySync.Side(entries: [a: entry("A", at: 50)]), synced: [a], now: t0)
        #expect(same.isEmpty)
        #expect(same.synced == [a])
        let mineNewer = LibrarySync.plan(local: LibrarySync.Side(entries: [a: entry("A2", at: 10)]), remote: LibrarySync.Side(entries: [a: entry("A", at: 0)]), synced: [a], now: t0)
        #expect(mineNewer.writeRemote[a] == entry("A2", at: 10))
        #expect(mineNewer.writeLocal.isEmpty)
        let theirsNewer = LibrarySync.plan(local: LibrarySync.Side(entries: [a: entry("A", at: 0)]), remote: LibrarySync.Side(entries: [a: entry("A2", at: 10)]), synced: [a], now: t0)
        #expect(theirsNewer.writeLocal[a] == entry("A2", at: 10))
        #expect(theirsNewer.writeRemote.isEmpty)
    }

    @Test("a view deleted here since the last sync leaves a tombstone and takes the record with it")
    func deletedHere() {
        let plan = LibrarySync.plan(local: LibrarySync.Side(), remote: LibrarySync.Side(entries: [a: entry("A", at: 0)]), synced: [a], now: t0)
        #expect(plan.tombstoneRemote == [a])
        #expect(plan.writeLocal.isEmpty, "not brought back")
        #expect(!plan.synced.contains(a))
    }

    @Test("a tombstone newer than the local copy deletes it; an older one loses to a later edit and is cleared")
    func deletedElsewhere() {
        let newer = LibrarySync.plan(local: LibrarySync.Side(entries: [a: entry("A", at: 0)]), remote: LibrarySync.Side(tombstones: [a: t0.addingTimeInterval(5)]), synced: [a], now: t0)
        #expect(newer.deleteLocal == [a])
        #expect(newer.writeRemote.isEmpty)
        let older = LibrarySync.plan(local: LibrarySync.Side(entries: [a: entry("A2", at: 10)]), remote: LibrarySync.Side(tombstones: [a: t0.addingTimeInterval(5)]), synced: [], now: t0)
        #expect(Set(older.writeRemote.keys) == [a])
        #expect(older.clearTombstones == [a])
        // A record left beside a newer tombstone is not brought back either.
        let stale = LibrarySync.plan(local: LibrarySync.Side(), remote: LibrarySync.Side(entries: [a: entry("A", at: 0)], tombstones: [a: t0.addingTimeInterval(5)]), synced: [], now: t0)
        #expect(stale.isEmpty)
    }

    @Test("a record travels as JSON and comes back whole")
    func recordEncoding() throws {
        let record = entry("{\"beadyView\":1}", at: 12.5)
        let data = try record.encoded()
        #expect(LibrarySync.Entry.decode(data) == record)
        #expect(LibrarySync.Entry.decode(Data("junk".utf8)) == nil)
    }

    @Test("a tombstone is kept for thirty days, then cleared")
    func tombstoneLifetime() {
        let fresh = LibrarySync.plan(local: LibrarySync.Side(), remote: LibrarySync.Side(tombstones: [a: t0.addingTimeInterval(-29 * 86_400)]), synced: [], now: t0)
        #expect(fresh.isEmpty)
        let old = LibrarySync.plan(local: LibrarySync.Side(), remote: LibrarySync.Side(tombstones: [a: t0.addingTimeInterval(-31 * 86_400)]), synced: [], now: t0)
        #expect(old.clearTombstones == [a])
    }

    @Test("a folder and a fake store converge, and converge again after an edit and a delete on each side")
    func roundTrip() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("beady-sync-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        func view(_ name: String, id: String, symbol: String = "bookmark") -> IssueView {
            IssueView(id: IssueView.ID(id), name: name, symbol: symbol, filter: ViewFilter(), presentation: ViewPresentation())
        }
        func files() -> [String] { ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).sorted() }
        let store = FakeStore()
        try view("Mine", id: "mine").documentData().write(to: folder.appendingPathComponent("mine.beadyview"))
        store.write(LibrarySync.Entry(document: try view("Theirs", id: "theirs").documentData(), modified: t0), for: IssueView.ID("theirs"))
        var builtIn = IssueView.builtIn(.pipeline)!
        builtIn.presentation.layout = .list
        try builtIn.documentData().write(to: folder.appendingPathComponent("pipeline.beadyview"))

        var synced: Set<IssueView.ID> = []
        func sync(now: Date) {
            let plan = LibrarySync.plan(local: LibrarySyncFolder.read(folder), remote: store.read(), synced: synced, now: now)
            LibrarySyncFolder.apply(plan, to: folder, store: store, now: now)
            synced = plan.synced
        }
        sync(now: t0)
        #expect(files() == ["mine.beadyview", "pipeline.beadyview", "theirs.beadyview"])
        #expect(Set(store.read().entries.keys) == [IssueView.ID("mine"), IssueView.ID("theirs")], "a built-in's remembered layout is this Mac's, not the Library's")
        #expect(synced == [IssueView.ID("mine"), IssueView.ID("theirs")])
        #expect(LibrarySync.plan(local: LibrarySyncFolder.read(folder), remote: store.read(), synced: synced, now: t0).isEmpty, "converged")

        // The other Mac renames theirs and deletes mine; this Mac edits nothing.
        store.write(LibrarySync.Entry(document: try view("Theirs renamed", id: "theirs").documentData(), modified: t0.addingTimeInterval(60)), for: IssueView.ID("theirs"))
        store.removeEntry(for: IssueView.ID("mine"))
        store.writeTombstone(t0.addingTimeInterval(60), for: IssueView.ID("mine"))
        sync(now: t0.addingTimeInterval(120))
        #expect(files() == ["pipeline.beadyview", "theirs.beadyview"])
        #expect(try ViewLibrary.views(fromDocument: Data(contentsOf: folder.appendingPathComponent("theirs.beadyview"))).first?.name == "Theirs renamed")

        // This Mac deletes theirs: the record goes and a tombstone says so.
        try FileManager.default.removeItem(at: folder.appendingPathComponent("theirs.beadyview"))
        sync(now: t0.addingTimeInterval(180))
        #expect(store.read().entries.isEmpty)
        #expect(store.read().tombstones[IssueView.ID("theirs")] == t0.addingTimeInterval(180))
        #expect(files() == ["pipeline.beadyview"])
    }

    @Test("applying a plan writes and deletes only inside the folder, and only records that parse as the view they claim to be")
    func applyRefusesHostileRecords() throws {
        let parent = FileManager.default.temporaryDirectory.appendingPathComponent("beady-sync-\(UUID().uuidString)", isDirectory: true)
        let folder = parent.appendingPathComponent("views", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let victim = parent.appendingPathComponent("victim.beadyview")
        try Data("mine".utf8).write(to: victim)
        func document(_ name: String, id: String) throws -> Data {
            try IssueView(id: IssueView.ID(id), name: name, symbol: "bookmark", filter: ViewFilter(), presentation: ViewPresentation()).documentData()
        }

        var plan = LibrarySync.Plan()
        // A key that names a path, raw bytes that aren't a view, and a document whose own id
        // doesn't match its key: none of them may touch the disk.
        plan.writeLocal[IssueView.ID("../victim")] = LibrarySync.Entry(document: try document("Escape", id: "../victim"), modified: t0)
        plan.writeLocal[IssueView.ID("garbage")] = LibrarySync.Entry(document: Data("not a view".utf8), modified: t0)
        plan.writeLocal[IssueView.ID("mismatch")] = LibrarySync.Entry(document: try document("Other", id: "other"), modified: t0)
        plan.writeLocal[IssueView.ID("good")] = LibrarySync.Entry(document: try document("Good", id: "good"), modified: t0)
        plan.deleteLocal = [IssueView.ID("../victim")]
        LibrarySyncFolder.apply(plan, to: folder, store: FakeStore(), now: t0)

        let written = ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).sorted()
        #expect(written == ["good.beadyview"])
        #expect(FileManager.default.contents(atPath: victim.path) == Data("mine".utf8), "nothing outside the folder was replaced or removed")
    }

    @Test("a folder file whose content claims an id that couldn't be a file name never enters the store")
    func readRefusesHostileIDs() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("beady-sync-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let evil = IssueView(id: IssueView.ID("../escape"), name: "Evil", symbol: "bookmark", filter: ViewFilter(), presentation: ViewPresentation())
        try evil.documentData().write(to: folder.appendingPathComponent("innocent-name.beadyview"))
        #expect(LibrarySyncFolder.read(folder).entries.isEmpty)
    }
}
