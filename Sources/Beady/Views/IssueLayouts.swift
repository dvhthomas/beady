import BeadsCore
import BeadsPresentation
import SwiftUI

// MARK: List

/// Linear-style list, as a table: the header can be dragged to resize, reordered, and
/// right-clicked to show or hide columns. Group headers become table sections.
struct IssueListView: View {
    @Bindable var model: WorkspaceModel
    let columns: ColumnLayout

    var body: some View {
        let groups = model.groups
        let grouped = model.grouping != .none
        // Worked out once per render; `recentChange` scans the activity log each time it's asked.
        let changedElsewhere = model.beadsChangedElsewhere
        Table(of: BeadsCore.Issue.self, selection: $model.selection, columnCustomization: columnCustomization) {
            column(.priority) { issue in
                PriorityBadge(priority: issue.priority)
            }
            column(.id) { issue in
                Text(issue.id.rawValue)
                    .font(.callout.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .help(DisplayText.preview(issue.id.rawValue) ?? "")
            }
            column(.status) { issue in
                let category = model.snapshot?.category(of: issue) ?? .active
                Image(systemName: category.symbolName)
                    .foregroundStyle(category.color)
                    .help(DisplayText.status(issue.status))
            }
            column(.type) { issue in
                Image(systemName: IssueTypeStyle.symbol(for: issue.type))
                    .foregroundStyle(.secondary)
                    .help(issue.type)
            }
            column(.title) { issue in
                HStack(spacing: 6) {
                    Text(issue.title)
                        .lineLimit(1)
                        .help(DisplayText.preview(issue.title) ?? "")
                    if model.snapshot?.isBlocked(issue) == true { BlockedMark() }
                    if changedElsewhere.contains(issue.id) {
                        Image(systemName: "person.wave.2")
                            .foregroundStyle(.orange)
                            .help("Another session changed this recently")
                    }
                }
            }
            column(.labels) { issue in
                Text(issue.labels.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .help(DisplayText.preview(issue.labels.joined(separator: ", ")) ?? "")
            }
            column(.assignee) { issue in
                Text(issue.assignee ?? "")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .help(DisplayText.preview(issue.assignee ?? "") ?? "")
            }
            column(.progress) { issue in
                if let completion = model.progress(of: issue.id) {
                    HStack(spacing: 6) {
                        ProgressView(value: completion.fraction)
                            .tint(.green)
                            .controlSize(.mini)
                        Text("\(completion.closed)/\(completion.total)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
            column(.date) { issue in
                let date = model.ordering == .recentlyClosed ? (issue.closedAt ?? issue.updatedAt) : issue.updatedAt
                Text(date, format: .relative(presentation: .named, unitsStyle: .abbreviated))
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
    }

    @ViewBuilder
    private func rowMenu(_ issue: BeadsCore.Issue) -> some View {
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
        .defaultVisibility(column.isVisibleByDefault ? .visible : .hidden)
        .disabledCustomizationBehavior(column.isAlwaysVisible ? .visibility : [])
    }
}

// MARK: Tree

/// A flat list of pre-indented rows. Nested DisclosureGroups inside a List overlapped and
/// duplicated rows as the tree changed, so expansion lives in the model instead.
struct IssueOutlineView: View {
    @Bindable var model: WorkspaceModel

    var body: some View {
        List(model.outlineRows, selection: $model.selection) { row in
            OutlineRowView(row: row, model: model)
        }
        .contextMenu {
            Button("Expand All") { model.expandAll() }
            Button("Collapse All") { model.collapseAll() }
        }
    }
}

private struct OutlineRowView: View {
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
            TreeIssueRow(node: row.node, snapshot: model.snapshot)
        }
        .padding(.leading, CGFloat(row.depth) * 18)
        .background(isDropTarget.wrappedValue ? Color.accentColor.opacity(0.18) : .clear, in: RoundedRectangle(cornerRadius: 4))
        .draggableIssue(row.id, when: model.canEdit)
        // Dropping another issue on this row proposes moving it under this one.
        .dropDestination(for: String.self) { items, _ in
            guard model.canEdit, let dragged = IssueDragPayload.decode(items), dragged != row.id else { return false }
            model.proposeParent(dragged, to: row.id)
            return true
        } isTargeted: { targeted in
            isDropTarget.wrappedValue = targeted && model.canEdit
        }
    }
}

private struct TreeIssueRow: View {
    let node: IssueTreeNode
    let snapshot: IssueSnapshot?

    var body: some View {
        let issue = node.issue
        let category = snapshot?.category(of: issue) ?? .active
        HStack(spacing: 8) {
            Image(systemName: category.symbolName)
                .foregroundStyle(category.color)
                .help(DisplayText.status(issue.status))
            Text(issue.id.rawValue)
                .font(.callout.monospaced())
                .foregroundStyle(.secondary)
            Text(issue.title)
                .lineLimit(1)
                .help(DisplayText.preview(issue.title) ?? "")
            if snapshot?.isBlocked(issue) == true { BlockedMark() }
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

    var body: some View {
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
    }
}

private struct BoardColumnView: View {
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
                        IssueCard(issue: issue, snapshot: model.snapshot, isSelected: model.selection == issue.id)
                            .onTapGesture { model.selection = issue.id }
                            .draggableIssue(issue.id, when: model.canEdit)
                    }
                }
                .padding(2)
            }
        }
        .padding(8)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.accentColor, lineWidth: isDropTarget.wrappedValue ? 2 : 0)
        )
        // Only proposes; the confirmation sheet has the final say.
        .dropDestination(for: String.self) { items, _ in
            guard let dragged = IssueDragPayload.decode(items) else { return false }
            return model.proposeDrop(dragged, onGroup: group.key)
        } isTargeted: { targeted in
            isDropTarget.wrappedValue = targeted && model.canEdit
        }
    }
}

private struct IssueCard: View {
    let issue: Issue
    let snapshot: IssueSnapshot?
    let isSelected: Bool

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
            Text(issue.title)
                .font(.callout.weight(.medium))
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .help(DisplayText.preview(issue.title) ?? "")
            HStack(spacing: 6) {
                if snapshot?.isBlocked(issue) == true { BlockedMark() }
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
                .strokeBorder(isSelected ? Color.accentColor : Color.secondary.opacity(0.2), lineWidth: isSelected ? 2 : 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 8))
    }
}
