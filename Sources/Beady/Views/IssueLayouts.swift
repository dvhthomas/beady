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
                    .help(DisplayText.preview(reason.blockers.map { "\($0.id) \($0.title)" }.joined(separator: ", ")) ?? reason.summary)
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
                            Text("\(group.issues.count)")
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
        .defaultVisibility(columns.isVisible(column, in: model.source) ? .visible : .hidden)
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
                    .help(row.isExpanded ? "Collapse" : "Expand")
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
        .help(node.isMatch ? issue.title : "\(issue.title)\nShown for context; doesn't match the filters")
    }
}

// MARK: Board

/// Columns follow the view's grouping (lifecycle when ungrouped). While editing, dropping a card
/// on a column proposes that column's value, where the grouping allows it.
struct IssueBoardView: View {
    let model: WorkspaceModel
    let ui: WorkspaceUI
    /// `State` as a plain DynamicProperty: Command Line Tools lack the @State macro plugin.
    private var monitor = State<Any?>(initialValue: nil)

    init(model: WorkspaceModel, ui: WorkspaceUI) {
        self.model = model
        self.ui = ui
    }

    var body: some View {
        // Horizontal only: each column scrolls its own cards, and a vertical axis here just let
        // the whole board float away from the top when a filter left it shorter than the pane.
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 12) {
                ForEach(model.boardGroups) { group in
                    BoardColumnView(group: group, model: model)
                        .frame(width: 290)
                }
            }
            .padding(12)
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear(perform: startWatchingKeys)
        .onDisappear(perform: stopWatchingKeys)
    }

    /// The board is a grid we drew ourselves, so the arrow keys have to be caught here — left to
    /// AppKit they walk the sidebar's list instead. Anything modal, or a text field with the
    /// keyboard, gets the key first.
    private func startWatchingKeys() {
        guard monitor.wrappedValue == nil else { return }
        let model = model
        let ui = ui
        monitor.wrappedValue = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { @MainActor event in
            guard model.layout == .board, !ui.isSheetOpen, !ui.isSearchFocused,
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
    @Environment(\.theme) private var theme
    let group: IssueGroupModel
    let model: WorkspaceModel
    /// `State` as a plain DynamicProperty: Command Line Tools lack the @State macro plugin.
    private var isDropTarget = State(initialValue: false)

    init(group: IssueGroupModel, model: WorkspaceModel) {
        self.group = group
        self.model = model
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(group.title)
                    .font(.headline)
                    .lineLimit(1)
                Text("\(group.issues.count)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 4)

            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(group.issues) { issue in
                        IssueCard(
                            issue: issue,
                            snapshot: model.snapshot,
                            isSelected: model.selection == issue.id,
                            openBlocker: { model.selection = $0 },
                            removeMark: { mark in Task { await model.toggleMark(mark, on: issue.id) } }
                        )
                            .onTapGesture { model.selection = issue.id }
                            .draggableIssue(issue.id, when: model.canEdit)
                    }
                }
                .padding(2)
            }
        }
        .padding(8)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(theme.accent, lineWidth: isDropTarget.wrappedValue ? 2 : 0)
        )
        // Only proposes; the confirmation sheet has the final say.
        .dropDestination(for: String.self) { items, _ in
            guard let dragged = IssueDragPayload.decode(items), model.canDrop(dragged, onGroup: group.key) else {
                // Nothing to do: refuse at once so the card animates home without a pause.
                return false
            }
            // Staging the change is work; let the drag finish its animation first.
            Task { @MainActor in _ = model.proposeDrop(dragged, onGroup: group.key) }
            return true
        } isTargeted: { targeted in
            isDropTarget.wrappedValue = targeted && model.canEdit
        }
    }
}

private struct IssueCard: View {
    @Environment(\.theme) private var theme
    let issue: Issue
    let snapshot: IssueSnapshot?
    let isSelected: Bool
    let openBlocker: (IssueID) -> Void
    let removeMark: (IssueMark) -> Void

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
                Text("")
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
                    WaitingMark(reason: reason, snapshot: snapshot, open: openBlocker)
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
        }
        .padding(10)
        .background(.background, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(isSelected ? theme.accent : theme.border, lineWidth: isSelected ? 2 : 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 8))
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
            guard let table = Self.tableView(near: view) else { return }
            for column in table.tableColumns where column.headerToolTip != column.title {
                column.headerToolTip = column.title
            }
        }
    }

    /// The table this background view sits behind: up to the nearest common ancestor, then down.
    private static func tableView(near view: NSView) -> NSTableView? {
        var ancestor: NSView? = view
        while let current = ancestor {
            if let found = descendantTable(of: current) { return found }
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
