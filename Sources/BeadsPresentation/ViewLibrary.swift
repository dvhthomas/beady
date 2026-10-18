import BeadsCore
import Foundation

/// What a view looks like on screen: its live filter and presentation, which may differ from the
/// view as saved.
public struct ViewState: Equatable, Codable, Sendable {
    public var filter: ViewFilter
    public var presentation: ViewPresentation

    public init(filter: ViewFilter, presentation: ViewPresentation) {
        self.filter = filter
        self.presentation = presentation
    }

    /// The view as saved: where it starts, and what Reset goes back to.
    public init(of view: IssueView) {
        self.init(filter: view.filter, presentation: view.presentation)
    }
}

/// Everything a workspace keeps about its views: the saved views (the built-ins with their
/// remembered presentation, then the user's own in name order), what is live on top of each, and
/// views an older Beady's saved state turned up that nobody has accepted or declined yet.
///
/// Saved views are the Library tier: one `.beadyview` document per view in a folder (the app
/// uses ~/Library/Application Support/Beady/views), so `cp` and a sync service both work. What is
/// live, and the offers, stay in preferences: they are this Mac's, not documents.
public struct ViewLibrary: Equatable, Sendable {
    /// Built-ins first, in table order, then the user's own views by name.
    public var views: [IssueView] {
        didSet {
            let ordered = Self.ordered(views)
            if ordered != views { views = ordered }
        }
    }
    public var live: [IssueView.ID: ViewState]
    public var offers: [IssueView]

    public init(views: [IssueView] = IssueView.builtIns, live: [IssueView.ID: ViewState] = [:], offers: [IssueView] = []) {
        self.views = Self.ordered(views)
        self.live = live
        self.offers = offers
    }

    private static func ordered(_ views: [IssueView]) -> [IssueView] {
        let builtIns = views.filter(\.isBuiltIn)
        let mine = views.filter { !$0.isBuiltIn }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        return builtIns + mine
    }

    public func view(_ id: IssueView.ID) -> IssueView? {
        views.first { $0.id == id }
    }

    func index(of id: IssueView.ID) -> Int? {
        views.firstIndex { $0.id == id }
    }

    // MARK: Loading and saving

    static let viewsKey = "views"
    static let liveKey = "liveViews"
    static let offersKey = "offeredViews"
    /// Where Beady kept one state per lifecycle scope, before views were saved filters.
    static let legacyKey = "viewStates"

    public static let fileExtension = "beadyview"
    /// An array of views, for "send me your views".
    public static let bundleExtension = "beadyviews"

    /// Reads the library back: views from the folder when there is one, what's live and the
    /// offers from preferences. Views an older Beady kept in preferences move to the folder once,
    /// and its per-scope blob is migrated once; both are then removed. Anything that can't be read
    /// is dropped rather than fought with: the library starts from the built-ins and is saved
    /// again on the next change.
    public static func load(from directory: URL?, preferences: UserDefaults?) -> ViewLibrary {
        var library = ViewLibrary()
        let decoder = JSONDecoder()
        if let preferences, let data = preferences.data(forKey: legacyKey) {
            library = ViewMigration.migrate(data) ?? ViewLibrary()
            preferences.removeObject(forKey: legacyKey)
            library.save(to: directory, preferences: preferences)
            return library
        }
        if let directory, let onDisk = readViews(in: directory) {
            library.views = merge(onDisk)
            preferences?.removeObject(forKey: viewsKey)
        } else if let preferences, let data = preferences.data(forKey: viewsKey),
                  let saved = try? decoder.decode([IssueView].self, from: data) {
            library.views = merge(saved)
            if let directory {
                // From preferences to files, once.
                library.writeViews(to: directory)
                preferences.removeObject(forKey: viewsKey)
            }
        }
        guard let preferences else { return library }
        if let data = preferences.data(forKey: liveKey), let saved = try? decoder.decode([SavedViewState].self, from: data) {
            library.live = Dictionary(saved.map { ($0.view, $0.state) }, uniquingKeysWith: { first, _ in first })
        }
        if let data = preferences.data(forKey: offersKey), let saved = try? decoder.decode([IssueView].self, from: data) {
            library.offers = saved
        }
        return library
    }

    /// Shorthand for a library kept in preferences alone.
    public static func load(from preferences: UserDefaults?) -> ViewLibrary {
        load(from: nil, preferences: preferences)
    }

    /// Every `.beadyview` in the folder that reads as a view; nil when the folder has no view
    /// files at all (not there yet, or empty), so preferences can be consulted instead.
    static func readViews(in directory: URL) -> [IssueView]? {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { return nil }
        let files = names.filter { $0.hasSuffix(".\(fileExtension)") }.sorted()
        guard !files.isEmpty else { return nil }
        return files.compactMap { name in
            guard let data = FileManager.default.contents(atPath: directory.appendingPathComponent(name).path) else { return nil }
            return (try? views(fromDocument: data))?.first
        }
    }

    /// The built-in table stays the definition: a saved built-in contributes only its remembered
    /// presentation, so a built-in's name, symbol and filter can change between Beady versions.
    /// User views follow in their saved order.
    static func merge(_ saved: [IssueView]) -> [IssueView] {
        let builtIns = IssueView.builtIns.map { builtIn in
            var view = builtIn
            if let remembered = saved.first(where: { $0.id == builtIn.id }) {
                view.presentation = remembered.presentation
            }
            return view
        }
        let ids = Set(builtIns.map(\.id))
        return builtIns + saved.filter { !$0.isBuiltIn && !ids.contains($0.id) }
    }

    /// Writes the views to the folder when there is one (else to preferences), and what's live
    /// and the offers to preferences.
    public func save(to directory: URL?, preferences: UserDefaults?) {
        let encoder = JSONEncoder()
        if let directory {
            writeViews(to: directory)
        } else if let preferences, let data = try? encoder.encode(views) {
            preferences.set(data, forKey: Self.viewsKey)
        }
        guard let preferences else { return }
        // A dictionary keyed by a struct doesn't encode as a JSON object, so one record per view,
        // in a stable order.
        let live = live.map { SavedViewState(view: $0.key, state: $0.value) }.sorted { $0.view.rawValue < $1.view.rawValue }
        if let data = try? encoder.encode(live) { preferences.set(data, forKey: Self.liveKey) }
        if let data = try? encoder.encode(offers) { preferences.set(data, forKey: Self.offersKey) }
    }

    public func save(to preferences: UserDefaults?) {
        save(to: nil, preferences: preferences)
    }

    /// One file per user view, and per built-in whose presentation differs from the table; a
    /// file whose content hasn't changed is left alone, so a folder watcher doesn't wake for
    /// nothing, and files for views that are gone are removed.
    func writeViews(to directory: URL) {
        let manager = FileManager.default
        try? manager.createDirectory(at: directory, withIntermediateDirectories: true)
        let wanted = views.filter { view in
            !view.isBuiltIn || IssueView.builtIn(view.id)?.presentation != view.presentation
        }
        var keep: Set<String> = []
        for view in wanted {
            let name = "\(view.id.rawValue).\(Self.fileExtension)"
            keep.insert(name)
            guard let data = try? view.documentData() else { continue }
            let url = directory.appendingPathComponent(name)
            if manager.contents(atPath: url.path) == data { continue }
            try? data.write(to: url, options: .atomic)
        }
        for name in (try? manager.contentsOfDirectory(atPath: directory.path)) ?? []
        where name.hasSuffix(".\(Self.fileExtension)") && !keep.contains(name) {
            try? manager.removeItem(at: directory.appendingPathComponent(name))
        }
    }

    // MARK: Documents

    /// The views in a document: one `.beadyview`, or a `.beadyviews` array. A document from a
    /// newer Beady, or one that isn't a view at all, is refused with a message worth showing.
    public static func views(fromDocument data: Data) throws -> [IssueView] {
        let object = try JSONSerialization.jsonObject(with: data)
        let decoder = JSONDecoder()
        if let array = object as? [[String: Any]] {
            return try array.map { try view(from: $0, decoder: decoder) }
        }
        guard let dictionary = object as? [String: Any] else { throw ViewImportError.notAView }
        return [try view(from: dictionary, decoder: decoder)]
    }

    private static func view(from json: [String: Any], decoder: JSONDecoder) throws -> IssueView {
        guard let version = json["beadyView"] as? Int else { throw ViewImportError.notAView }
        guard version <= IssueView.formatVersion else { throw ViewImportError.newerFormat(version) }
        let data = try JSONSerialization.data(withJSONObject: json)
        do {
            return try decoder.decode(IssueView.self, from: data)
        } catch {
            throw ViewImportError.notAView
        }
    }

    /// A `.beadyviews` document.
    public static func documentData(for views: [IssueView]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(views)
    }

    /// Adds views from a document as user views. A view whose id is already taken — by one of
    /// the user's own or by a built-in — gets a fresh id and a name that says it was imported,
    /// so importing never overwrites anything. Returns the views as added.
    @discardableResult
    public mutating func importViews(_ imported: [IssueView]) -> [IssueView] {
        var added: [IssueView] = []
        for var view in imported {
            view.isBuiltIn = false
            if self.view(view.id) != nil {
                view.id = IssueView.ID(UUID().uuidString)
                view.name += " (imported)"
            }
            views.append(view)
            added.append(view)
        }
        return added
    }

    /// Which built-in an older Beady's lifecycle scope lands on; nil for Open, which has no
    /// built-in (it is Everything with a Lifecycle chip).
    public static func builtIn(forScope scope: String) -> IssueView.ID? {
        switch scope {
        case "ready": .frontier
        case "inFlight": .inFlight
        case "blocked": .stuck
        case "deferred": .deferred
        case "closed": .landed
        case "all": .everything
        default: nil
        }
    }
}

struct SavedViewState: Codable, Sendable {
    let view: IssueView.ID
    let state: ViewState
}

public enum ViewImportError: Error, Equatable, LocalizedError {
    case notAView
    case newerFormat(Int)

    public var errorDescription: String? {
        switch self {
        case .notAView:
            "This file isn't a Beady view."
        case .newerFormat(let version):
            "This view was saved by a newer Beady (format \(version)); this Beady reads format \(IssueView.formatVersion). Update Beady to open it."
        }
    }
}

public extension IssueView {
    /// The view as a `.beadyview` document: the section-5 JSON, readable by eye.
    func documentData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    /// `Agent tiles.beadyview`, with the characters a file name can't carry replaced.
    var exportFilename: String {
        let safe = name.map { ["/", ":"].contains($0) ? "-" : $0 }
        return "\(String(safe)).\(ViewLibrary.fileExtension)"
    }
}

/// Reads the per-scope state an older Beady saved and lands it on the built-in views, so nothing
/// anyone set up is lost: each scope's remembered layout, grouping and ordering become the
/// matching built-in's presentation; any rules it carried become a modification on top of that
/// view's meaning; Open, which has no built-in, is offered as a user view.
enum ViewMigration {
    private struct Record: Decodable {
        let source: Source
        let state: State
    }

    /// `ViewSource` as Swift encoded it: `{"lifecycle": {"_0": "open"}}`.
    private enum Source: Decodable {
        case lifecycle(String)
        case focused(String)
        case label(String)

        private enum Keys: CodingKey { case lifecycle, focused, label }
        private enum Payload: CodingKey { case _0 }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: Keys.self)
            func value(_ key: Keys) throws -> String {
                try container.nestedContainer(keyedBy: Payload.self, forKey: key).decode(String.self, forKey: ._0)
            }
            if container.contains(.lifecycle) {
                self = .lifecycle(try value(.lifecycle))
            } else if container.contains(.focused) {
                self = .focused(try value(.focused))
            } else if container.contains(.label) {
                self = .label(try value(.label))
            } else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "not a view source"))
            }
        }
    }

    private struct State: Decodable {
        let filter: ViewFilter
        let layout: ViewLayout
        let grouping: IssueGrouping
        let ordering: IssueSort

        var presentation: ViewPresentation {
            ViewPresentation(layout: layout, grouping: grouping, ordering: ordering)
        }
    }

    static func migrate(_ data: Data) -> ViewLibrary? {
        guard let records = try? JSONDecoder().decode([Record].self, from: data) else { return nil }
        var library = ViewLibrary()
        for record in records {
            switch record.source {
            case .lifecycle("open"):
                // Open is Everything with a Lifecycle chip. Offered rather than imposed: a view
                // nobody asked for shouldn't appear in the sidebar on its own.
                var filter = record.state.filter
                filter.set(FilterRule(field: .lifecycle, op: .isAnyOf, values: [StatusCategory.active.rawValue]))
                library.offers.append(IssueView(
                    id: IssueView.ID(UUID().uuidString), name: "Open", symbol: "circle",
                    filter: filter, presentation: record.state.presentation
                ))
            case .lifecycle(let scope):
                if let id = ViewLibrary.builtIn(forScope: scope) { land(record.state, on: id, in: &library) }
            case .label(IssueMark.starred.label):
                land(record.state, on: .starred, in: &library)
            case .focused, .label:
                // Focus is a chip on a view now, and no other label ever had a view.
                continue
            }
        }
        return library
    }

    private static func land(_ state: State, on id: IssueView.ID, in library: inout ViewLibrary) {
        guard let index = library.index(of: id) else { return }
        library.views[index].presentation = state.presentation
        guard !state.filter.isEmpty else { return }
        // The rules it carried sit on top of what the view means, which wins where they clash.
        var filter = library.views[index].filter
        for rule in state.filter.rules where filter.rule(for: rule.field) == nil {
            filter.set(rule)
        }
        filter.searchText = state.filter.searchText
        library.live[id] = ViewState(filter: filter, presentation: state.presentation)
    }
}
