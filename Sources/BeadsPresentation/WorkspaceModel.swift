import BeadsCore
import Foundation
import Observation

/// View state for one open beads workspace, modelled on Linear: the sidebar picks a view (a
/// lifecycle or an epic), and each view keeps its own filters, layout, grouping and ordering.
/// Loading, change-driven refresh and every write go through one `BeadsStore`.
@MainActor
@Observable
public final class WorkspaceModel {
    public enum Layout: String, CaseIterable, Identifiable, Codable, Sendable {
        case list, board, tree
        public var id: String { rawValue }
    }

    public enum LoadState: Equatable, Sendable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    public let title: String
    public private(set) var snapshot: IssueSnapshot?
    public private(set) var loadState: LoadState = .idle
    public private(set) var lastLoaded: Date?
    /// Set when a reload fails while older data is still on screen.
    public private(set) var refreshError: String?
    public private(set) var isLoading = false

    /// The view picked in the sidebar.
    public var source: ViewSource = .lifecycle(.open)
    public var selection: IssueID?
    /// Tree branches the user has folded; everything else is expanded.
    public private(set) var collapsed: Set<IssueID> = []

    public private(set) var pendingChange: PendingChange?
    /// What other sessions have been doing lately, so edits can warn about live work.
    public private(set) var activityLog: ActivityLog = .empty
    /// Newest first.
    public private(set) var activity: [ChangeRecord] = []
    /// True while a confirmed change is being written; the sheet is locked meanwhile.
    public private(set) var isWriting = false

    private var viewStates: [ViewSource: ViewState] = [:] {
        didSet { saveViewStates() }
    }

    @ObservationIgnored private let store: any BeadsStore
    /// Where each view's filters, layout, grouping and ordering are remembered between launches.
    /// Standard macOS preferences: ~/Library/Preferences/me.bitsby.beady.plist.
    @ObservationIgnored private let preferences: UserDefaults?
    @ObservationIgnored private static let viewStatesKey = "viewStates"
    @ObservationIgnored private let allowsWriting: Bool
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private let staleAfter: TimeInterval
    @ObservationIgnored private var lastAttempt: (token: String, at: Date)?
    /// When we wrote each bead, so our own changes aren't read as another session's.
    @ObservationIgnored private var ownWrites: [IssueID: [Date]] = [:]
    @ObservationIgnored private let activityWindow: TimeInterval
    /// Where `unfocus()` goes back to.
    @ObservationIgnored private var viewBeforeFocus: ViewSource = .lifecycle(.open)

    public init(
        title: String,
        store: any BeadsStore,
        allowsWriting: Bool = true,
        /// Nil keeps this model out of any saved state — which is what tests and the
        /// offscreen snapshots want. The app passes `.standard`.
        preferences: UserDefaults? = nil,
        now: @escaping @Sendable () -> Date = { Date() },
        staleAfter: TimeInterval = 300,
        activityWindow: TimeInterval = 600
    ) {
        self.title = title
        self.store = store
        self.allowsWriting = allowsWriting
        self.preferences = preferences
        self.now = now
        self.staleAfter = staleAfter
        self.activityWindow = activityWindow
        viewStates = Self.loadViewStates(from: preferences)
    }

    /// Saved views that can't be read — an older format, a corrupted value — are dropped rather
    /// than fought with: the app starts from its defaults and saves again on the next change.
    private static func loadViewStates(from preferences: UserDefaults?) -> [ViewSource: ViewState] {
        guard let data = preferences?.data(forKey: viewStatesKey),
              let saved = try? JSONDecoder().decode([SavedViewState].self, from: data) else { return [:] }
        return Dictionary(saved.map { ($0.source, $0.state) }, uniquingKeysWith: { first, _ in first })
    }

    private func saveViewStates() {
        guard let preferences else { return }
        let saved = viewStates.map { SavedViewState(source: $0.key, state: $0.value) }
        guard let data = try? JSONEncoder().encode(saved) else { return }
        preferences.set(data, forKey: Self.viewStatesKey)
    }

    // MARK: Loading

    public func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        if snapshot == nil { loadState = .loading }

        // Taken before loading, so a write that lands mid-load still triggers the next refresh.
        lastAttempt = (await store.changeToken(), now())
        if let log = try? await store.recentActivity(since: now().addingTimeInterval(-activityWindow)) {
            noteActivity(log)
        }
        do {
            snapshot = try await store.loadSnapshot()
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
    }

    /// Cheap to call often: reloads only when bd has written, or the data has gone stale.
    public func refreshIfChanged() async {
        guard let lastAttempt else { return await load() }
        let changed = await store.changeToken() != lastAttempt.token
        let stale = now().timeIntervalSince(lastAttempt.at) >= staleAfter
        if changed || stale { await load() }
    }

    // MARK: The current view's state

    private var state: ViewState {
        get { viewStates[source] ?? .defaults(for: source) }
        set { viewStates[source] = newValue }
    }

    public var filter: ViewFilter {
        get { state.filter }
        set { state.filter = newValue }
    }

    public var layout: Layout {
        get { state.layout }
        set { state.layout = newValue }
    }

    public var grouping: IssueGrouping {
        get { state.grouping }
        set { state.grouping = newValue }
    }

    public var ordering: IssueSort {
        get { state.ordering }
        set { state.ordering = newValue }
    }

    public var searchText: String {
        get { state.filter.searchText }
        set { state.filter.searchText = newValue }
    }

    public var viewTitle: String {
        switch source {
        case .lifecycle(let scope): DisplayText.scope(scope)
        case .focused(let id): snapshot?.issue(id)?.title ?? id.rawValue
        case .label(let label): IssueMark(rawValue: label)?.title ?? label
        }
    }

    // MARK: What the view shows

    public var visibleIssues: [Issue] {
        guard let snapshot else { return [] }
        let now = now()
        let source = source
        let filter = filter
        return ordering.sorted(
            snapshot.issues.filter {
                source.includes($0, in: snapshot, now: now) && filter.matches($0, in: snapshot, now: now)
            },
            // A pin is a request to see something first, wherever it appears.
            pinnedFirst: true
        )
    }

    public var groups: [IssueGroupModel] {
        makeGroups(grouping, including: [])
    }

    /// Board columns. A board needs columns, so no grouping means lifecycle columns. While editing,
    /// every value a card could be dropped into has a column, even when empty.
    public var boardGroups: [IssueGroupModel] {
        let grouping = boardGrouping
        return makeGroups(grouping, including: canEdit ? dropKeys(for: grouping) : [])
    }

    public var tree: [IssueTreeNode] {
        guard let snapshot else { return [] }
        return IssueTree.build(matches: visibleIssues, in: snapshot)
    }

    /// Resolved from the whole snapshot, so following a link to a filtered-out issue still works.
    public var selectedIssue: Issue? {
        selection.flatMap { snapshot?.issue($0) }
    }

    private var boardGrouping: IssueGrouping {
        grouping == .none ? .category : grouping
    }

    private func dropKeys(for grouping: IssueGrouping) -> [String] {
        let categories = source.categories
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
        case .assignee: return key.isEmpty ? "Unassigned" : key
        case .parent: return key.isEmpty ? "No parent" : (snapshot?.issue(IssueID(key))?.title ?? key)
        }
    }

    // MARK: Filters

    public func toggleFilterValue(_ value: String, in field: FilterField) {
        filter.toggle(value, in: field)
    }

    public func setFilterOperator(_ op: FilterOperator, for field: FilterField) {
        filter.setOperator(op, for: field)
    }

    public func removeFilter(_ field: FilterField) {
        filter.remove(field)
    }

    /// Removes this view's filter rules; other views keep theirs.
    public func clearFilters() {
        filter.removeAllRules()
    }

    public func filterOptions(for field: FilterField) -> [FilterMenuOption] {
        guard let snapshot else { return [] }
        return FilterOptions.options(for: field, source: source, filter: filter, in: snapshot, now: now()).map {
            FilterMenuOption(value: $0.value, title: valueTitle($0.value, field: field), count: $0.count, isSelected: $0.isSelected)
        }
    }

    public var filterChips: [FilterChipModel] {
        filter.rules.map { rule in
            let titles = sortedValues(rule).map { valueTitle($0, field: rule.field) }
            let values = titles.count > 2 ? "\(titles.count) \(DisplayText.noun(rule.field))" : titles.joined(separator: ", ")
            return FilterChipModel(
                field: rule.field,
                fieldTitle: DisplayText.field(rule.field),
                operatorTitle: DisplayText.operatorTitle(rule.op, valueCount: rule.values.count, field: rule.field),
                valuesTitle: rule.field == .blocked ? "" : values,
                operators: rule.field.operators.map {
                    OperatorChoice(op: $0, title: DisplayText.operatorTitle($0, valueCount: 2, field: rule.field), isSelected: $0 == rule.op)
                }
            )
        }
    }

    private func valueTitle(_ raw: String, field: FilterField) -> String {
        switch field {
        case .status: DisplayText.status(raw)
        case .priority: Int(raw).map(DisplayText.priority) ?? raw
        case .assignee: raw.isEmpty ? "Unassigned" : raw
        case .blocked: "Blocked"
        case .parent: snapshot?.issue(IssueID(raw))?.title ?? raw
        case .updated, .closed: TimeWindow(rawValue: raw).map(DisplayText.window) ?? raw
        case .type, .labels: raw
        }
    }

    private func sortedValues(_ rule: FilterRule) -> [String] {
        switch rule.field {
        case .priority:
            return rule.values.sorted { (Int($0) ?? .max) < (Int($1) ?? .max) }
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

    public var sidebarViews: [SidebarEntry] {
        let scopes: [Scope] = [.open, .ready, .inFlight, .blocked, .deferred, .closed, .all]
        var entries = scopes.map { scope in
            SidebarEntry(source: .lifecycle(scope), title: DisplayText.scope(scope), count: total(in: .lifecycle(scope)))
        }
        // Starred only earns a place in the sidebar once something is starred.
        let starred = ViewSource.label(IssueMark.starred.label)
        let count = total(in: starred)
        if count > 0 {
            entries.append(SidebarEntry(source: starred, title: IssueMark.starred.title, count: count))
        }
        return entries
    }

    // MARK: Pins and stars

    /// Adds or removes the bd label behind a mark. Marks are reversible metadata that can't lose
    /// anyone's work, so they apply immediately — the confirmation sheet is for content and the
    /// graph. The write still goes through `ChangeRunner`: validated, applied, read back.
    public func toggleMark(_ mark: IssueMark, on id: IssueID) async {
        guard canEdit, !isWriting, let snapshot, let issue = snapshot.issue(id) else { return }
        let change = IssueChange.setMark(id, mark, on: !issue.has(mark))
        let pending = PendingChange(
            change: change,
            base: issue,
            summary: ChangeDescriber.summary(change),
            subject: ChangeDescriber.subject(change, in: snapshot),
            details: ChangeDescriber.details(change, in: snapshot),
            problems: ChangeValidator.problems(for: change, in: snapshot),
            asksForReason: false
        )
        guard pending.canConfirm else { return }

        isWriting = true
        noteOwnWrite(id)
        do {
            _ = try await ChangeRunner(writer: store).run(change, seenIn: snapshot, base: issue)
            record(pending, issueID: id, error: nil)
        } catch {
            record(pending, issueID: id, error: error)
        }
        isWriting = false
        await reloadAfterWrite()
    }

    /// Filters the current view by a mark's label, using the ordinary labels rule so it reads as
    /// a normal chip and can be removed like one.
    public func toggleMarkFilter(_ mark: IssueMark) {
        toggleFilterValue(mark.label, in: .labels)
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

    /// Unfinished epics, each a view of everything under it.
    private func total(in source: ViewSource) -> Int {
        guard let snapshot else { return 0 }
        let now = now()
        return snapshot.issues.lazy.filter { source.includes($0, in: snapshot, now: now) }.count
    }

    /// Opens the view of everything under `id`.
    /// Points the whole view at everything under a bead — any bead, whatever its type. bd's
    /// parent/child graph is the same relation for an epic and for a task with subtasks.
    public func focus(on id: IssueID) {
        if case .lifecycle = source { viewBeforeFocus = source }
        source = .focused(id)
    }

    /// Back to the view you were in before focusing.
    public func unfocus() {
        source = viewBeforeFocus
    }

    /// The bead the view is focused on, for the breadcrumb; nil in a lifecycle view.
    public var focusedIssue: Issue? {
        guard case .focused(let id) = source else { return nil }
        return snapshot?.issue(id)
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

    public func loadHistory(for id: IssueID, limit: Int = 50) async {
        if case .loading = history[id] { return }
        history[id] = .loading
        do {
            let versions = try await store.versions(of: id, limit: limit)
            // The cached activity only covers the last few minutes; history reaches back further,
            // so ask for a window that actually spans what's being shown.
            let oldest = versions.map(\.date).min() ?? now()
            let log = (try? await store.recentActivity(since: oldest.addingTimeInterval(-60))) ?? activityLog
            history[id] = .loaded(History.events(from: versions, activity: log))
        } catch {
            history[id] = .failed(error.localizedDescription)
        }
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
        guard canEdit, !isWriting, let snapshot else { return }
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
                message: "\(recent.actor) changed \(recent.field ?? "this bead") \(ChangeDescriber.ago(recent.date, from: now())). Refresh if you're not sure you're looking at the latest."
            ))
        }
        pendingChange = PendingChange(
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
    public func proposeDrop(_ id: IssueID, onGroup key: String) -> Bool {
        guard canEdit, let snapshot, let issue = snapshot.issue(id) else { return false }
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
            pending.notice = "The checks changed since this was proposed, because the data was refreshed. Review them, then apply again."
            pendingChange = pending
            return
        }

        pending.isApplying = true
        pending.notice = nil
        pendingChange = pending
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
            await reloadAfterWrite()
            selection = id
        case .failure(let error):
            record(pending, issueID: pending.change.issueID, error: error)
            if stillShowing {
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
        let entry = ChangeRecord(
            date: now(), summary: pending.summary, issueID: issueID,
            succeeded: error == nil, message: error?.localizedDescription
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
