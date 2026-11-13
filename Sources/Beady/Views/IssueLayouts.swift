import AppKit
import BeadsCore
import BeadsPresentation
import SwiftUI

// MARK: List

/// Linear-style list, as a table: the header can be dragged to resize, reordered, and
/// right-clicked to show or hide columns. Group headers become table sections.
struct IssueListView: View {
    @Bindable var model: WorkspaceModel
    let columns: ColumnLayout
    @Environment(\.theme) private var theme

    var body: some View {
        let groups = model.groups
        let grouped = model.grouping != .none
        Table(of: BeadsCore.Issue.self, selection: $model.selection, columnCustomization: columnCustomization) {
            column(.priority) { issue in
                PriorityBadge(priority: issue.priority)
            }
            column(.id) { issue in
                Text(issue.id.rawValue)
                    .font(.callout.monospaced())
                    .rowForeground(theme.secondaryText, secondary: true)
                    .lineLimit(1)
                    .help(DisplayText.preview(issue.id.rawValue) ?? "")
            }
            column(.status) { issue in
                let category = model.snapshot?.category(of: issue) ?? .active
                Image(systemName: category.symbolName)
                    .rowForeground(theme.color(category))
                    .help(DisplayText.status(issue.status))
            }
            column(.type) { issue in
                Image(systemName: IssueTypeStyle.symbol(for: issue.type))
                    .rowForeground(theme.secondaryText, secondary: true)
                    .help(issue.type)
            }
            column(.title) { issue in
                HStack(spacing: 6) {
                    MarkGlyphs(issue: issue) { mark in
                        Task { await model.toggleMark(mark, on: issue.id) }
                    }
                    Text(issue.title)
                        .lineLimit(1)
                        .rowForeground(theme.text)
                        .help(DisplayText.preview(issue.title) ?? "")
                    if let reason = model.blockedReason(for: issue.id) {
                        WaitingMark(reason: reason, snapshot: model.snapshot) { model.selection = $0 }
                    }
                }
            }
            column(.labels) { issue in
                Text(issue.labels.joined(separator: " · "))
                    .font(.caption)
                    .rowForeground(theme.secondaryText, secondary: true)
                    .lineLimit(1)
                    .help(DisplayText.preview(issue.labels.joined(separator: ", ")) ?? "")
            }
            column(.assignee) { issue in
                Text(issue.assignee ?? "")
                    .font(.caption)
                    .rowForeground(theme.secondaryText, secondary: true)
                    .lineLimit(1)
                    .help(DisplayText.preview(issue.assignee ?? "") ?? "")
            }
            column(.progress) { issue in
                if let completion = model.progress(of: issue.id) {
                    HStack(spacing: 6) {
                        ProgressView(value: completion.fraction)
                            .tint(theme.color(.done))
                            .controlSize(.mini)
                        Text("\(completion.closed)/\(completion.total)")
                            .font(.caption.monospacedDigit())
                            .rowForeground(theme.secondaryText, secondary: true)
                    }
                }
            }
            column(.blockedBy) { issue in
                if let reason = model.blockedReason(for: issue.id) {
                    Button {
                        // The fastest answer is the blocker itself, so the cell jumps to it.
                        if let first = reason.blockers.first { model.selection = first.id }
                    } label: {
                        Text(reason.summary)
                            .lineLimit(1)
                            .rowForeground(theme.color(.frozen), secondary: true)
                    }
                    .buttonStyle(.plain)
                    .disabled(reason.blockers.isEmpty)
                    .help(DisplayText.preview(reason.blockers.map { "\($0.id.rawValue) \($0.title)" }.joined(separator: ", ")) ?? reason.summary)
                }
            }
            column(.date) { issue in
                let date = model.ordering == .recentlyClosed ? (issue.closedAt ?? issue.updatedAt) : issue.updatedAt
                Text(date, format: .relative(presentation: .named, unitsStyle: .abbreviated))
                    .font(.caption)
                    .rowForeground(theme.secondaryText, secondary: true)
                    .lineLimit(1)
                    .help(date.formatted(date: .abbreviated, time: .shortened))
            }
        } rows: {
            // Sections only when the view is grouped: an empty header still takes a row's height.
            if grouped {
                ForEach(groups) { group in
                    Section {
                        rows(group)
                    } header: {
                        HStack(spacing: 6) {
                            Text(group.title)
                            Text(group.issues.count, format: .number)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                            // Grouped by parent, the header is a bead: say how far along it is.
                            if let completion = group.completion {
                                Text("· \(completion.closed)/\(completion.total) done")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } else {
                ForEach(groups) { group in
                    rows(group)
                }
            }
        }
        .tableStyle(.inset(alternatesRowBackgrounds: false))
        .scrollContentBackground(.hidden)
        .background(theme.background)
        // A narrow column truncates its header with an ellipsis; this puts the full name back
        // within reach on hover, which SwiftUI's Table has no API for.
        .background(TableHeaderTooltips())
    }

    @ViewBuilder
    private func rowMenu(_ issue: BeadsCore.Issue) -> some View {
        ForEach(IssueMark.allCases, id: \.self) { mark in
            Button(MarkStyle.action(mark, isOn: issue.has(mark))) {
                Task { await model.toggleMark(mark, on: issue.id) }
            }
            .disabled(!model.canEdit)
        }
        Divider()
        Button("Focus on This Bead") { model.focus(on: issue.id) }
            .disabled(model.snapshot?.children(of: issue.id).isEmpty != false)
        Button("Show Details") { model.selection = issue.id }
    }

    private var columnCustomization: Binding<TableColumnCustomization<BeadsCore.Issue>> {
        Binding(get: { columns.customization }, set: { columns.customization = $0 })
    }

    private func rows(_ group: IssueGroupModel) -> some TableRowContent<BeadsCore.Issue> {
        ForEach(group.issues) { issue in
            // Only draggable where a drag could lead somewhere: a read-only workspace can't move
            // a bead, so it shouldn't offer the affordance.
            if model.canEdit {
                TableRow(issue)
                    .draggable(IssueDragPayload.encode(issue.id))
                    .contextMenu { rowMenu(issue) }
            } else {
                TableRow(issue)
                    .contextMenu { rowMenu(issue) }
            }
        }
    }

    /// One column, sized and named from the catalog so the table and the Display menu agree.
    private func column<Content: View>(
        _ column: ListColumn,
        @ViewBuilder content: @escaping (BeadsCore.Issue) -> Content
    ) -> some TableColumnContent<BeadsCore.Issue, Never> {
        TableColumn(column.title(for: model.ordering)) { issue in
            content(issue)
        }
        .width(min: column.minimumWidth, ideal: column.idealWidth, max: column.maximumWidth.map { CGFloat($0) })
        .customizationID(column.id)
        .defaultVisibility(columns.isVisible(column, in: model.view.presentation) ? .visible : .hidden)
        .disabledCustomizationBehavior(column.isAlwaysVisible ? .visibility : [])
    }
}

// MARK: Tree

/// A flat list of pre-indented rows. Nested DisclosureGroups inside a List overlapped and
/// duplicated rows as the tree changed, so expansion lives in the model instead.
struct IssueOutlineView: View {
    @Bindable var model: WorkspaceModel
    @Environment(\.theme) private var theme

    var body: some View {
        List(model.outlineRows, selection: $model.selection) { row in
            OutlineRowView(row: row, model: model)
        }
        .scrollContentBackground(.hidden)
        .background(theme.background)
        .contextMenu {
            Button("Expand All") { model.expandAll() }
            Button("Collapse All") { model.collapseAll() }
        }
    }
}

private struct OutlineRowView: View {
    @Environment(\.theme) private var theme
    let row: OutlineRow
    let model: WorkspaceModel
    /// `State` as a plain DynamicProperty: Command Line Tools lack the @State macro plugin.
    private var isDropTarget = State(initialValue: false)

    init(row: OutlineRow, model: WorkspaceModel) {
        self.row = row
        self.model = model
    }

    var body: some View {
        HStack(spacing: 4) {
            Group {
                if row.hasChildren {
                    Button {
                        model.toggleExpansion(of: row.id)
                    } label: {
                        Image(systemName: "chevron.right")
                            .rotationEffect(.degrees(row.isExpanded ? 90 : 0))
                            .frame(width: 14, height: 14)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help(row.isExpanded ? String(localized: "Collapse", comment: "Tooltip on a tree disclosure") : String(localized: "Expand", comment: "Tooltip on a tree disclosure"))
                } else {
                    Color.clear
                }
            }
            .frame(width: 14)
            TreeIssueRow(
                node: row.node,
                snapshot: model.snapshot,
                openBlocker: { model.selection = $0 },
                removeMark: { mark in Task { await model.toggleMark(mark, on: row.id) } }
            )
        }
        .padding(.leading, CGFloat(row.depth) * 18)
        .background(isDropTarget.wrappedValue ? theme.accent.opacity(0.18) : .clear, in: RoundedRectangle(cornerRadius: 4))
        .draggableIssue(row.id, when: model.canEdit)
        // Dropping another issue on this row proposes moving it under this one.
        .dropDestination(for: String.self) { items, _ in
            guard model.canEdit, let dragged = IssueDragPayload.decode(items), dragged != row.id,
                  model.snapshot?.issue(dragged)?.parentID != row.id else { return false }
            Task { @MainActor in model.proposeParent(dragged, to: row.id) }
            return true
        } isTargeted: { targeted in
            isDropTarget.wrappedValue = targeted && model.canEdit
        }
    }
}

private struct TreeIssueRow: View {
    @Environment(\.theme) private var theme
    let node: IssueTreeNode
    let snapshot: IssueSnapshot?
    let openBlocker: (IssueID) -> Void
    let removeMark: (IssueMark) -> Void

    var body: some View {
        let issue = node.issue
        let category = snapshot?.category(of: issue) ?? .active
        HStack(spacing: 8) {
            Image(systemName: category.symbolName)
                .foregroundStyle(theme.color(category))
                .help(DisplayText.status(issue.status))
            Text(issue.id.rawValue)
                .font(.callout.monospaced())
                .foregroundStyle(.secondary)
            MarkGlyphs(issue: issue, remove: removeMark)
            Text(issue.title)
                .lineLimit(1)
                .help(DisplayText.preview(issue.title) ?? "")
            if let snapshot, let reason = BlockedReason.of(issue.id, in: snapshot) {
                WaitingMark(reason: reason, snapshot: snapshot, open: openBlocker)
            }
            Spacer(minLength: 8)
            if let completion = snapshot?.progress(of: issue.id) {
                CompletionMeter(completion: completion)
            }
            PriorityBadge(priority: issue.priority)
        }
        .opacity(node.isMatch ? 1 : 0.5)
        .help(node.isMatch ? issue.title : String(localized: "\(issue.title)\nShown for context; doesn't match the filters", comment: "Tooltip on a dimmed tree row; the value is the bead's title"))
    }
}

// MARK: Board

/// Columns follow the view's grouping (lifecycle when ungrouped). While editing, dropping a card
/// on a column gives it that column's value, where the grouping allows it — written at once when
/// clean, through the confirmation sheet when anything needs the user.
struct IssueBoardView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let model: WorkspaceModel
    let ui: WorkspaceUI
    /// `State` as a plain DynamicProperty: Command Line Tools lack the @State macro plugin.
    private var monitor = State<Any?>(initialValue: nil)
    /// One namespace for every card, so a card leaving one column and entering another is the
    /// same view to SwiftUI and glides between them instead of popping.
    private var cardSpace = Namespace()

    init(model: WorkspaceModel, ui: WorkspaceUI) {
        self.model = model
        self.ui = ui
    }

    var body: some View {
        let columns = model.boardColumns
        // Horizontal only: each column scrolls its own cards, and a vertical axis here just let
        // the whole board float away from the top when a filter left it shorter than the pane.
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 12) {
                ForEach(columns) { column in
                    BoardColumnView(column: column, model: model, cardSpace: cardSpace.wrappedValue, select: select)
                        .frame(width: column.cards.isEmpty ? BoardColumnView.railWidth : BoardColumnView.fullWidth)
                }
            }
            .padding(12)
            .frame(maxHeight: .infinity, alignment: .top)
            // Any re-arrangement animates — a confirmed drop, an undo, a background refresh —
            // so a card is seen travelling to its new column, never vanishing from the old one,
            // and a column emptying or filling is seen shrinking to or growing from its rail.
            // Under Reduce Motion the move is instant; the settle glow still marks the landing.
            .animation(reduceMotion ? nil : .snappy(duration: 0.4), value: columns.map { $0.cards.map(\.id) })
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // A click on the board that misses every card lets go of the selected one, as a click
        // below the last row of the list does. Not while an edit is open: Escape stands down
        // then too. A floating details pane lies over the board's end; its clicks are its own.
        .background(ClickWatcher(except: { point, window in
            BeadMarker.covers(point, in: window) || ui.detailsCover(point, in: window)
        }) {
            if model.selection != nil, model.draft == nil { model.selection = nil }
        })
        .onAppear(perform: startWatchingKeys)
        .onDisappear(perform: stopWatchingKeys)
    }

    /// A click on a card or a folded sub-task. The window follows the selection on its own —
    /// except when the bead clicked is already the selected one and its details were hidden
    /// since: nothing changes then, and the click should still bring them up.
    private func select(_ id: IssueID) {
        model.selection = id
        ui.follow(selection: id)
    }

    /// The board is a grid we drew ourselves, so the arrow keys have to be caught here — left to
    /// AppKit they walk the sidebar's list instead. Anything modal, or a text field with the
    /// keyboard, gets the key first.
    private func startWatchingKeys() {
        guard monitor.wrappedValue == nil else { return }
        let model = model
        let ui = ui
        monitor.wrappedValue = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { @MainActor event in
            guard model.presentedLayout == .board, !ui.isSheetOpen, !ui.isSearchFocused,
                  !(NSApp.keyWindow?.firstResponder is NSTextView) else { return event }
            switch event.keyCode {
            case 126: model.moveSelection(.up)
            case 125: model.moveSelection(.down)
            case 123: model.moveSelection(.left)
            case 124: model.moveSelection(.right)
            default: return event
            }
            return nil
        }
    }

    private func stopWatchingKeys() {
        if let monitor = monitor.wrappedValue { NSEvent.removeMonitor(monitor) }
        monitor.wrappedValue = nil
    }
}

private struct BoardColumnView: View {
    /// An empty column shrinks to this: wide enough to hit with a dragged card, narrow enough
    /// that a board of mostly empty columns is mostly board.
    static let railWidth: CGFloat = 56
    static let fullWidth: CGFloat = 290

    @Environment(\.theme) private var theme
    let column: BoardColumnModel
    let model: WorkspaceModel
    let cardSpace: Namespace.ID
    /// Selects the bead that was clicked and brings its details up.
    let select: (IssueID) -> Void
    /// `State` as a plain DynamicProperty: Command Line Tools lack the @State macro plugin.
    private var isDropTarget = State(initialValue: false)

    init(column: BoardColumnModel, model: WorkspaceModel, cardSpace: Namespace.ID, select: @escaping (IssueID) -> Void) {
        self.column = column
        self.model = model
        self.cardSpace = cardSpace
        self.select = select
    }

    private var isEmpty: Bool { column.cards.isEmpty }

    var body: some View {
        Group {
            if isEmpty {
                emptyRail
            } else {
                cards
            }
        }
        .padding(8)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(
            isDropTarget.wrappedValue && isEmpty ? theme.accent.opacity(0.14) : theme.surface.opacity(isEmpty ? 0.55 : 1),
            in: RoundedRectangle(cornerRadius: 10)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(
                    isDropTarget.wrappedValue ? theme.accent : theme.border,
                    style: StrokeStyle(
                        lineWidth: isDropTarget.wrappedValue ? 2 : 1,
                        dash: isEmpty && !isDropTarget.wrappedValue ? [5, 4] : []
                    )
                )
                .opacity(isEmpty || isDropTarget.wrappedValue ? 1 : 0)
        )
        // A clean drop writes at once, with Undo in the Changes menu as the way back; the
        // confirmation sheet appears only when something needs the user (a reason, a problem).
        .dropDestination(for: String.self) { items, _ in
            guard let dragged = IssueDragPayload.decode(items), model.canDrop(dragged, onGroup: column.key) else {
                // Nothing to do: refuse at once so the card animates home without a pause.
                return false
            }
            // Staging the change is work; let the drag finish its animation first.
            Task { @MainActor in await model.applyDrop(dragged, onGroup: column.key) }
            return true
        } isTargeted: { targeted in
            isDropTarget.wrappedValue = targeted && model.canEdit
        }
    }

    /// An empty column, shrunk to a rail with its title running down it. It exists to be
    /// dropped on — that's why empty columns are on the board at all — so the whole strip
    /// stays a drop target and lights up like a full column when a card is over it.
    private var emptyRail: some View {
        GeometryReader { proxy in
            Text(column.title)
                .font(.headline)
                .foregroundStyle(isDropTarget.wrappedValue ? AnyShapeStyle(theme.accent) : AnyShapeStyle(.secondary))
                .lineLimit(1)
                .fixedSize()
                .rotationEffect(.degrees(90))
                .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
        .accessibilityLabel(Text(column.title))
    }

    private var cards: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(column.title)
                    .font(.headline)
                    .lineLimit(1)
                Text(column.cards.count, format: .number)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 4)

            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(column.cards) { card in
                        IssueCard(
                            issue: card.issue,
                            children: card.children,
                            snapshot: model.snapshot,
                            selection: model.selection,
                            isExpanded: model.boardExpanded.contains(card.id),
                            toggleExpansion: { model.toggleBoardCard(card.id) },
                            select: select,
                            canDrag: model.canEdit,
                            removeMark: { mark in Task { await model.toggleMark(mark, on: card.id) } },
                            menu: { issue in cardMenu(issue) }
                        )
                            .onTapGesture { select(card.id) }
                            // Where the card is, for the board to tell a click on a bead from
                            // a click on the space around one.
                            .background(BeadMarker())
                            .draggableIssue(card.id, when: model.canEdit)
                            .contextMenu { cardMenu(card.issue) }
                            .matchedGeometryEffect(id: card.id, in: cardSpace)
                            .modifier(AppliedChangeGlow(
                                change: model.lastAppliedChange?.issueID == card.id ? model.lastAppliedChange : nil,
                                acknowledge: { model.acknowledgeAppliedChange($0) }
                            ))
                    }
                }
                .padding(2)
            }
        }
    }

    /// The card's menu, the same choices as a list row's.
    @ViewBuilder
    private func cardMenu(_ issue: BeadsCore.Issue) -> some View {
        ForEach(IssueMark.allCases, id: \.self) { mark in
            Button(MarkStyle.action(mark, isOn: issue.has(mark))) {
                Task { await model.toggleMark(mark, on: issue.id) }
            }
            .disabled(!model.canEdit)
        }
        Divider()
        Button("Focus on This Bead") { model.focus(on: issue.id) }
            .disabled(model.snapshot?.children(of: issue.id).isEmpty != false)
        Button("Show Details") { model.selection = issue.id }
    }
}

private struct IssueCard<Menu: View>: View {
    @Environment(\.theme) private var theme
    let issue: Issue
    /// Direct sub-tasks folded into this card; empty with nesting off.
    let children: [BoardChildRow]
    let snapshot: IssueSnapshot?
    let selection: IssueID?
    let isExpanded: Bool
    let toggleExpansion: () -> Void
    let select: (IssueID) -> Void
    let canDrag: Bool
    let removeMark: (IssueMark) -> Void
    /// The context menu for a bead on this card, built where the model lives.
    @ViewBuilder let menu: (Issue) -> Menu

    private var isSelected: Bool { selection == issue.id }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                PriorityBadge(priority: issue.priority)
                TypeLabel(type: issue.type)
                Spacer(minLength: 4)
                Text(issue.id.rawValue)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 4) {
                MarkGlyphs(issue: issue, remove: removeMark)
                Text(verbatim: "")
                    .frame(width: 0, height: 0)
            }
            .fixedSize()
            Text(issue.title)
                .font(.callout.weight(.medium))
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .help(DisplayText.preview(issue.title) ?? "")
            HStack(spacing: 6) {
                if let snapshot, let reason = BlockedReason.of(issue.id, in: snapshot) {
                    WaitingMark(reason: reason, snapshot: snapshot, open: select)
                }
                if let assignee = issue.assignee {
                    Label(assignee, systemImage: "person")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if let closedAt = issue.closedAt {
                    Text(closedAt, format: .relative(presentation: .named))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if let completion = snapshot?.progress(of: issue.id) {
                    CompletionMeter(completion: completion)
                }
            }
            if !issue.labels.isEmpty {
                Text(issue.labels.joined(separator: " · "))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            if !children.isEmpty {
                Button(action: toggleExpansion) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        Text("^[\(children.count) sub-task](inflect: true)")
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(isExpanded ? "Hide the sub-tasks" : "Show the sub-tasks")
                if isExpanded {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(children) { child in
                            childRow(child)
                        }
                    }
                }
            }
        }
        .padding(10)
        .background(.background, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(isSelected ? theme.accent : theme.border, lineWidth: isSelected ? 2 : 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 8))
    }

    /// One folded sub-task: its own status glyph — which keeps what the column said when the
    /// child folded in from another one — title and subtree progress, selectable and draggable
    /// like any card.
    private func childRow(_ child: BoardChildRow) -> some View {
        let category = snapshot?.category(of: child.issue) ?? .active
        return HStack(spacing: 6) {
            Image(systemName: category.symbolName)
                .font(.caption)
                .foregroundStyle(theme.color(category))
            Text(child.issue.title)
                .font(.caption)
                .lineLimit(1)
                .help(DisplayText.preview(child.issue.title) ?? "")
            Spacer(minLength: 4)
            if let completion = child.completion {
                CompletionMeter(completion: completion)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            selection == child.id ? AnyShapeStyle(theme.selection) : AnyShapeStyle(.clear),
            in: RoundedRectangle(cornerRadius: 5)
        )
        .contentShape(RoundedRectangle(cornerRadius: 5))
        .onTapGesture { select(child.id) }
        .draggableIssue(child.id, when: canDrag)
        .contextMenu { menu(child.issue) }
    }
}


/// Marks where a card is on the board. The board hears every click that lands on it, through
/// the window's events; SwiftUI won't say whether a card was under the pointer, but the plain
/// view planted behind each card has the card's frame, and AppKit will.
struct BeadMarker: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        Self.views.add(view)
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {}

    /// Every card on screen; a card that scrolls away or leaves the board drops out by itself.
    @MainActor private static let views = NSHashTable<NSView>.weakObjects()

    /// Where the cards are in `window`, in its coordinates.
    @MainActor static func frames(in window: NSWindow) -> [CGRect] {
        views.allObjects.filter { $0.window === window }.map { $0.convert($0.bounds, to: nil) }
    }

    /// True when `point`, in `window`'s coordinates, is on a card.
    @MainActor static func covers(_ point: CGPoint, in window: NSWindow) -> Bool {
        frames(in: window).contains { $0.contains(point) }
    }
}

/// A brief accent glow around the card whose change this session just wrote. The board moves
/// the card to its new column when the data refreshes; the glow marks where it landed, then
/// hands the acknowledgement back to the model so a rebuilt board doesn't replay it. A fade is
/// calm enough to keep under Reduce Motion — it is the confirmation, not decoration.
private struct AppliedChangeGlow: ViewModifier {
    @Environment(\.theme) private var theme
    /// The applied change, only when it was to this card's bead.
    let change: AppliedChange?
    let acknowledge: (AppliedChange) -> Void
    /// `State` as a plain DynamicProperty: Command Line Tools lack the @State macro plugin.
    private var glows = State(initialValue: false)

    init(change: AppliedChange?, acknowledge: @escaping (AppliedChange) -> Void) {
        self.change = change
        self.acknowledge = acknowledge
    }

    func body(content: Content) -> some View {
        content
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(theme.accent, lineWidth: 3)
                    .opacity(glows.wrappedValue ? 0.8 : 0)
                    .allowsHitTesting(false)
            )
            .task(id: change) {
                guard let change else { return }
                glows.wrappedValue = true
                // Hold while the card finishes travelling, then fade out and let go.
                try? await Task.sleep(for: .milliseconds(500))
                withAnimation(.easeOut(duration: 0.9)) { glows.wrappedValue = false }
                try? await Task.sleep(for: .milliseconds(900))
                acknowledge(change)
            }
    }
}

/// Finds the `NSTableView` backing a SwiftUI `Table` or `List`, starting from a plain `NSView`
/// planted in the same spot with `.background(...)`: up to the nearest common ancestor, then down.
///
/// The climb stops at the edge of the split-view pane it started in. Past that the nearest table
/// is the pane next door's — the sidebar's list, seen from a center pane that has no table
/// because its view is empty — and that one is not nearby in any sense a caller means.
@MainActor
private enum NearbyTable {
    static func tableView(near view: NSView) -> NSTableView? {
        var ancestor: NSView? = view
        while let current = ancestor {
            if let found = descendantTable(of: current) { return found }
            if current.superview is NSSplitView { return nil }
            ancestor = current.superview
        }
        return nil
    }

    private static func descendantTable(of view: NSView) -> NSTableView? {
        if let table = view as? NSTableView { return table }
        for subview in view.subviews {
            if let found = descendantTable(of: subview) { return found }
        }
        return nil
    }
}

/// Gives the table's column headers their own tooltips.
///
/// SwiftUI's `Table` offers no way to build a header view, and AppKit truncates a header that
/// doesn't fit — so the full column name would otherwise be unreachable. `NSTableColumn` has
/// `headerToolTip` for exactly this; finding the table means a short walk through the view
/// hierarchy, and if that ever fails the table simply keeps its truncated headers.
private struct TableHeaderTooltips: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        NSView(frame: .zero)
    }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async {
            guard let table = NearbyTable.tableView(near: view) else { return }
            for column in table.tableColumns where column.headerToolTip != column.title {
                column.headerToolTip = column.title
            }
        }
    }
}

/// Moves keyboard focus into this pane's table whenever `trigger` changes.
///
/// Clicking a row in the sidebar's list leaves that list as the first responder, so the very
/// next arrow key walks the sidebar — switching views — instead of moving through the beads the
/// user is actually looking at. Planting this behind the center pane's Table or List, keyed to
/// the view source, hands the keyboard back as soon as the view finishes changing.
struct FocusesOnChange<Trigger: Equatable>: NSViewRepresentable {
    let trigger: Trigger

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        // Going between a view with beads and one with none rebuilds this spot, table and all,
        // so the hand-over a changed trigger asked for dies with the old one. The new one takes
        // it up — but it can also be rebuilt mid-search, as matches come and go, so it never
        // takes the keyboard from a field.
        context.coordinator.handKeyboard(toTableNear: view, evenFromAField: false)
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        guard context.coordinator.lastTrigger != trigger else { return }
        context.coordinator.lastTrigger = trigger
        context.coordinator.handKeyboard(toTableNear: view, evenFromAField: true)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(lastTrigger: trigger)
    }

    @MainActor
    final class Coordinator {
        var lastTrigger: Trigger
        /// The hand-over in flight; a newer one replaces it.
        private var handOver: Task<Void, Never>?

        init(lastTrigger: Trigger) { self.lastTrigger = lastTrigger }

        /// Makes the pane's table first responder. The table may not be there yet — a view with
        /// nothing in it draws a placeholder instead, and the table arrives a moment after —
        /// so it looks again for a little while. Only the first look, straight after a view
        /// switch, may take the keyboard from a text field; by a later one the user may have
        /// clicked into it.
        func handKeyboard(toTableNear view: NSView, evenFromAField: Bool) {
            handOver?.cancel()
            handOver = Task { @MainActor [weak view] in
                for attempt in 0..<12 {
                    if attempt > 0 { try? await Task.sleep(for: .milliseconds(50)) }
                    guard !Task.isCancelled, let view else { return }
                    guard let window = view.window, let table = NearbyTable.tableView(near: view) else { continue }
                    if (evenFromAField && attempt == 0) || !(window.firstResponder is NSTextView) {
                        window.makeFirstResponder(table)
                    }
                    return
                }
            }
        }
    }
}
