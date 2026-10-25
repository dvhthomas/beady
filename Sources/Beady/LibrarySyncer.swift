import BeadsCore
import BeadsPresentation
import Foundation
import Security

/// iCloud's Key-Value Store as the Library's other side: one `view.<id>` record per view, one
/// `tomb.<id>` date per deleted view. A view is a few hundred bytes against the store's megabyte.
final class UbiquitousLibraryStore: LibrarySyncStore {
    private static let viewPrefix = "view."
    private static let tombstonePrefix = "tomb."
    private let store = NSUbiquitousKeyValueStore.default

    /// Whether this build may use the store at all. The entitlement comes with a signed build
    /// (scripts/bundle.sh with CODESIGN_IDENTITY); an ad-hoc build runs without it, and the
    /// setting says so rather than pretending.
    static var isEntitled: Bool {
        guard let task = SecTaskCreateFromSelf(nil) else { return false }
        return SecTaskCopyValueForEntitlement(task, "com.apple.developer.ubiquity-kvstore-identifier" as CFString, nil) != nil
    }

    func read() -> LibrarySync.Side {
        var side = LibrarySync.Side()
        for (key, value) in store.dictionaryRepresentation {
            if key.hasPrefix(Self.viewPrefix), let data = value as? Data, let entry = LibrarySync.Entry.decode(data) {
                side.entries[IssueView.ID(String(key.dropFirst(Self.viewPrefix.count)))] = entry
            } else if key.hasPrefix(Self.tombstonePrefix), let seconds = value as? Double {
                side.tombstones[IssueView.ID(String(key.dropFirst(Self.tombstonePrefix.count)))] = Date(timeIntervalSince1970: seconds)
            }
        }
        return side
    }

    func write(_ entry: LibrarySync.Entry, for id: IssueView.ID) {
        guard let data = try? entry.encoded() else { return }
        store.set(data, forKey: Self.viewPrefix + id.rawValue)
    }

    func removeEntry(for id: IssueView.ID) {
        store.removeObject(forKey: Self.viewPrefix + id.rawValue)
    }

    func writeTombstone(_ date: Date, for id: IssueView.ID) {
        store.set(date.timeIntervalSince1970, forKey: Self.tombstonePrefix + id.rawValue)
    }

    func removeTombstone(for id: IssueView.ID) {
        store.removeObject(forKey: Self.tombstonePrefix + id.rawValue)
    }

    /// Asks iCloud for what other Macs wrote; the answer arrives as a notification.
    func synchronize() {
        store.synchronize()
    }
}

/// Keeps the Library folder and the store the same: once on start, whenever the folder changes
/// (the session's watcher calls `sync`), and whenever iCloud reports what another Mac wrote. The
/// decision is `LibrarySync.plan`; this only carries it out and remembers what both sides held.
@MainActor
final class LibrarySyncer {
    private static let syncedKey = "librarySyncedViews"
    private let directory: URL
    private let store: UbiquitousLibraryStore
    private let preferences: UserDefaults
    private let onPulled: () -> Void
    private var observer: NSObjectProtocol?

    init(directory: URL, store: UbiquitousLibraryStore, preferences: UserDefaults, onPulled: @escaping () -> Void) {
        self.directory = directory
        self.store = store
        self.preferences = preferences
        self.onPulled = onPulled
    }

    func start() {
        observer = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: NSUbiquitousKeyValueStore.default,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.sync() }
        }
        store.synchronize()
        sync()
    }

    func stop() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
    }

    /// One pass: what differs goes the newer way, a deletion either way travels.
    func sync() {
        let synced = Set((preferences.stringArray(forKey: Self.syncedKey) ?? []).map { IssueView.ID($0) })
        let now = Date()
        let plan = LibrarySync.plan(local: LibrarySyncFolder.read(directory), remote: store.read(), synced: synced, now: now)
        LibrarySyncFolder.apply(plan, to: directory, store: store, now: now)
        preferences.set(plan.synced.map { $0.rawValue }.sorted(), forKey: Self.syncedKey)
        if !plan.writeLocal.isEmpty || !plan.deleteLocal.isEmpty { onPulled() }
    }
}
