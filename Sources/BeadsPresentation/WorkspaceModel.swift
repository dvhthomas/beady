import BeadsCore
import Foundation
import Observation

/// View state for one open beads workspace, modelled on Linear: the sidebar picks a view (a
/// saved filter with a saved presentation), and each view keeps its own filters, layout,
/// grouping and ordering. Loading, change-driven refresh and every write go through one
/// `BeadsStore`.
@MainActor
@Observable
public final class WorkspaceModel {
    public typealias Layout = ViewLayout

    public enum LoadState: Equatable, Sendable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    public let title: String
    public private(set) var snapshot: IssueSnapshot? {
        didSet { dataGeneration &+= 1 }
    }
    public private(set) var loadState: LoadState = .idle
    public private(set) var lastLoaded: Date?
    /// Set when a reload fails while older data is still on screen.
    public private(set) var refreshError: String?
    public private(set) var isLoading = false

    /// The last change this session wrote, until a view acknowledges it. Set after the write
    /// lands and the data reloads, so the acknowledgement plays on the refreshed board.
    public private(set) var lastAppliedChange: AppliedChange?

    /// The window's undo manager, handed in by the app layer. Every reversible write this
    /// session makes is registered here — the stack native macOS users already have, so ⌘Z and
    /// ⇧⌘Z walk it, the Edit menu names each step ("Undo Move bdv-1 to In Progress"), and a
    /// focused text field still gets its own typing undo first. Foundation's UndoManager, so
    /// the model stays AppKit-free and tests supply their own.
    @ObservationIgnored private weak var undoManager: UndoManager?

    /// The view picked in the sidebar.
    public var viewID: IssueView.ID = .frontier {
        didSet {
            recordPlace(view: oldValue, selection: selection)
            // Asking for a board that can't split is a decision about one view, now.
            explicitBoardView = nil
        }
    }

    /// The view on screen: the view as saved, with what's live on top.
    public var view: IssueView {
        var view = savedView
        let state = state
        view.filter = state.filter
        view.presentation = state.presentation
        return view
    }

    /// Every view the sidebar offers: the built-ins, then the user's own, in order.
    public var views: [IssueView] { library.views }

    /// The issue prefix bd uses in this database, read off its ids; nil before the first load
    /// or in an empty database. The switcher shows it next to the workspace's name.
    public var issuePrefix: String? {
        WorkspaceSwitching.prefix(of: snapshot?.issues.map(\.id) ?? [])
    }

    /// The current view as saved: a built-in's definition, or a user view as last saved. An id
    /// this Beady doesn't know falls back to the first built-in rather than showing nothing.
    private var savedView: IssueView {
        library.view(viewID) ?? library.views[0]
    }

    public var selection: IssueID? {
        didSet { recordPlace(view: viewID, selection: oldValue) }
    }
    /// Tree branches the user has folded; everything else is expanded.
    public private(set) var collapsed: Set<IssueID> = []

    public private(set) var pendingChange: PendingChange?
    /// What other sessions have been doing lately, so edits can warn about live work.
    public private(set) var activityLog: ActivityLog = .empty
    /// Newest first.
    public private(set) var activity: [ChangeRecord] = []
    /// True while a confirmed change is being written; the sheet is locked meanwhile.
    public private(set) var isWriting = false

    /// The saved views and what is live on top of each, written back on every change — but only
    /// the parts that changed: a search keystroke touches what's live, never the Library folder.
    private var library = ViewLibrary() {
        didSet { library.save(changedFrom: oldValue, to: viewsDirectory, preferences: preferences) }
    }

    @ObservationIgnored private let store: any BeadsStore
    /// Where what's live on each view is remembered between launches.
    /// Standard macOS preferences: ~/Library/Preferences/me.bitsby.beady.plist.
    @ObservationIgnored private let preferences: UserDefaults?
    /// The Library: one .beadyview per view. Nil keeps views in preferences.
    @ObservationIgnored private let viewsDirectory: URL?
    @ObservationIgnored private let allowsWriting: Bool
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private let staleAfter: TimeInterval
    @ObservationIgnored private var lastAttempt: (token: String, at: Date)?
    /// When we wrote each bead, so our own changes aren't read as another session's.
    @ObservationIgnored private var ownWrites: [IssueID: [Date]] = [:]
    /// One bead's one mark: what the user last clicked, what bd has confirmed, and whether a
    /// writer is currently draining the difference.
    struct MarkKey: Hashable, Sendable {
        let id: IssueID
        let mark: IssueMark
    }

    @ObservationIgnored private var desiredMarks: [MarkKey: Bool] = [:]
    @ObservationIgnored private var writtenMarks: [MarkKey: Bool] = [:]
    @ObservationIgnored private var markWriters: Set<MarkKey> = []
    private var back: [Place] = []
    private var forward: [Place] = []
    /// True while `goBack`/`goForward` are moving, so the move isn't recorded as a new step.
    @ObservationIgnored private var isTravelling = false
    @ObservationIgnored private let activityWindow: TimeInterval
    /// Where the journal has been read up to, when it's on.
    @ObservationIgnored private var journalFeed = JournalFeed()
    @ObservationIgnored private var journalChecked = false
    /// Whether this open has had its chance to turn the journal on; it gets one.
    @ObservationIgnored private var journalDecided = false
    @ObservationIgnored private let journalPolicy: JournalPolicy
    public init(
        title: String,
        store: any BeadsStore,
        allowsWriting: Bool = true,
        /// Nil keeps this model out of any saved state — which is what tests and the
        /// offscreen snapshots want. The app passes `.standard`.
        preferences: UserDefaults? = nil,
        /// The folder of .beadyview files; nil keeps views in preferences.
        viewsDirectory: URL? = nil,
        now: @escaping @Sendable () -> Date = { Date() },
        staleAfter: TimeInterval = 300,
        activityWindow: TimeInterval = 600,
        /// Whether to turn bd's change journal on when this workspace opens.
        journalPolicy: JournalPolicy = .manual,
        /// How often this workspace was left syncing by itself, and where to note a new choice.
        syncCadence: SyncCadence = .manual,
        noteSyncCadence: ((SyncCadence) -> Void)? = nil
    ) {
        self.autoSync = AutoSync(cadence: syncCadence)
        self.noteSyncCadence = noteSyncCadence
        self.title = title
        self.store = store
        self.allowsWriting = allowsWriting
        self.preferences = preferences
        self.viewsDirectory = viewsDirectory
        self.now = now
        self.staleAfter = staleAfter
        self.activityWindow = activityWindow
        self.journalPolicy = journalPolicy
        library = ViewLibrary.load(from: viewsDirectory, preferences: preferences)
    }

    /// Picks up views that changed on disk — a file dropped in, a sync, a hand edit. What's live
    /// here stays; the folder only ever says what's saved.
    public func reloadViews() {
        guard viewsDirectory != nil else { return }
        let onDisk = ViewLibrary.load(from: viewsDirectory, preferences: nil)
        if onDisk.views != library.views {
            library.views = onDisk.views
        }
    }

    /// Adds the views in a .beadyview or .beadyviews document under My Views and shows the last
    /// of them. Throws a readable error for a file that isn't a view or is from a newer Beady.
    @discardableResult
    public func importViews(fromDocument data: Data) throws -> [IssueView] {
        let added = library.importViews(try ViewLibrary.views(fromDocument: data))
        if let last = added.last { viewID = last.id }
        return added
    }

    /// A view as saved, as a .beadyview document; nil when there is no such view.
    public func exportDocument(for id: IssueView.ID) throws -> Data? {
        try library.view(id)?.documentData()
    }

    // MARK: Loading

    public func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        if snapshot == nil { loadState = .loading }

        // Taken before loading, so a write that lands mid-load still triggers the next refresh.
        lastAttempt = (await store.changeToken(), now())
        if !journalChecked {
            // bd's version decides whether there's a journal to follow; it won't change while
            // the workspace is open, so it's asked once.
            journal = await store.journalStatus()
            journalChecked = true
        }
        if let log = await readActivity(since: now().addingTimeInterval(-activityWindow)) {
            noteActivity(log)
        }
        await refreshBackupStatus()
        do {
            snapshot = try await store.loadSnapshot()
            reapplyDesiredMarks()
            reapplyOptimisticDrops()
            loadState = .loaded
            lastLoaded = now()
            refreshError = nil
        } catch {
            if snapshot == nil {
                loadState = .failed(error.localizedDescription)
            } else {
                refreshError = error.localizedDescription
            }
        }
        // After the snapshot: whether this window can write is only known once there is one.
        if !journalDecided, snapshot != nil {
            journalDecided = true
            if journalPolicy.shouldTurnOn(journal: journal, canEdit: canEdit) { await enableJournal() }
        }
    }

    /// Cheap to call often: reloads only when bd has written, or the data has gone stale.
    public func refreshIfChanged() async {
        guard let lastAttempt else { return await load() }
        let changed = await store.changeToken() != lastAttempt.token
        let stale = now().timeIntervalSince(lastAttempt.at) >= staleAfter
        if changed || stale { await load() }
    }

    // MARK: The current view's state

    /// What's live for the current view: the saved view until something changes.
    private var state: ViewState {
        get { library.live[viewID] ?? ViewState(of: savedView) }
        set { library.live[viewID] = newValue }
    }

    public var filter: ViewFilter {
        get { state.filter }
        set { state.filter = newValue }
    }

    /// The view's layout as remembered or chosen. What is drawn is `presentedLayout`.
    public var layout: Layout {
        get { state.presentation.layout }
        set { chooseLayout(newValue) }
    }

    /// The view the user asked to see as a board even though it has nothing to split, if any.
    /// Per view and per session: never saved, cleared when the view changes.
    private var explicitBoardView: IssueView.ID?

    /// Sets the layout as the user's choice: the switcher, ⌘1/2/3, the palette. Choosing Board
    /// shows the board even when it can't split.
    public func chooseLayout(_ layout: Layout) {
        present { $0.layout = layout }
        explicitBoardView = layout == .board ? viewID : nil
    }

    /// What is drawn. A view never opens on a board that can't split: Board stays its preference
    /// and nothing is written, but it presents as a list, grouping and ordering unchanged, until
    /// the data spreads out or the user asks for the board anyway.
    public var presentedLayout: Layout {
        if layout == .board, explicitBoardView != viewID, boardNeedsSplitting != nil { return .list }
        return layout
    }

    /// True while a Board preference is being shown as a list, for the switcher's help.
    public var isBoardShownAsList: Bool {
        layout == .board && presentedLayout == .list
    }

    /// Back from an explicitly chosen board that can't split to the list, keeping Board as the
    /// preference so the board returns on its own.
    public func showBoardAsList() {
        explicitBoardView = nil
    }

    public var grouping: IssueGrouping {
        get { state.presentation.grouping }
        set { present { $0.grouping = newValue } }
    }

    public var ordering: IssueSort {
        get { state.presentation.ordering }
        set { present { $0.ordering = newValue } }
    }

    /// A built-in remembers its presentation the moment it changes: flipping the layout is
    /// cheap and never a modification, because the filter is what the view means. A user view's
    /// presentation is part of what it saves, so the change waits for Save.
    private func present(_ change: (inout ViewPresentation) -> Void) {
        var presentation = state.presentation
        change(&presentation)
        state.presentation = presentation
        if savedView.isBuiltIn, let index = library.index(of: viewID) {
            library.views[index].presentation = presentation
        }
    }

    // MARK: Saving views

    /// Whether what's on screen differs from the view as saved. A built-in's presentation is
    /// always remembered, so only its filter can be modified; a user view's layout counts too.
    public var isModified: Bool {
        state != ViewState(of: savedView)
    }

    /// Whether Save would do anything: a modified user view. A built-in is never saved over.
    public var canSave: Bool {
        !savedView.isBuiltIn && isModified
    }

    /// Saves what's on screen into the current user view. Refused for a built-in, whose filter is
    /// its definition: Save as new view is the way to keep a variation of one.
    @discardableResult
    public func save() -> Bool {
        guard !savedView.isBuiltIn, let index = library.index(of: viewID) else { return false }
        library.views[index].filter = state.filter
        library.views[index].presentation = state.presentation
        library.live[viewID] = nil
        return true
    }

    /// A new user view from what's on screen, which becomes the current view. The view you came
    /// from goes back to how it was saved.
    @discardableResult
    public func saveAsNewView(name: String, symbol: String = ViewIcon.defaultUserChoice) -> IssueView {
        let symbol = symbol.trimmingCharacters(in: .whitespaces)
        let view = IssueView(
            id: IssueView.ID(UUID().uuidString), name: name, symbol: symbol.isEmpty ? ViewIcon.defaultUserChoice : symbol,
            filter: state.filter, presentation: state.presentation
        )
        library.live[viewID] = nil
        library.views.append(view)
        viewID = view.id
        return view
    }

    /// Back to the view as saved.
    public func reset() {
        library.live[viewID] = nil
    }

    /// Gives a user view an icon (an SF Symbol name). Refused for a built-in, whose icon is part
    /// of what it is, and for a blank name, which would draw nothing.
    @discardableResult
    public func setIcon(_ symbol: String, for id: IssueView.ID) -> Bool {
        let symbol = symbol.trimmingCharacters(in: .whitespaces)
        guard !symbol.isEmpty, let index = library.index(of: id), !library.views[index].isBuiltIn else { return false }
        library.views[index].symbol = symbol
        return true
    }

    /// Renames a user view. Refused for a built-in, and for a blank name.
    @discardableResult
    public func renameView(_ id: IssueView.ID, to name: String) -> Bool {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let index = library.index(of: id), !library.views[index].isBuiltIn else { return false }
        library.views[index].name = name
        return true
    }

    /// A user view copied from a view as saved, named after it, keeping its filter, presentation
    /// and icon. Duplicating a built-in is the one way to change what it means: the copy is
    /// unlocked, under My Views. Nil when there is no such view.
    @discardableResult
    public func duplicateView(_ id: IssueView.ID) -> IssueView? {
        guard let source = library.view(id) else { return nil }
        var copy = source
        copy.id = IssueView.ID(UUID().uuidString)
        copy.name = String(localized: "\(source.name) copy", bundle: .module, comment: "Name of a duplicated view")
        copy.isBuiltIn = false
        library.views.append(copy)
        return copy
    }

    /// Removes a user view; the built-ins stay. Returns whether anything was removed.
    @discardableResult
    public func removeView(_ id: IssueView.ID) -> Bool {
        guard let index = library.index(of: id), !library.views[index].isBuiltIn else { return false }
        library.views.remove(at: index)
        library.live[id] = nil
        if viewID == id { viewID = library.views[0].id }
        return true
    }

    /// Views an older Beady's saved state turned up that have no built-in to land on (Open),
    /// each kept until it is accepted into the sidebar or declined.
    public var offeredViews: [IssueView] { library.offers }

    public func acceptOfferedView(_ id: IssueView.ID) {
        guard let index = library.offers.firstIndex(where: { $0.id == id }) else { return }
        let view = library.offers.remove(at: index)
        library.views.append(view)
        viewID = view.id
    }

    public func declineOfferedView(_ id: IssueView.ID) {
        library.offers.removeAll { $0.id == id }
    }

    public var searchText: String {
        get { state.filter.searchText }
        set { state.filter.searchText = newValue }
    }

    public var viewTitle: String { view.name }

    // MARK: What the view shows

    /// One body pass reads the filtered list many times over — the subtitle count, the board,
    /// the split check, the tree — so each derived value below remembers its last answer and
    /// the inputs it came from. A key carries everything the value derives from (the snapshot
    /// by generation, the live filter, the ordering…), so a stale entry simply never matches.
    /// Time-window rules re-evaluate with the next load rather than on every read, which the
    /// staleness reload bounds at a few minutes.
    @ObservationIgnored private var dataGeneration = 0

    private struct VisibleKey: Equatable {
        let generation: Int
        let filter: ViewFilter
        let ordering: IssueSort
    }

    @ObservationIgnored private var visibleCache: (key: VisibleKey, issues: [Issue])?
    @ObservationIgnored private var treeCache: (key: VisibleKey, tree: [IssueTreeNode])?

    private struct BoardKey: Equatable {
        let generation: Int
        let filter: ViewFilter
        let ordering: IssueSort
        let grouping: IssueGrouping
        let canEdit: Bool
    }

    @ObservationIgnored private var boardGroupsCache: (key: BoardKey, groups: [IssueGroupModel])?
    @ObservationIgnored private var boardColumnsCache: (key: BoardKey, nests: Bool, columns: [BoardColumnModel])?
    @ObservationIgnored private var boardSplitCache: (key: BoardKey, split: BoardSplit?)?

    private var visibleKey: VisibleKey {
        VisibleKey(generation: dataGeneration, filter: filter, ordering: ordering)
    }

    private var boardKey: BoardKey {
        BoardKey(generation: dataGeneration, filter: filter, ordering: ordering, grouping: boardGrouping, canEdit: canEdit)
    }

    public var visibleIssues: [Issue] {
        guard let snapshot else { return [] }
        let key = visibleKey
        if let cached = visibleCache, cached.key == key { return cached.issues }
        let now = now()
        let filter = key.filter
        let issues = ordering.sorted(
            snapshot.issues.filter { filter.matches($0, in: snapshot, now: now) },
            // A pin is a request to see something first, wherever it appears.
            pinnedFirst: true
        )
        visibleCache = (key, issues)
        return issues
    }

    public var groups: [IssueGroupModel] {
        makeGroups(grouping, including: [])
    }

    /// Board columns. A board needs columns, so no grouping means lifecycle columns. While editing,
    /// every value a card could be dropped into has a column, even when empty.
    public var boardGroups: [IssueGroupModel] {
        let key = boardKey
        if let cached = boardGroupsCache, cached.key == key { return cached.groups }
        let groups = makeGroups(key.grouping, including: key.canEdit ? dropKeys(for: key.grouping) : [])
        boardGroupsCache = (key, groups)
        return groups
    }

    /// The board's per-view option: fold sub-tasks into their parent's card. Reads off under
    /// parent grouping, where the columns are the parents already.
    public var nestsSubtasks: Bool {
        get { boardGrouping != .parent && (state.presentation.nestsSubtasks ?? false) }
        // Nil rather than false keeps the field out of files that never turned it on.
        set { present { $0.nestsSubtasks = newValue ? true : nil } }
    }

    /// What the board actually draws: `boardGroups` with nesting applied.
    public var boardColumns: [BoardColumnModel] {
        guard let snapshot else { return [] }
        let key = boardKey
        let nests = nestsSubtasks
        if let cached = boardColumnsCache, cached.key == key, cached.nests == nests { return cached.columns }
        let columns = BoardNesting.columns(from: boardGroups, in: snapshot, nesting: nests)
        boardColumnsCache = (key, nests, columns)
        return columns
    }

    /// Cards expanded to show their folded children. This session's, like `collapsed`, but its
    /// own set: the tree starts expanded, cards start collapsed.
    public private(set) var boardExpanded: Set<IssueID> = []

    public func toggleBoardCard(_ id: IssueID) {
        if !boardExpanded.insert(id).inserted { boardExpanded.remove(id) }
    }

    /// What would split a board that has collapsed to one column. Nil when the board already has
    /// more than one column with cards in it, when this isn't a board, or when there is nothing
    /// to split (one card or none). Groupings are offered only if they would actually spread the
    /// cards out, so the board never silently shows one column again.
    public var boardNeedsSplitting: BoardSplit? {
        guard layout == .board, let snapshot else { return nil }
        let key = boardKey
        if let cached = boardSplitCache, cached.key == key { return cached.split }
        let split: BoardSplit?
        let issues = visibleIssues
        if issues.count > 1, boardGroups.filter({ !$0.issues.isEmpty }).count <= 1 {
            let candidates: [IssueGrouping] = [.status, .priority, .assignee, .parent]
            split = BoardSplit(groupings: candidates.filter { $0 != key.grouping && $0.groups(issues, in: snapshot).count > 1 })
        } else {
            split = nil
        }
        boardSplitCache = (key, split)
        return split
    }

    public struct BoardSplit: Equatable, Sendable {
        /// Groupings that would give the board more than one column, in the order to offer them.
        public let groupings: [IssueGrouping]
    }

    public var tree: [IssueTreeNode] {
        guard let snapshot else { return [] }
        let key = visibleKey
        if let cached = treeCache, cached.key == key { return cached.tree }
        let tree = IssueTree.build(matches: visibleIssues, in: snapshot)
        treeCache = (key, tree)
        return tree
    }

    /// Resolved from the whole snapshot, so following a link to a filtered-out issue still works.
    public var selectedIssue: Issue? {
        selection.flatMap { snapshot?.issue($0) }
    }

    private var boardGrouping: IssueGrouping {
        grouping == .none ? .category : grouping
    }

    private func dropKeys(for grouping: IssueGrouping) -> [String] {
        let categories = filter.lifecycleCategories
        switch grouping {
        case .category:
            return StatusCategory.allCases.filter(categories.contains).map(\.rawValue)
        case .status:
            let catalog = snapshot?.catalog ?? .builtIn
            return ["open", "in_progress", "blocked", "deferred", "closed"].filter { categories.contains(catalog.category(of: $0)) }
        case .priority:
            return (0...4).map(String.init)
        case .none, .type, .assignee, .parent:
            return []
        }
    }

    private func makeGroups(_ grouping: IssueGrouping, including keys: [String]) -> [IssueGroupModel] {
        guard let snapshot else { return [] }
        return grouping.groups(visibleIssues, in: snapshot, including: keys).map {
            IssueGroupModel(
                key: $0.key,
                title: groupTitle($0.key, grouping: grouping),
                issues: $0.issues,
                // Only a group that *is* a bead has progress of its own.
                completion: grouping == .parent && !$0.key.isEmpty ? snapshot.progress(of: IssueID($0.key)) : nil
            )
        }
    }

    private func groupTitle(_ key: String, grouping: IssueGrouping) -> String {
        switch grouping {
        case .none: return ""
        case .category: return StatusCategory(rawValue: key).map(DisplayText.category) ?? key
        case .status: return DisplayText.status(key)
        case .priority: return Int(key).map(DisplayText.priority) ?? key
        case .type: return key.prefix(1).uppercased() + key.dropFirst()
        case .assignee: return key.isEmpty ? String(localized: "Unassigned", bundle: .module, comment: "Group header for beads with no assignee") : key
        case .parent: return key.isEmpty ? String(localized: "No parent", bundle: .module, comment: "Group header for top-level beads") : (snapshot?.issue(IssueID(key))?.title ?? key)
        }
    }

    // MARK: Filters

    /// A built-in's own rules are its definition and can't be edited in place: duplicate the view
    /// instead. Nothing on a user view is locked. A rule that somehow differs from the
    /// definition (an older saved state) isn't locked either, so it can be put right.
    public var lockedFields: Set<FilterField> {
        guard savedView.isBuiltIn else { return [] }
        return Set(savedView.filter.rules.filter { $0 == filter.rule(for: $0.field) }.map(\.field))
    }

    public func isLocked(_ field: FilterField) -> Bool {
        lockedFields.contains(field)
    }

    /// Whether Clear would do anything: rules added on top of what the view means.
    public var hasClearableFilters: Bool {
        filter.rules.contains { !isLocked($0.field) }
    }

    public func toggleFilterValue(_ value: String, in field: FilterField) {
        guard !isLocked(field) else { return }
        filter.toggle(value, in: field)
    }

    public func setFilterOperator(_ op: FilterOperator, for field: FilterField) {
        guard !isLocked(field) else { return }
        filter.setOperator(op, for: field)
    }

    public func removeFilter(_ field: FilterField) {
        guard !isLocked(field) else { return }
        filter.remove(field)
    }

    /// Removes the rules added on top of this view; a built-in's own rules stay, and other views
    /// keep theirs.
    public func clearFilters() {
        for field in filter.rules.map(\.field) where !isLocked(field) {
            filter.remove(field)
        }
    }

    public func filterOptions(for field: FilterField) -> [FilterMenuOption] {
        guard let snapshot else { return [] }
        return FilterOptions.options(for: field, filter: filter, in: snapshot, now: now()).map {
            FilterMenuOption(
                value: $0.value,
                title: valueTitle($0.value, field: field),
                count: $0.count,
                isSelected: $0.isSelected,
                help: DisplayText.help(forValue: $0.value, in: field, catalog: snapshot.catalog)
            )
        }
    }

    /// Every rule but the focus, which the breadcrumb shows instead.
    public var filterChips: [FilterChipModel] {
        let locked = lockedFields
        return filter.rules.filter { Self.focusedID(of: $0) == nil }.map { rule in
            let titles = sortedValues(rule).map { valueTitle($0, field: rule.field) }
            let values = titles.count > 2 ? "\(titles.count) \(DisplayText.noun(rule.field))" : titles.joined(separator: ", ")
            return FilterChipModel(
                field: rule.field,
                fieldTitle: DisplayText.field(rule.field),
                operatorTitle: DisplayText.operatorTitle(rule.op, valueCount: rule.values.count, field: rule.field),
                valuesTitle: rule.field == .blocked ? "" : values,
                operators: rule.field.operators.map {
                    OperatorChoice(op: $0, title: DisplayText.operatorTitle($0, valueCount: 2, field: rule.field), isSelected: $0 == rule.op)
                },
                isLocked: locked.contains(rule.field),
                fieldHelp: DisplayText.help(for: rule.field),
                valuesHelp: rule.values.count == 1
                    ? rule.values.first.flatMap { DisplayText.help(forValue: $0, in: rule.field, catalog: snapshot?.catalog ?? .builtIn) }
                    : nil
            )
        }
    }

    private func valueTitle(_ raw: String, field: FilterField) -> String {
        switch field {
        case .lifecycle: StatusCategory(rawValue: raw).map(DisplayText.lifecycle) ?? raw
        case .status: DisplayText.status(raw)
        case .priority: Int(raw).map(DisplayText.priority) ?? raw
        case .assignee: raw.isEmpty ? String(localized: "Unassigned", bundle: .module, comment: "Filter value for beads with no assignee") : raw
        case .blocked: String(localized: "Blocked", bundle: .module, comment: "Filter value")
        case .ready: raw == FilterRule.readyValue ? String(localized: "yes", bundle: .module, comment: "Filter value for Ready: ‘Ready · is · yes’") : raw
        case .parent: snapshot?.issue(IssueID(raw))?.title ?? raw
        case .updated, .closed: TimeWindow(rawValue: raw).map(DisplayText.window) ?? raw
        case .type, .labels: raw
        }
    }

    private func sortedValues(_ rule: FilterRule) -> [String] {
        switch rule.field {
        case .priority:
            return rule.values.sorted { (Int($0) ?? .max) < (Int($1) ?? .max) }
        case .lifecycle:
            let order = { (raw: String) in StatusCategory(rawValue: raw).flatMap(StatusCategory.allCases.firstIndex) ?? .max }
            return rule.values.sorted { order($0) < order($1) }
        case .status:
            let catalog = snapshot?.catalog ?? .builtIn
            let order = { (status: String) in StatusCategory.allCases.firstIndex(of: catalog.category(of: status)) ?? 0 }
            return rule.values.sorted { (order($0), $0) < (order($1), $1) }
        default:
            return rule.values.sorted {
                valueTitle($0, field: rule.field).localizedStandardCompare(valueTitle($1, field: rule.field)) == .orderedAscending
            }
        }
    }

    // MARK: Sidebar

    /// Every row, in sidebar order: the sections flattened.
    public var sidebarViews: [SidebarEntry] {
        sidebarSections.flatMap(\.entries)
    }

    /// Views (the built-ins), My Views (the user's own, with a + to add one, even when empty),
    /// and Starred once something is starred.
    public var sidebarSections: [SidebarSection] {
        let builtIns = library.views.filter { $0.isBuiltIn && $0.id != .starred }
        let mine = library.views.filter { !$0.isBuiltIn }
        var sections = [
            SidebarSection(kind: .views, title: String(localized: "Views", bundle: .module, comment: "Sidebar section: the built-in views"), entries: builtIns.map(sidebarEntry), canAdd: false),
            SidebarSection(kind: .mine, title: String(localized: "My Views", bundle: .module, comment: "Sidebar section: the user's own views"), entries: mine.map(sidebarEntry), canAdd: true),
        ]
        if let starred = library.view(.starred), total(in: starred) > 0 {
            sections.append(SidebarSection(kind: .starred, title: "", entries: [sidebarEntry(starred)], canAdd: false))
        }
        return sections
    }

    private func sidebarEntry(_ view: IssueView) -> SidebarEntry {
        let live = library.live[view.id]
        return SidebarEntry(
            id: view.id,
            title: view.name,
            symbol: view.symbol,
            layout: (live?.presentation ?? view.presentation).layout,
            count: total(in: view),
            isModified: live.map { $0 != ViewState(of: view) } ?? false,
            isBuiltIn: view.isBuiltIn,
            help: DisplayText.help(forView: view.id)
        )
    }

    // MARK: Moving around the board

    public enum MoveDirection: Sendable {
        case up, down, left, right
    }

    /// Moves the highlight around the board. The list and the tree are real AppKit lists and
    /// handle their own arrows; the board is a grid of columns we drew ourselves, so it needs
    /// this — otherwise the arrows wander off into the sidebar.
    public func moveSelection(_ direction: MoveDirection) {
        guard layout == .board else { return }
        let columns = boardColumns.filter { !$0.cards.isEmpty }
        guard !columns.isEmpty else { return }
        // Each column flattened to what can be landed on: cards, and the children of expanded
        // cards, in drawn order.
        let rows = columns.map { BoardNesting.selectableIDs(in: $0, expanded: boardExpanded) }

        // Where an id stands. A selected child inside a collapsed card stands where its card
        // does, so the arrows always have somewhere to start from.
        func place(of id: IssueID) -> (column: Int, row: Int)? {
            for (column, ids) in rows.enumerated() {
                if let row = ids.firstIndex(of: id) { return (column, row) }
            }
            for (column, list) in columns.enumerated() {
                if let card = list.cards.first(where: { $0.children.contains { $0.id == id } }),
                   let row = rows[column].firstIndex(of: card.id) { return (column, row) }
            }
            return nil
        }

        guard let selection, let (column, row) = place(of: selection) else {
            // Nothing selected yet: start at the top of the first column with anything in it.
            self.selection = rows.first?.first
            return
        }

        switch direction {
        case .up:
            self.selection = rows[column][max(row - 1, 0)]
        case .down:
            self.selection = rows[column][min(row + 1, rows[column].count - 1)]
        case .left, .right:
            let next = direction == .left ? column - 1 : column + 1
            guard rows.indices.contains(next) else { return }
            // Keep your place down the column, or land on the last row of a shorter one.
            self.selection = rows[next][min(row, rows[next].count - 1)]
        }
    }

    // MARK: Where you've been

    /// A view and the bead that was selected in it — one step of history.
    public struct Place: Equatable, Sendable {
        public let view: IssueView.ID
        public let selection: IssueID?
    }

    /// Far more than anyone steps back through, and small enough to ignore.
    public static let maxHistory = 100

    public var canGoBack: Bool { !back.isEmpty }
    public var canGoForward: Bool { !forward.isEmpty }
    /// For tests: how many steps are remembered in total.
    public var historyDepth: Int { back.count + forward.count }

    /// Back to the bead and view you came from — following a blocker link and returning is the
    /// case this exists for.
    public func goBack() {
        guard let destination = back.popLast() else { return }
        forward.append(Place(view: viewID, selection: selection))
        travel(to: destination)
    }

    public func goForward() {
        guard let destination = forward.popLast() else { return }
        back.append(Place(view: viewID, selection: selection))
        travel(to: destination)
    }

    private func travel(to place: Place) {
        isTravelling = true
        viewID = place.view
        selection = place.selection
        isTravelling = false
    }

    /// Remembers where you just were, unless you were already there or we're the ones moving.
    private func recordPlace(view: IssueView.ID, selection: IssueID?) {
        guard !isTravelling else { return }
        let previous = Place(view: view, selection: selection)
        guard previous != Place(view: viewID, selection: self.selection) else { return }
        guard back.last != previous else { return }
        back.append(previous)
        if back.count > Self.maxHistory { back.removeFirst(back.count - Self.maxHistory) }
        // Going somewhere new abandons whatever was ahead, as a browser does.
        forward.removeAll()
    }

    // MARK: Backup

    /// Where this database is backed up, refreshed with each load. bd does the work; the app
    /// only reports it and asks for it.
    public private(set) var backup: BackupStatus = .none
    /// True while a backup is running, so the indicator can say so.
    public private(set) var isBackingUp = false

    public func refreshBackupStatus() async {
        backup = (try? await store.backupStatus()) ?? .none
    }

    /// Runs bd's backup now. Returns the failure, if any, for the caller to show.
    @discardableResult
    public func backUpNow() async -> String? {
        guard !isBackingUp, backup.isConfigured else { return nil }
        isBackingUp = true
        defer { isBackingUp = false }
        do {
            try await store.syncBackup()
            await refreshBackupStatus()
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    /// Points bd at a folder and takes the first backup.
    @discardableResult
    public func startBackingUp(to folder: String) async -> String? {
        guard !isBackingUp else { return nil }
        isBackingUp = true
        defer { isBackingUp = false }
        do {
            try await store.configureBackup(folder: folder)
            await refreshBackupStatus()
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    /// One phrase for the window's subtitle: the whole backup UI, as agreed.
    public var backupSummary: String? {
        if isBackingUp { return String(localized: "backing up…", bundle: .module, comment: "Toolbar backup status") }
        guard backup.isConfigured else { return String(localized: "not backed up", bundle: .module, comment: "Toolbar backup status") }
        guard let last = backup.lastSync else { return String(localized: "backup set up, not run yet", bundle: .module, comment: "Toolbar backup status") }
        return String(localized: "backed up \(ChangeDescriber.ago(last, from: now()))", bundle: .module, comment: "Toolbar backup status; the value is a relative time such as ‘6 minutes ago’")
    }

    // MARK: Sharing

    /// What bd reports about sharing (plan 0006). Nil until first read, and when bd wouldn't say,
    /// in which case the app shows nothing rather than guess.
    public private(set) var sharing: SharingFacts?
    /// The last sync this session. A halted merge leaves nothing for bd to report afterwards,
    /// so this is how a conflict stays on screen until it is settled.
    public private(set) var lastSync: SyncOutcome?
    /// What is running: a sync, which can be stopped, or a share or a settlement, which can't.
    public private(set) var sharingActivity: SharingActivity = .idle
    /// True while a sync, a share or a conflict settlement is running.
    public var isSyncing: Bool { sharingActivity != .idle }
    /// The sync timer: its cadence, and what the last sync means for the next tick (plan 0007).
    public private(set) var autoSync: AutoSync
    /// The running `bd sync`, so Stop has something to cancel.
    @ObservationIgnored private var syncTask: Task<SyncOutcome, Error>?
    @ObservationIgnored private let noteSyncCadence: ((SyncCadence) -> Void)?
    /// What the last sharing action has to say that the status doesn't: a failure in bd's words.
    public private(set) var sharingNotice: String?
    /// The checkouts, hooks and storage bd reports, for the Workspace Setup sheet.
    public private(set) var setup: WorkspaceSetup = .unknown
    /// The repository's git origin, the Share Beads sheet's starting point.
    public private(set) var gitOrigin: String?

    public var sharingState: SharingState? {
        sharing.map { SharingState.derive($0, lastSync: lastSync) }
    }

    public var sharingSummary: SharingSummary? {
        sharingState?.summary(activity: sharingActivity)
    }

    /// How often this workspace syncs by itself. This Mac's choice: it is kept in Beady's
    /// preferences by whoever opened the model, and changes nothing in bd's configuration.
    public var syncCadence: SyncCadence {
        get { autoSync.cadence }
        set {
            guard newValue != autoSync.cadence else { return }
            autoSync.choose(newValue)
            noteSyncCadence?(newValue)
        }
    }

    /// The line under the cadence choice.
    public var autoSyncCaption: String {
        autoSync.caption(remote: sharingState?.remote)
    }

    /// Asks bd where the database is shared and how it stands against that remote. This is the
    /// one read that goes to the network, so it runs when a workspace opens, after each sharing
    /// action and when asked, not with every reload.
    public func refreshSharing() async {
        sharing = try? await store.sharingFacts()
    }

    /// Reads what the Workspace Setup and Share Beads sheets show besides sharing itself.
    public func refreshSetup() async {
        setup = await store.workspaceSetup()
        gitOrigin = await store.gitOriginURL()
    }

    /// False for the one notice that isn't a complaint: the word that a sync was stopped.
    public var sharingNoticeIsFailure: Bool {
        sharingNotice != SyncOutcome.stopped.notice
    }

    public func dismissSharingNotice() {
        sharingNotice = nil
    }

    /// One `bd sync`: pull, check, push. Nothing is retried here; bd does its own bounded
    /// retrying, and a second press is the user's to make.
    public func syncNow() async {
        await runSync(automatic: false)
    }

    /// Asks bd to stop the sync that is running. bd is sent the signal Ctrl-C sends, finishes
    /// what it is writing and exits; `syncNow` then reads how things stand. Only a sync can be
    /// stopped: a share and a settlement run to the end.
    public func stopSync() {
        guard sharingActivity == .syncing else { return }
        sharingActivity = .stopping
        syncTask?.cancel()
    }

    /// Called every few seconds while the window is open. Runs one sync when the timer's rules
    /// say one is due, and otherwise does nothing.
    public func autoSyncTick() async {
        let isBusy = isSyncing || isWriting || isBackingUp
        guard autoSync.isDue(at: now(), state: sharingState, isBusy: isBusy, canWrite: allowsWriting) else { return }
        await runSync(automatic: true)
    }

    private func runSync(automatic: Bool) async {
        guard allowsWriting, !isSyncing else { return }
        sharingActivity = .syncing
        if !automatic { sharingNotice = nil }
        let remote = sharing?.remote?.name ?? SharePlan.remoteName

        // Its own task, so Stop cancels the sync and not whoever asked for it.
        let task = Task { [store] in try await store.sync() }
        syncTask = task
        let answer: Result<SyncOutcome, Error>
        do { answer = .success(try await task.value) } catch { answer = .failure(error) }
        syncTask = nil
        let stopRequested = sharingActivity == .stopping

        let outcome: SyncOutcome
        var thrown: Error?
        switch answer {
        case .success(let reported):
            outcome = reported.afterStop(requested: stopRequested)
        case .failure(let error):
            outcome = stopRequested ? .stopped : .failed(error.localizedDescription)
            if !stopRequested { thrown = error }
        }
        lastSync = outcome
        let shown = autoSync.record(outcome, at: now(), automatic: automatic) == .show
        if shown {
            sharingNotice = thrown?.localizedDescription ?? outcome.notice
        } else if outcome == .synced {
            // A good sync answers whatever an earlier one complained of.
            sharingNotice = nil
        }

        // The Changes menu lists what a person did and what they need to know: a quiet tick is
        // neither, and a stop is not a failure.
        let failedSummary = String(localized: "Sync with \(remote)", bundle: .module, comment: "Changes menu entry for a sync that failed; the remote's name")
        switch outcome {
        case .synced:
            if !automatic {
                record(summary: String(localized: "Synced with \(remote)", bundle: .module, comment: "Changes menu entry; the remote's name"))
            }
        case .conflict:
            record(summary: String(localized: "Sync with \(remote) stopped on a conflict", bundle: .module, comment: "Changes menu entry; the remote's name"), error: SharingFailure(message: String(localized: "Nothing was sent and nothing here was lost.", bundle: .module)))
        case .busy, .stuck, .unrelated, .failed:
            if shown {
                record(summary: failedSummary, error: thrown ?? SharingFailure(message: outcome.notice ?? ""))
            }
        case .noRemote, .localOnly, .stopped:
            break
        }
        sharingActivity = .idle
        await afterSharingAction()
    }

    /// What Share Beads would do for the URL in its field.
    public func sharePlan(url: String, audience: ShareAudience) -> SharePlan {
        SharePlan.make(facts: sharing ?? .none, gitOrigin: gitOrigin, url: url, audience: audience)
    }

    /// The exact commands a plan runs.
    public func commands(for plan: SharePlan) -> [String] {
        plan.steps.map(store.commandPreview(for:))
    }

    /// The exact command behind a sharing action, for showing before it runs.
    public func command(for action: SharingAction) -> String? {
        switch action {
        case .sync: store.commandPreview(for: .sync)
        case .settleConflict(let side): store.commandPreview(for: .settleConflict(keeping: side))
        case .share, .checkAgain, .stop: nil
        }
    }

    /// Runs a share plan, a step at a time, stopping at the first that fails. Returns whether it
    /// all went through; a failure is in `sharingNotice`, in bd's words.
    @discardableResult
    public func share(_ plan: SharePlan) async -> Bool {
        guard allowsWriting, !isSyncing, plan.canShare else { return false }
        sharingActivity = .working
        defer { sharingActivity = .idle }
        sharingNotice = nil
        let summary = String(localized: "Shared beads with \(plan.destination)", bundle: .module, comment: "Changes menu entry; the remote's URL")
        do {
            for step in plan.steps { try await store.perform(step) }
            lastSync = nil
            record(summary: summary)
            await afterSharingAction()
            return true
        } catch {
            let message = error.localizedDescription
            if SyncOutcome.isUnrelatedHistory(message) { lastSync = .unrelated(message) }
            sharingNotice = message
            record(summary: String(localized: "Share beads with \(plan.destination)", bundle: .module, comment: "Changes menu entry for a share that failed; the remote's URL"), error: error)
            // A remote that was added before the failure is real; show it.
            await afterSharingAction()
            return false
        }
    }

    /// Settles a conflict for one side, then publishes the result. Only where bd offers it:
    /// embedded storage (`SharingState.conflict(_, canChooseSide:)`).
    public func settleConflict(keeping side: ConflictSide) async {
        guard allowsWriting, !isSyncing, case .conflict(let remote, true) = sharingState else { return }
        sharingActivity = .working
        sharingNotice = nil
        do {
            try await store.perform(.settleConflict(keeping: side))
            lastSync = nil
            record(summary: side == .mine
                ? String(localized: "Settled the conflict with \(remote.name), keeping this Mac's beads", bundle: .module, comment: "Changes menu entry; the remote's name")
                : String(localized: "Settled the conflict with \(remote.name), taking its beads", bundle: .module, comment: "Changes menu entry; the remote's name"))
        } catch {
            sharingNotice = error.localizedDescription
            record(summary: String(localized: "Settle the conflict with \(remote.name)", bundle: .module, comment: "Changes menu entry for a settlement that failed; the remote's name"), error: error)
            sharingActivity = .idle
            await afterSharingAction()
            return
        }
        sharingActivity = .idle
        // The pull merged; the push is what tells the remote.
        await syncNow()
    }

    /// A sharing action may have brought beads in, and has changed how this database stands.
    private func afterSharingAction() async {
        await refreshSharing()
        await load()
    }

    // MARK: Editing a bead

    /// What's being edited right now, if anything. It lives here rather than in the form's own
    /// state so a reload can't quietly replace what someone is typing — and so the values are
    /// observable, which view-local storage under Command Line Tools has proved not to be.
    public var draft: EditDraft?

    public func beginEditing(_ id: IssueID) {
        guard canEdit else { return }
        draft = editDraft(for: id)
    }

    public func endEditing() {
        draft = nil
    }

    /// Hands the draft to the confirmation sheet, which stays the only way to write.
    public func reviewDraft() {
        guard let draft, let change = draft.change else { return }
        propose(change, basedOn: draft.original)
    }

    /// A draft of one bead, for the edit form. Nil when the bead isn't in this snapshot.
    public func editDraft(for id: IssueID) -> EditDraft? {
        snapshot?.issue(id).map(EditDraft.init)
    }

    /// The people already working in this database, for suggesting an assignee.
    public var knownAssignees: [String] {
        guard let snapshot else { return [] }
        return snapshot.assignees.sorted()
    }

    /// Labels already in use, so a form offers them rather than inviting typos.
    public var knownLabels: [String] {
        guard let snapshot else { return [] }
        return snapshot.labels.sorted()
    }

    /// bd's built-in types plus whatever this database has taken to using.
    public var knownTypes: [String] {
        ChangeValidator.coreTypes.union(snapshot?.types ?? []).sorted()
    }

    /// Statuses from `bd statuses`, so custom ones appear without the app knowing about them.
    public var knownStatuses: [String] {
        snapshot?.catalog.names ?? []
    }

    // MARK: Pins and stars

    /// Adds or removes the bd label behind a mark.
    ///
    /// The label is applied to the loaded snapshot straight away and written afterwards: a bd
    /// write costs the best part of a second (process start, then Dolt), and waiting for it made
    /// a pin feel broken. Clicking again while a write is in the air is never dropped — the
    /// latest click is what the app shows and what bd ends up with — and a wobble that lands back
    /// where it started needs no second write. A failure puts the mark back and says why.
    ///
    /// Marks are reversible metadata, so showing one early can't lose anyone's work; edits keep
    /// the confirmation sheet.
    public func toggleMark(_ mark: IssueMark, on id: IssueID) async {
        guard canEdit, let loaded = snapshot, let issue = loaded.issue(id) else { return }
        let key = MarkKey(id: id, mark: mark)
        let alreadyWriting = markWriters.contains(key)
        // With no write in flight, the loaded snapshot is the truth about what bd holds.
        if !alreadyWriting { writtenMarks[key] = issue.has(mark) }

        let wanted = !(desiredMarks[key] ?? issue.has(mark))
        desiredMarks[key] = wanted
        setMarkLocally(mark, on: wanted, for: id)

        // A writer is already draining this bead's mark; it will pick the new intent up.
        guard !alreadyWriting else { return }
        markWriters.insert(key)
        defer {
            markWriters.remove(key)
            desiredMarks[key] = nil
        }

        while let target = desiredMarks[key], target != writtenMarks[key] {
            guard let base = baseIssue(id, mark: mark, at: writtenMarks[key] ?? false) else { break }
            let change = IssueChange.setMark(id, mark, on: target)
            let pending = markChange(change, base: base)
            guard pending.canConfirm else { break }
            noteOwnWrite(id)
            do {
                _ = try await ChangeRunner(writer: store).run(change, seenIn: base.snapshot, base: base.issue)
                writtenMarks[key] = target
                record(pending, issueID: id, error: nil)
                // One bead changed, so read back that bead rather than the whole database.
                if let fresh = try? await store.currentIssue(id), let current = snapshot {
                    snapshot = current.replacing(fresh)
                    reapplyDesiredMarks()
                }
            } catch {
                let confirmed = writtenMarks[key] ?? false
                desiredMarks[key] = confirmed
                setMarkLocally(mark, on: confirmed, for: id)
                record(pending, issueID: id, error: error)
                break
            }
        }
    }

    /// The bead and snapshot as bd last confirmed them, which is what a change has to be
    /// validated and checked against — the live snapshot may be showing a mark bd hasn't got yet.
    private func baseIssue(_ id: IssueID, mark: IssueMark, at written: Bool) -> (issue: Issue, snapshot: IssueSnapshot)? {
        guard let snapshot, var issue = snapshot.issue(id) else { return nil }
        var labels = issue.labels.filter { $0 != mark.label }
        if written { labels.append(mark.label) }
        issue.labels = labels
        return (issue, snapshot.replacing(issue))
    }

    private func markChange(_ change: IssueChange, base: (issue: Issue, snapshot: IssueSnapshot)) -> PendingChange {
        PendingChange(
            change: change,
            base: base.issue,
            summary: ChangeDescriber.summary(change),
            subject: ChangeDescriber.subject(change, in: base.snapshot),
            details: ChangeDescriber.details(change, in: base.snapshot),
            problems: ChangeValidator.problems(for: change, in: base.snapshot),
            asksForReason: false
        )
    }

    /// Shows a mark as though bd had already recorded it.
    private func setMarkLocally(_ mark: IssueMark, on: Bool, for id: IssueID) {
        guard let snapshot, var issue = snapshot.issue(id) else { return }
        var labels = issue.labels.filter { $0 != mark.label }
        if on { labels.append(mark.label) }
        issue.labels = labels
        self.snapshot = snapshot.replacing(issue)
    }

    /// Marks clicked but not yet confirmed, re-applied after a reload so a refresh landing
    /// mid-write doesn't flicker them.
    private func reapplyDesiredMarks() {
        for (key, on) in desiredMarks {
            setMarkLocally(key.mark, on: on, for: key.id)
        }
    }

    /// Filters the current view by a mark's label, using the ordinary labels rule so it reads as
    /// a normal chip and can be removed like one.
    public func toggleMarkFilter(_ mark: IssueMark) {
        toggleFilterValue(mark.label, in: .labels)
    }

    /// Why a bead is waiting, or nil when it isn't. bd calls all of it "blocked"; this separates
    /// waiting on a bead, waiting on another project, and someone having set the status.
    public func blockedReason(for id: IssueID) -> BlockedReason? {
        guard let snapshot else { return nil }
        return BlockedReason.of(id, in: snapshot)
    }

    /// What has to finish before this bead can start; empty when nothing is in the way.
    public func unblockPath(for id: IssueID) -> UnblockPath? {
        guard let snapshot else { return nil }
        let path = UnblockPath.to(id, in: snapshot)
        return path.isBlocked ? path : nil
    }

    public func neighbourhood(around id: IssueID) -> IssueNeighbourhood? {
        guard let snapshot else { return nil }
        return IssueNeighbourhood.around(id, in: snapshot)
    }

    public var hasStarredBeads: Bool {
        snapshot?.issues.contains { $0.has(.starred) } ?? false
    }

    public func isMarked(_ mark: IssueMark, _ id: IssueID) -> Bool {
        snapshot?.issue(id)?.has(mark) ?? false
    }

    /// The sidebar badges depend only on the saved filters and the data, so typing in search
    /// must not recount them: one pass fills every view's total, remembered until the data or
    /// the saved views change.
    @ObservationIgnored private var totalsCache: (generation: Int, views: [IssueView], totals: [IssueView.ID: Int])?

    /// What a view's own filter matches, for the sidebar badge.
    private func total(in view: IssueView) -> Int {
        guard let snapshot else { return 0 }
        if let cached = totalsCache, cached.generation == dataGeneration, cached.views == library.views {
            return cached.totals[view.id] ?? 0
        }
        let now = now()
        var totals: [IssueView.ID: Int] = [:]
        for view in library.views {
            totals[view.id] = snapshot.issues.lazy.filter { view.filter.matches($0, in: snapshot, now: now) }.count
        }
        totalsCache = (dataGeneration, library.views, totals)
        return totals[view.id] ?? 0
    }

    // MARK: Focus

    /// Narrows the current view to everything under a bead — any bead, whatever its type: bd's
    /// parent/child graph is the same relation for an epic and for a task with subtasks. Focus
    /// is a `parent · is · X` chip on the view you're in, shown as the breadcrumb, so the view's
    /// other rules still apply and there is one focus at a time.
    public func focus(on id: IssueID) {
        guard !isLocked(.parent) else { return }
        filter.set(FilterRule(field: .parent, op: .isAnyOf, values: [id.rawValue]))
    }

    /// Pops the focus chip; the rest of the view's filter stays.
    public func unfocus() {
        guard !isLocked(.parent) else { return }
        filter.remove(.parent)
    }

    /// The bead the view is focused on, for the breadcrumb; nil when there is no focus chip.
    public var focusedIssue: Issue? {
        guard let rule = filter.rule(for: .parent), let id = Self.focusedID(of: rule) else { return nil }
        return snapshot?.issue(id)
    }

    /// A parent rule naming exactly one bead to be under is a focus; several parents, or
    /// "not under", are ordinary chips.
    private static func focusedID(of rule: FilterRule) -> IssueID? {
        guard rule.field == .parent, rule.op == .isAnyOf, rule.values.count == 1, let raw = rule.values.first else { return nil }
        return IssueID(raw)
    }

    /// Where a bead could be moved to: anything that already holds work — an epic, or any bead
    /// with children — minus itself, its own descendants and anything finished.
    public func parentChoices(for id: IssueID?) -> [Issue] {
        guard let snapshot else { return [] }
        let excluded: Set<IssueID> = id.map { Set([$0] + snapshot.descendants(of: $0).map(\.id)) } ?? []
        return snapshot.issues
            .filter { !excluded.contains($0.id) && !snapshot.isDone($0) }
            .filter { $0.type == "epic" || !snapshot.children(of: $0.id).isEmpty }
            .sorted { $0.id < $1.id }
    }

    /// How much of a bead's subtree is done; nil for a bead with no children.
    public func progress(of id: IssueID) -> Completion? {
        snapshot?.progress(of: id)
    }

    // MARK: Tree expansion

    public var outlineRows: [OutlineRow] {
        OutlineRow.flatten(tree, collapsed: collapsed)
    }

    public func toggleExpansion(of id: IssueID) {
        if collapsed.contains(id) {
            collapsed.remove(id)
        } else {
            collapsed.insert(id)
        }
    }

    public func collapseAll() {
        var branches: Set<IssueID> = []
        func collect(_ nodes: [IssueTreeNode]) {
            for node in nodes where !node.children.isEmpty {
                branches.insert(node.id)
                collect(node.children)
            }
        }
        collect(tree)
        collapsed = branches
    }

    public func expandAll() {
        collapsed = []
    }

    // MARK: Editing

    public var canEdit: Bool { allowsWriting && snapshot != nil }

    /// Bumped when something asks for the selected bead to be edited (⌘E); the detail view watches it.
    public private(set) var editRequests = 0

    public func beginEditingSelection() {
        guard canEdit, selection != nil else { return }
        editRequests += 1
    }

    // MARK: Other sessions

    /// Records what bd says has been happening, usually after a reload.
    public func noteActivity(_ log: ActivityLog) {
        activityLog = log
    }

    /// The last change another session made to a bead, if it was recent enough to matter.
    ///
    /// bd has no lease or lock to take, and agents write whenever they like, so this can only
    /// inform: the app warns and keeps the data fresh rather than pretending to hold a lock.
    public func recentChange(to id: IssueID) -> ActivityEntry? {
        activityLog.latestChange(
            to: id,
            since: now().addingTimeInterval(-activityWindow),
            excluding: ownWrites[id] ?? []
        )
    }

    /// What the History expander is showing for the selected bead.
    public enum HistoryState: Equatable, Sendable {
        case loading
        case loaded([HistoryEvent])
        case failed(String)
    }

    /// Loaded only when asked for: reading a bead's history runs another bd command.
    public private(set) var history: [IssueID: HistoryState] = [:]
    /// The beads whose history is kept, oldest first, so a long session can't grow it forever.
    @ObservationIgnored private var historyOrder: [IssueID] = []
    private static let maxHistoryEntries = 50

    public func loadHistory(for id: IssueID, limit: Int = 50) async {
        if case .loading = history[id] { return }
        history[id] = .loading
        historyOrder.removeAll { $0 == id }
        historyOrder.append(id)
        while historyOrder.count > Self.maxHistoryEntries {
            history[historyOrder.removeFirst()] = nil
        }
        do {
            let versions = try await store.versions(of: id, limit: limit)
            // The cached activity only covers the last few minutes; history reaches back further,
            // so ask for a window that actually spans what's being shown.
            let oldest = versions.map(\.date).min() ?? now()
            let log = journal.isOn
                ? journalFeed.activity
                : (try? await store.recentActivity(since: oldest.addingTimeInterval(-60))) ?? activityLog
            history[id] = .loaded(History.events(from: versions, activity: log))
        } catch {
            history[id] = .failed(error.localizedDescription)
        }
    }

    // MARK: The events journal

    /// Whether bd keeps its events journal here. With it on, the journal says who made each
    /// write; without it (bd older than 1.3, or the journal left off) the interaction log does,
    /// as before. The file watcher wakes the app either way.
    public private(set) var journal: JournalStatus = .unsupported(nil)

    /// Writes the journal setting, with Beady's shorter retention where bd's defaults still
    /// stand, then starts following it. No confirmation sheet first: the sheet guards changes
    /// to beads, and this is Beady's own setting of the workspace, listed under Changes with an
    /// Undo instead. Returns the failure, if any, for the caller to show.
    @discardableResult
    public func enableJournal() async -> String? {
        guard canEdit, case .supported(_, let settings) = journal, !settings.isEnabled else { return nil }
        let written = JournalRetention.settings(toEnable: settings)
        do {
            try await store.writeJournalSettings(written)
        } catch {
            record(summary: String(localized: "Turn on bd's change journal in \(title)", bundle: .module, comment: "Changes menu entry; the value is the workspace name"), error: error)
            return error.localizedDescription
        }
        journalPolicy.noteTurnedOn()
        record(summary: String(localized: "Turned on bd's change journal in \(title)", bundle: .module, comment: "Changes menu entry; the value is the workspace name"), undo: .journalSettings(JournalRetention.settings(toUndo: written)))
        await followJournal()
        return nil
    }

    /// Takes back a change that offered it. Returns the failure, if any, for the caller to show.
    @discardableResult
    public func undo(_ entry: ChangeRecord) async -> String? {
        guard let undo = entry.undo, activity.contains(where: { $0.id == entry.id }) else { return nil }
        switch undo {
        case .journalSettings(let settings):
            do {
                try await store.writeJournalSettings(settings)
            } catch {
                return error.localizedDescription
            }
            consumeUndo(of: entry)
            record(summary: String(localized: "Turned bd's change journal off in \(title)", bundle: .module, comment: "Changes menu entry; the value is the workspace name"))
            await followJournal()
        }
        return nil
    }

    // MARK: Undo and redo

    /// Hands this model the window's undo manager. Nothing already registered moves over: a
    /// different manager means a different window, whose stack starts clean.
    public func attachUndoManager(_ manager: UndoManager?) {
        guard manager !== undoManager else { return }
        undoManager?.removeAllActions(withTarget: self)
        undoManager = manager
    }

    /// Lets go of the undo manager before this model does: registrations target this model
    /// without retaining it, so they must not outlive it.
    public func detachUndoManager() {
        undoManager?.removeAllActions(withTarget: self)
        undoManager = nil
    }

    /// Puts a landed change onto the window's undo stack, named so the Edit menu reads "Undo
    /// Move bdv-1 to In Progress". Registration is optimistic: the database is shared, so each
    /// invocation re-validates against that moment's data instead of pretending bd can be rolled
    /// back blind — a step that can no longer apply explains itself when chosen (`perform`).
    /// The explicit group makes each write one step even where no run loop turns, as in tests.
    private func registerUndo(of step: UndoStep) {
        guard let undoManager else { return }
        undoManager.beginUndoGrouping()
        undoManager.registerUndo(withTarget: self) { model in
            MainActor.assumeIsolated { model.undoStepChosen(step) }
        }
        undoManager.setActionName(step.summary)
        undoManager.endUndoGrouping()
    }

    /// Runs when the user picks Undo. Registering here, while the manager is undoing, files the
    /// opposite entry on the redo stack — that is all redo is — and the write follows.
    private func undoStepChosen(_ step: UndoStep) {
        if let undoManager {
            undoManager.registerUndo(withTarget: self) { model in
                MainActor.assumeIsolated { model.redoStepChosen(step) }
            }
            undoManager.setActionName(step.summary)
        }
        Task {
            await perform(step.undoChange, titled: String(localized: "Undo \(step.summary)", bundle: .module, comment: "Changes menu entry and sheet title; the value is the original change's summary"))
        }
    }

    /// Runs when the user picks Redo: files the undo back and applies the original change again.
    private func redoStepChosen(_ step: UndoStep) {
        if let undoManager {
            undoManager.registerUndo(withTarget: self) { model in
                MainActor.assumeIsolated { model.undoStepChosen(step) }
            }
            undoManager.setActionName(step.summary)
        }
        Task {
            await perform(step.redoChange, titled: String(localized: "Redo \(step.summary)", bundle: .module, comment: "Changes menu entry and sheet title; the value is the original change's summary"))
        }
    }

    /// Writes one undo or redo step: a bead change like any other, validated against today's
    /// data, written safely, journalled. Written at once when clean — the Edit menu named
    /// exactly what would happen — but a step that can't apply any more (the bead moved on
    /// since) raises the confirmation sheet with the problems spelled out and Apply disabled,
    /// so it explains itself rather than failing silently; so does a write that fails.
    private func perform(_ change: IssueChange, titled summary: String) async {
        guard var pending = makePending(change) else { return }
        pending.summary = summary
        pending.registersUndo = false
        if pending.problems.contains(where: { $0.severity == .error }) {
            pendingChange = pending
            return
        }
        await write(pending)
    }

    /// Spends an entry's one Undo, once it has been used successfully.
    private func consumeUndo(of entry: ChangeRecord) {
        if let index = activity.firstIndex(where: { $0.id == entry.id }) {
            activity[index].undo = nil
        }
    }

    /// Re-reads the journal's settings after writing them, and starts over from whichever
    /// source of activity now applies.
    private func followJournal() async {
        journal = await store.journalStatus()
        journalFeed = JournalFeed()
        if let log = await readActivity(since: now().addingTimeInterval(-activityWindow)) {
            noteActivity(log)
        }
    }

    /// Who has been working where: from the journal when it's on, else bd's interaction log.
    /// A pruned checkpoint moves up to what bd still has and reads once more; a journal that
    /// can't be read falls back to the log rather than going quiet.
    private func readActivity(since cutoff: Date) async -> ActivityLog? {
        guard journal.isOn else { return try? await store.recentActivity(since: cutoff) }
        let kept = now().addingTimeInterval(-TimeInterval(JournalRetention.days) * 86_400)
        for _ in 0..<2 {
            guard let read = try? await store.journalRecords(after: journalFeed.checkpoint) else {
                return try? await store.recentActivity(since: cutoff)
            }
            journalFeed = journalFeed.applying(read, keepingSince: min(kept, cutoff))
            if case .records = read { break }
        }
        return journalFeed.activity
    }

    /// Beads another session has touched lately, for marking rows in a list.
    public var beadsChangedElsewhere: Set<IssueID> {
        let since = now().addingTimeInterval(-activityWindow)
        return Set(activityLog.issuesChanged(since: since).filter { recentChange(to: $0) != nil })
    }

    /// Stages a change for confirmation. Nothing is written until `confirmPendingChange`.
    /// - Parameter base: the issue as the user saw it when they started, if earlier than the
    ///   current snapshot (an edit form opened before an auto-refresh, for example).
    public func propose(_ change: IssueChange, basedOn base: Issue? = nil) {
        // A refused proposal (mid-write, say) leaves whatever is staged alone.
        guard let pending = makePending(change, basedOn: base) else { return }
        pendingChange = pending
    }

    /// A change with everything needed to judge it: normalized, validated, described.
    private func makePending(_ change: IssueChange, basedOn base: Issue? = nil) -> PendingChange? {
        guard canEdit, !isWriting, let snapshot else { return nil }
        let normalized = change.normalized()
        let asksForReason: Bool = if case .setStatus(_, let from, let to, _) = normalized {
            to == "closed" || from == "closed"
        } else {
            false
        }
        var problems = ChangeValidator.problems(for: normalized, in: snapshot)
        if let id = normalized.issueID, let recent = recentChange(to: id) {
            problems.append(ChangeProblem(
                code: .recentlyChangedElsewhere,
                severity: .warning,
                message: String(localized: "\(recent.actor) changed \(recent.field ?? String(localized: "this bead", bundle: .module, comment: "Stands in for a field name when bd didn't record one")) \(ChangeDescriber.ago(recent.date, from: now())). Refresh if you're not sure you're looking at the latest.", bundle: .module, comment: "Warning: who changed what, and a relative time such as ‘2 minutes ago’")
            ))
        }
        return PendingChange(
            change: normalized,
            base: base ?? normalized.issueID.flatMap { snapshot.issue($0) },
            summary: ChangeDescriber.summary(normalized),
            subject: ChangeDescriber.subject(normalized, in: snapshot),
            details: ChangeDescriber.details(normalized, in: snapshot),
            problems: problems,
            asksForReason: asksForReason
        )
    }

    /// Moving to a lifecycle. Moving to the one it's already in does nothing.
    /// Proposes adding or removing a blocker. bd keeps these as dependencies rather than fields,
    /// so this is its own change and gets its own confirmation.
    public func proposeBlocker(_ id: IssueID, blocker: IssueID, on: Bool) {
        propose(.setBlocker(id, blocker: blocker, on: on))
    }

    /// Beads that could be made to block this one: everything else unfinished, minus the ones
    /// already in the way and anything that would close a loop.
    public func blockerChoices(for id: IssueID) -> [Issue] {
        guard let snapshot, let issue = snapshot.issue(id) else { return [] }
        let already = Set(snapshot.blockers(of: issue).map(\.id))
        return snapshot.issues
            .filter { $0.id != id && !already.contains($0.id) && !snapshot.isDone($0) }
            .filter { candidate in
                ChangeValidator.problems(for: .setBlocker(id, blocker: candidate.id, on: true), in: snapshot)
                    .allSatisfy { $0.severity != .error }
            }
            .sorted { $0.id < $1.id }
    }

    /// Proposes an exact status, for a form that lists bd's own statuses.
    public func proposeStatus(_ id: IssueID, to status: String) {
        guard let snapshot, let issue = snapshot.issue(id), status != issue.status else { return }
        propose(.setStatus(id, from: issue.status, to: status, reason: nil))
    }

    public func proposeStatusMove(_ id: IssueID, to category: StatusCategory) {
        guard let snapshot, let issue = snapshot.issue(id), snapshot.category(of: issue) != category else { return }
        propose(.setStatus(id, from: issue.status, to: category.defaultStatus, reason: nil))
    }

    public func proposeParent(_ id: IssueID, to parent: IssueID?) {
        guard let issue = snapshot?.issue(id) else { return }
        propose(.setParent(id, from: issue.parentID, to: parent))
    }

    /// Dropping a card on a board column proposes giving it that column's value, for the
    /// groupings where that's a change the app can make: lifecycle, status, priority and parent.
    /// Returns whether a change was proposed.
    @discardableResult
    /// Whether dropping this bead on that column would change anything — answered without
    /// staging a change, so a drag can be accepted or refused while the cursor is still moving.
    /// Dropping a card back where it started must snap straight home, not wait on validation.
    public func canDrop(_ id: IssueID, onGroup key: String) -> Bool {
        // A bead whose own drop is still writing can't be dropped again (the retry would race
        // the write), but every other bead stays droppable while writes queue up behind.
        guard canEdit, !isWriting, optimisticIssues[id] == nil,
              let snapshot, let issue = snapshot.issue(id) else { return false }
        switch boardGrouping {
        case .category:
            guard let category = StatusCategory(rawValue: key) else { return false }
            return snapshot.category(of: issue) != category
        case .status:
            return !key.isEmpty && key != issue.status
        case .priority:
            return Int(key).map { $0 != issue.priority } ?? false
        case .parent:
            return (key.isEmpty ? nil : IssueID(key)) != issue.parentID
        case .none, .type, .assignee:
            return false
        }
    }

    public func proposeDrop(_ id: IssueID, onGroup key: String) -> Bool {
        guard canDrop(id, onGroup: key), let snapshot, let issue = snapshot.issue(id) else { return false }
        let previous = pendingChange?.id
        switch boardGrouping {
        case .category:
            guard let category = StatusCategory(rawValue: key) else { return false }
            proposeStatusMove(id, to: category)
        case .status:
            guard !key.isEmpty, key != issue.status else { return false }
            propose(.setStatus(id, from: issue.status, to: key, reason: nil))
        case .priority:
            guard let priority = Int(key), priority != issue.priority else { return false }
            propose(.edit(id, IssueEdit(priority: priority)))
        case .parent:
            let parent = key.isEmpty ? nil : IssueID(key)
            guard parent != issue.parentID else { return false }
            proposeParent(id, to: parent)
        case .none, .type, .assignee:
            return false
        }
        return pendingChange != nil && pendingChange?.id != previous
    }

    /// The close or reopen reason typed into the confirmation sheet.
    public var pendingReason: String {
        get {
            if case .setStatus(_, _, _, let reason) = pendingChange?.change { return reason ?? "" }
            return ""
        }
        set {
            guard !isWriting, case .setStatus(let id, let from, let to, _) = pendingChange?.change else { return }
            let change = IssueChange.setStatus(id, from: from, to: to, reason: newValue)
            pendingChange?.change = change
            if let snapshot {
                pendingChange?.problems = ChangeValidator.problems(for: change.normalized(), in: snapshot)
            }
        }
    }

    public var pendingCommands: [String] {
        guard let pendingChange, allowsWriting else { return [] }
        return store.commandPreview(for: pendingChange.change.normalized())
    }

    /// A view calls this once it has finished acknowledging the change on screen, so the same
    /// acknowledgement doesn't play again when the view is rebuilt.
    public func acknowledgeAppliedChange(_ change: AppliedChange) {
        if lastAppliedChange == change { lastAppliedChange = nil }
    }

    /// Ignored while the change is being written: closing the sheet wouldn't stop bd.
    public func cancelPendingChange() {
        guard !isWriting else { return }
        pendingChange = nil
    }

    public func confirmPendingChange() async {
        guard !isWriting, allowsWriting, var pending = pendingChange, pending.canConfirm, let snapshot else { return }

        // The data may have refreshed since this was proposed. If the checks now say something
        // different, show that instead of writing.
        let problems = ChangeValidator.problems(for: pending.change.normalized(), in: snapshot)
        if problems != pending.problems {
            pending.problems = problems
            pending.notice = String(localized: "The checks changed since this was proposed, because the data was refreshed. Review them, then apply again.", bundle: .module)
            pendingChange = pending
            return
        }

        pending.isApplying = true
        pending.notice = nil
        pendingChange = pending
        await write(pending)
    }

    /// Stages the drop and, when there is nothing for the user to decide, applies it at once:
    /// the drag was the decision, so the card moves this instant — the snapshot previews the
    /// change while bd (the best part of a second across several processes) catches up in the
    /// background, the glow confirms the write landing, and the journal entry's Undo is the way
    /// back. The confirmation sheet still appears when something needs the user — a close or
    /// reopen (bd stores a reason), a warning or error from the checks, or a write that fails,
    /// which also puts the card back. Returns whether the drop was accepted at all.
    @discardableResult
    public func applyDrop(_ id: IssueID, onGroup key: String) async -> Bool {
        guard proposeDrop(id, onGroup: key), let pending = pendingChange else { return false }
        guard !pending.asksForReason, pending.problems.isEmpty else { return true }
        pendingChange = nil
        guard let seenIn = snapshot, let base = pending.base,
              let preview = pending.change.applied(to: base) else {
            // No one-bead preview for this change; the slower, known-good path.
            await write(pending)
            return true
        }
        optimisticIssues[id] = preview
        snapshot = seenIn.replacing(preview)
        selection = id
        dropQueue.append(QueuedDrop(pending: pending, seenIn: seenIn))
        await drainDrops()
        return true
    }

    /// A drop already shown on the board, waiting for its bd write.
    private struct QueuedDrop {
        let pending: PendingChange
        /// The data the change was validated against, before the board showed it early.
        let seenIn: IssueSnapshot
    }

    @ObservationIgnored private var dropQueue: [QueuedDrop] = []
    @ObservationIgnored private var isDrainingDrops = false
    /// Previews shown ahead of bd, keyed by bead: re-applied after a reload so a refresh landing
    /// mid-write doesn't snap the card back (`reapplyDesiredMarks` is the same idea for marks),
    /// and the marker that keeps the bead from being dropped again before its write settles.
    @ObservationIgnored private var optimisticIssues: [IssueID: Issue] = [:]

    /// Writes queued drops one at a time, never alongside a confirmed change's write. On
    /// success, only the changed bead is read back — the full reload costs three more bd
    /// processes and the file watcher covers anything else. On failure the preview is taken
    /// back, so the card visibly returns, and the sheet says why.
    private func drainDrops() async {
        guard !isDrainingDrops else { return }
        isDrainingDrops = true
        defer { isDrainingDrops = false }
        while !dropQueue.isEmpty {
            while isWriting { try? await Task.sleep(for: .milliseconds(25)) }
            let drop = dropQueue.removeFirst()
            let pending = drop.pending
            guard let id = pending.change.issueID else { continue }
            noteOwnWrite(id)
            do {
                let written = try await ChangeRunner(writer: store).run(pending.change, seenIn: drop.seenIn, base: pending.base)
                noteOwnWrite(written)
                optimisticIssues[id] = nil
                record(pending, issueID: written, error: nil)
                // The optimistic path lands on the undo stack just as write(_:) does (rule 12).
                if pending.registersUndo, let reverse = pending.change.reversed(from: pending.base) {
                    registerUndo(of: UndoStep(summary: pending.summary, undoChange: reverse, redoChange: pending.change))
                }
                if let fresh = try? await store.currentIssue(written), let current = snapshot {
                    snapshot = current.replacing(fresh)
                    reapplyDesiredMarks()
                    reapplyOptimisticDrops()
                }
                lastAppliedChange = AppliedChange(issueID: written, sequence: (lastAppliedChange?.sequence ?? 0) + 1)
            } catch {
                optimisticIssues[id] = nil
                // Put the card back as bd has it (one cheap read), or as it was before the drop.
                let truth = (try? await store.currentIssue(id)) ?? pending.base
                if let truth, let current = snapshot {
                    snapshot = current.replacing(truth)
                }
                record(pending, issueID: id, error: error)
                if pendingChange == nil {
                    var failed = pending
                    failed.failure = error.localizedDescription
                    pendingChange = failed
                }
            }
        }
    }

    /// Puts in-flight previews back on top of a freshly loaded snapshot.
    private func reapplyOptimisticDrops() {
        guard var updated = snapshot else { return }
        for issue in optimisticIssues.values { updated = updated.replacing(issue) }
        snapshot = updated
    }

    /// Runs the safe write and settles the outcome: the journal entry (with its Undo where the
    /// change has a reverse), the reload, the selection and the on-screen acknowledgement. A
    /// failure keeps the sheet up when it was showing — and raises it when the write had skipped
    /// the sheet, so a drop never fails silently.
    private func write(_ pending: PendingChange) async {
        guard !isWriting, allowsWriting else { return }
        // Queued drops write one at a time; a confirmed change waits its turn like any of them.
        while isDrainingDrops { try? await Task.sleep(for: .milliseconds(25)) }
        guard let snapshot else { return }
        var pending = pending
        isWriting = true
        noteOwnWrite(pending.change.issueID)
        let outcome: Result<IssueID, Error>
        do {
            outcome = .success(try await ChangeRunner(writer: store).run(pending.change, seenIn: snapshot, base: pending.base))
        } catch {
            outcome = .failure(error)
        }
        isWriting = false

        let stillShowing = pendingChange?.id == pending.id
        switch outcome {
        case .success(let id):
            noteOwnWrite(id)
            record(pending, issueID: id, error: nil)
            if stillShowing { pendingChange = nil }
            // A change that landed and has a reverse goes onto the window's undo stack; an undo
            // or redo being written manages its own place there instead.
            if pending.registersUndo, let reverse = pending.change.reversed(from: pending.base) {
                registerUndo(of: UndoStep(summary: pending.summary, undoChange: reverse, redoChange: pending.change))
            }
            await reloadAfterWrite()
            selection = id
            lastAppliedChange = AppliedChange(issueID: id, sequence: (lastAppliedChange?.sequence ?? 0) + 1)
        case .failure(let error):
            record(pending, issueID: pending.change.issueID, error: error)
            if stillShowing || pendingChange == nil {
                pending.isApplying = false
                pending.failure = error.localizedDescription
                pendingChange = pending
            }
            // Show the current state behind the sheet, so the failure can be understood.
            await reloadAfterWrite()
        }
    }

    /// Remembers that a write of ours landed (or may have), and forgets stale entries.
    private func noteOwnWrite(_ id: IssueID?) {
        guard let id else { return }
        let cutoff = now().addingTimeInterval(-activityWindow * 2)
        ownWrites[id] = (ownWrites[id] ?? []).filter { $0 >= cutoff } + [now()]
    }

    private func record(_ pending: PendingChange, issueID: IssueID?, error: Error?) {
        record(summary: pending.summary, issueID: issueID, error: error)
    }

    private func record(summary: String, issueID: IssueID? = nil, error: Error? = nil, undo: ChangeRecord.Undo? = nil) {
        let entry = ChangeRecord(
            date: now(), summary: summary, issueID: issueID,
            succeeded: error == nil, message: error?.localizedDescription, undo: undo
        )
        activity.insert(entry, at: 0)
        if activity.count > 50 { activity.removeLast() }
    }

    /// A background refresh may be mid-flight; wait for it so this load isn't skipped.
    private func reloadAfterWrite() async {
        while isLoading {
            try? await Task.sleep(for: .milliseconds(50))
        }
        await load()
    }
}
