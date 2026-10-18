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
/// remembered presentation, then the user's own, in order), what is live on top of each, and
/// views an older Beady's saved state turned up that nobody has accepted or declined yet.
///
/// Lives in standard preferences for now; bdv-jlx.5 moves views to files.
public struct ViewLibrary: Equatable, Sendable {
    public var views: [IssueView]
    public var live: [IssueView.ID: ViewState]
    public var offers: [IssueView]

    public init(views: [IssueView] = IssueView.builtIns, live: [IssueView.ID: ViewState] = [:], offers: [IssueView] = []) {
        self.views = views
        self.live = live
        self.offers = offers
    }

    public func view(_ id: IssueView.ID) -> IssueView? {
        views.first { $0.id == id }
    }

    func index(of id: IssueView.ID) -> Int? {
        views.firstIndex { $0.id == id }
    }

    // MARK: Preferences

    static let viewsKey = "views"
    static let liveKey = "liveViews"
    static let offersKey = "offeredViews"
    /// Where Beady kept one state per lifecycle scope, before views were saved filters.
    static let legacyKey = "viewStates"

    /// Reads the library back. An older Beady's per-scope blob is migrated once and removed.
    /// Anything that can't be read is dropped rather than fought with: the library starts from
    /// the built-ins and is saved again on the next change.
    public static func load(from preferences: UserDefaults?) -> ViewLibrary {
        guard let preferences else { return ViewLibrary() }
        if let data = preferences.data(forKey: legacyKey) {
            let migrated = ViewMigration.migrate(data) ?? ViewLibrary()
            preferences.removeObject(forKey: legacyKey)
            migrated.save(to: preferences)
            return migrated
        }
        var library = ViewLibrary()
        let decoder = JSONDecoder()
        if let data = preferences.data(forKey: viewsKey), let saved = try? decoder.decode([IssueView].self, from: data) {
            library.views = merge(saved)
        }
        if let data = preferences.data(forKey: liveKey), let saved = try? decoder.decode([SavedViewState].self, from: data) {
            library.live = Dictionary(saved.map { ($0.view, $0.state) }, uniquingKeysWith: { first, _ in first })
        }
        if let data = preferences.data(forKey: offersKey), let saved = try? decoder.decode([IssueView].self, from: data) {
            library.offers = saved
        }
        return library
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

    public func save(to preferences: UserDefaults?) {
        guard let preferences else { return }
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(views) { preferences.set(data, forKey: Self.viewsKey) }
        // A dictionary keyed by a struct doesn't encode as a JSON object, so one record per view,
        // in a stable order.
        let live = live.map { SavedViewState(view: $0.key, state: $0.value) }.sorted { $0.view.rawValue < $1.view.rawValue }
        if let data = try? encoder.encode(live) { preferences.set(data, forKey: Self.liveKey) }
        if let data = try? encoder.encode(offers) { preferences.set(data, forKey: Self.offersKey) }
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
