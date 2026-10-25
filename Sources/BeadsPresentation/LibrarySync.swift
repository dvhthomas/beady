import BeadsCore
import Foundation

/// Keeping the view Library the same on every Mac signed into one Apple ID, through iCloud's
/// Key-Value Store. The store holds one record per view (its document and when it last changed)
/// and a tombstone per deleted view, so a deletion travels too and a Mac that was asleep doesn't
/// bring the view back. The folder of `.beadyview` files stays the Library; the store mirrors it.
///
/// The decision of what to copy which way is a pure function of both sides, so it is tested
/// without iCloud; the app feeds it the folder and the store and carries the plan out.
public enum LibrarySync {
    /// How long a tombstone outlives the view, so every Mac has a chance to see it.
    public static let tombstoneLifetime: TimeInterval = 30 * 86_400

    /// A view as one side holds it: its document and when it last changed. Codable is how a
    /// record travels through the store: the document as base64, the date as seconds.
    public struct Entry: Equatable, Sendable, Codable {
        public let document: Data
        public let modified: Date

        public init(document: Data, modified: Date) {
            self.document = document
            self.modified = modified
        }

        public func encoded() throws -> Data {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .secondsSince1970
            return try encoder.encode(self)
        }

        public static func decode(_ data: Data) -> Entry? {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .secondsSince1970
            return try? decoder.decode(Entry.self, from: data)
        }
    }

    /// Everything one side knows: records by view id, tombstones by view id.
    public struct Side: Equatable, Sendable {
        public var entries: [IssueView.ID: Entry]
        public var tombstones: [IssueView.ID: Date]

        public init(entries: [IssueView.ID: Entry] = [:], tombstones: [IssueView.ID: Date] = [:]) {
            self.entries = entries
            self.tombstones = tombstones
        }
    }

    /// What to do to bring the two sides together.
    public struct Plan: Equatable, Sendable {
        public var writeLocal: [IssueView.ID: Entry] = [:]
        public var deleteLocal: Set<IssueView.ID> = []
        public var writeRemote: [IssueView.ID: Entry] = [:]
        /// Views deleted here since the last sync: the record goes, a tombstone takes its place.
        public var tombstoneRemote: Set<IssueView.ID> = []
        /// Tombstones to clear: the view is back, or the tombstone has outlived its use.
        public var clearTombstones: Set<IssueView.ID> = []
        /// What both sides hold once the plan is carried out: the next sync's `synced`.
        public var synced: Set<IssueView.ID> = []

        public init() {}

        public var isEmpty: Bool {
            writeLocal.isEmpty && deleteLocal.isEmpty && writeRemote.isEmpty && tombstoneRemote.isEmpty && clearTombstones.isEmpty
        }
    }

    /// Last writer wins per view; a view on one side only is copied to the other, unless it was
    /// deleted on the other side after it last changed. `synced` is the set of views both sides
    /// held after the previous sync, which is how a local deletion is told from a view that
    /// hasn't arrived yet.
    public static func plan(local: Side, remote: Side, synced: Set<IssueView.ID>, now: Date) -> Plan {
        var plan = Plan()
        let ids = Set(local.entries.keys).union(remote.entries.keys).union(remote.tombstones.keys).union(synced)
        for id in ids {
            let mine = local.entries[id]
            let theirs = remote.entries[id]
            let tombstone = remote.tombstones[id]
            switch (mine, theirs) {
            case (let mine?, let theirs?):
                if mine.document != theirs.document {
                    if mine.modified > theirs.modified {
                        plan.writeRemote[id] = mine
                    } else {
                        plan.writeLocal[id] = theirs
                    }
                }
                if tombstone != nil { plan.clearTombstones.insert(id) }
                plan.synced.insert(id)
            case (let mine?, nil):
                if let tombstone, tombstone >= mine.modified {
                    // Deleted on another Mac after this copy last changed.
                    plan.deleteLocal.insert(id)
                } else {
                    plan.writeRemote[id] = mine
                    if tombstone != nil { plan.clearTombstones.insert(id) }
                    plan.synced.insert(id)
                }
            case (nil, let theirs?):
                if synced.contains(id) {
                    // It was here and is gone: deleted on this Mac.
                    plan.tombstoneRemote.insert(id)
                } else if let tombstone, tombstone >= theirs.modified {
                    // A record a tombstone has already answered; nothing to bring back.
                    break
                } else {
                    plan.writeLocal[id] = theirs
                    plan.synced.insert(id)
                }
            case (nil, nil):
                if let tombstone, now.timeIntervalSince(tombstone) > tombstoneLifetime {
                    plan.clearTombstones.insert(id)
                }
            }
        }
        return plan
    }
}

/// What the app needs from iCloud's Key-Value Store, or a stand-in for it in tests.
public protocol LibrarySyncStore: AnyObject {
    /// Every record and tombstone the store holds right now.
    func read() -> LibrarySync.Side
    func write(_ entry: LibrarySync.Entry, for id: IssueView.ID)
    func removeEntry(for id: IssueView.ID)
    func writeTombstone(_ date: Date, for id: IssueView.ID)
    func removeTombstone(for id: IssueView.ID)
}

/// A Library folder as a sync side, and the plan carried out on it. Files are the truth on this
/// Mac; a pulled view is written with the record's date, so the next look sees them agree.
public enum LibrarySyncFolder {
    /// The user's views in the folder, by id, with when each file last changed.
    public static func read(_ directory: URL) -> LibrarySync.Side {
        var entries: [IssueView.ID: LibrarySync.Entry] = [:]
        let manager = FileManager.default
        for name in (try? manager.contentsOfDirectory(atPath: directory.path)) ?? [] where name.hasSuffix(".\(ViewLibrary.fileExtension)") {
            let url = directory.appendingPathComponent(name)
            guard let data = manager.contents(atPath: url.path),
                  let view = (try? ViewLibrary.views(fromDocument: data))?.first, !view.isBuiltIn else { continue }
            let modified = (try? manager.attributesOfItem(atPath: url.path)[.modificationDate] as? Date) ?? .distantPast
            entries[view.id] = LibrarySync.Entry(document: data, modified: modified)
        }
        return LibrarySync.Side(entries: entries)
    }

    /// Carries a plan out: files in the folder, records and tombstones in the store.
    public static func apply(_ plan: LibrarySync.Plan, to directory: URL, store: LibrarySyncStore, now: Date) {
        let manager = FileManager.default
        try? manager.createDirectory(at: directory, withIntermediateDirectories: true)
        for (id, entry) in plan.writeLocal {
            let url = directory.appendingPathComponent("\(id.rawValue).\(ViewLibrary.fileExtension)")
            try? entry.document.write(to: url, options: .atomic)
            try? manager.setAttributes([.modificationDate: entry.modified], ofItemAtPath: url.path)
        }
        for id in plan.deleteLocal {
            try? manager.removeItem(at: directory.appendingPathComponent("\(id.rawValue).\(ViewLibrary.fileExtension)"))
        }
        for (id, entry) in plan.writeRemote { store.write(entry, for: id) }
        for id in plan.tombstoneRemote {
            store.removeEntry(for: id)
            store.writeTombstone(now, for: id)
        }
        for id in plan.clearTombstones { store.removeTombstone(for: id) }
    }
}
