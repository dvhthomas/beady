import BeadsCore
import BeadsPresentation
import SwiftUI

struct IssueDetailView: View {
    let model: WorkspaceModel
    /// `State` as a plain DynamicProperty: Command Line Tools lack the @State macro plugin.
    private var isEditing = State(initialValue: false)

    init(model: WorkspaceModel) {
        self.model = model
    }

    var body: some View {
        Group {
            if let issue = model.selectedIssue, let snapshot = model.snapshot {
                if isEditing.wrappedValue, model.canEdit {
                    EditIssueForm(issue: issue, model: model) { isEditing.wrappedValue = false }
                        .id(issue.id)
                } else {
                    IssueDetailContent(issue: issue, snapshot: snapshot, model: model) {
                        isEditing.wrappedValue = true
                    }
                }
            } else {
                ContentUnavailableView(
                    "No Selection",
                    systemImage: "doc.text.magnifyingglass",
                    description: Text("Select an issue to see its details.")
                )
            }
        }
        .onChange(of: model.selection) { isEditing.wrappedValue = false }
        .onChange(of: model.editRequests) { isEditing.wrappedValue = model.canEdit && model.selectedIssue != nil }
        .onChange(of: model.activity.first?.id) {
            if model.activity.first?.succeeded == true { isEditing.wrappedValue = false }
        }
    }
}

private struct IssueDetailContent: View {
    @Environment(\.theme) private var theme
    let issue: Issue
    let snapshot: IssueSnapshot
    let model: WorkspaceModel
    let onEdit: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                if model.canEdit {
                    editActions
                }
                if let completion = snapshot.progress(of: issue.id) {
                    progress(completion)
                }
                metadata
                relations
                textSection("Description", issue.description)
                textSection("Notes", issue.notes)
                HistorySection(model: model, issue: issue)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(issue.id.rawValue)
                .font(.callout.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            Text(issue.title)
                .font(.title3.weight(.semibold))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                StatusBadge(status: issue.status, category: snapshot.category(of: issue))
                PriorityBadge(priority: issue.priority)
                TypeLabel(type: issue.type)
                if snapshot.isBlocked(issue) {
                    Label("Blocked", systemImage: "exclamationmark.octagon.fill")
                        .font(.caption)
                        .foregroundStyle(theme.blocked)
                }
            }
        }
    }

    /// Each of these only proposes a change; the confirmation sheet does the writing.
    private var editActions: some View {
        HStack(spacing: 8) {
            Button("Edit", systemImage: "pencil", action: onEdit)
            Menu {
                ForEach(StatusCategory.allCases, id: \.self) { category in
                    Button(DisplayText.category(category)) {
                        model.proposeStatusMove(issue.id, to: category)
                    }
                    .disabled(snapshot.category(of: issue) == category)
                }
            } label: {
                Label("Status", systemImage: "circle.lefthalf.filled")
            }
            Menu {
                Button("No Parent") { model.proposeParent(issue.id, to: nil) }
                    .disabled(issue.parentID == nil)
                Divider()
                ForEach(model.parentChoices(for: issue.id)) { parent in
                    Button("\(parent.id.rawValue) — \(parent.title)") {
                        model.proposeParent(issue.id, to: parent.id)
                    }
                    .disabled(issue.parentID == parent.id)
                }
            } label: {
                Label("Move To", systemImage: "arrow.turn.down.right")
            }
        }
        .controlSize(.small)
    }

    private func progress(_ completion: Completion) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ProgressView(value: completion.fraction)
                .tint(theme.color(.done))
            HStack {
                Text("\(completion.closed) of \(completion.total) descendants closed")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Focus on This Bead") { model.focus(on: issue.id) }
                    .controlSize(.small)
            }
        }
    }

    private var metadata: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
            row("Assignee", issue.assignee ?? "Unassigned")
            if let owner = issue.owner { row("Owner", owner) }
            if !issue.labels.isEmpty { row("Labels", issue.labels.joined(separator: ", ")) }
            row("Created", formatted(issue.createdAt))
            row("Updated", formatted(issue.updatedAt))
            if let started = issue.startedAt { row("Started", formatted(started)) }
            if let closed = issue.closedAt { row("Closed", formatted(closed)) }
            if let reason = issue.closeReason { row("Close reason", reason) }
            if let reference = issue.externalRef { row("External ref", reference) }
            if issue.commentCount > 0 { row("Comments", "\(issue.commentCount)") }
        }
        .font(.callout)
    }

    private func row(_ title: String, _ value: String) -> some View {
        GridRow {
            Text(title)
                .foregroundStyle(.secondary)
                .gridColumnAlignment(.trailing)
            Text(value)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var relations: some View {
        let parent = issue.parentID.flatMap { snapshot.issue($0) }
        let blockers = snapshot.blockers(of: issue)
        let external = snapshot.externalBlockers(of: issue)
        let blocks = snapshot.dependents(of: issue.id)
        let children = snapshot.children(of: issue.id)
        if let parent { relationGroup("Parent", [parent]) }
        if !blockers.isEmpty { relationGroup("Blocked by", blockers) }
        if !external.isEmpty { externalGroup(external) }
        if !blocks.isEmpty { relationGroup("Blocks", blocks) }
        if !children.isEmpty { relationGroup("Children", children) }
    }

    private func relationGroup(_ title: String, _ issues: [Issue]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.headline)
            ForEach(issues) { related in
                let category = snapshot.category(of: related)
                Button {
                    model.selection = related.id
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: category.symbolName)
                            .foregroundStyle(theme.color(category))
                        Text(related.id.rawValue)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                        Text(related.title)
                            .lineLimit(1)
                            .strikethrough(category == .done, color: .secondary)
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("\(related.id.rawValue): \(related.title)")
            }
        }
    }

    private func externalGroup(_ ids: [IssueID]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Blocked by other projects").font(.headline)
            ForEach(ids, id: \.self) { id in
                Label(id.rawValue, systemImage: "arrow.up.forward.square")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
    }

    @ViewBuilder
    private func textSection(_ title: String, _ text: String) -> some View {
        if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.headline)
                Text(Self.markdown(text))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private static func markdown(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }

    private func formatted(_ date: Date) -> String {
        "\(date.formatted(date: .abbreviated, time: .shortened)) (\(date.formatted(.relative(presentation: .named))))"
    }
}

/// Inline editor for the text fields and priority. Proposes only the fields that changed.
private struct EditIssueForm: View {
    @Environment(\.theme) private var theme
    let model: WorkspaceModel
    let onDone: () -> Void
    /// `State` as plain DynamicProperties: Command Line Tools lack the @State macro plugin.
    /// `base` is the issue as it was when editing began. It stays put when an auto-refresh brings a
    /// newer version, so the live conflict check compares against what the user started from.
    private var base: State<Issue>
    private var title: State<String>
    private var priority: State<Int>
    private var description: State<String>
    private var notes: State<String>

    init(issue: Issue, model: WorkspaceModel, onDone: @escaping () -> Void) {
        self.model = model
        self.onDone = onDone
        base = State(initialValue: issue)
        title = State(initialValue: issue.title)
        priority = State(initialValue: issue.priority)
        description = State(initialValue: issue.description)
        notes = State(initialValue: issue.notes)
    }

    private var edit: IssueEdit {
        let original = base.wrappedValue
        func changed(_ value: String, from old: String) -> String? {
            let trim = { (text: String) in text.trimmingCharacters(in: .whitespacesAndNewlines) }
            return trim(value) == trim(old) ? nil : value
        }
        return IssueEdit(
            title: changed(title.wrappedValue, from: original.title),
            description: changed(description.wrappedValue, from: original.description),
            notes: changed(notes.wrappedValue, from: original.notes),
            priority: priority.wrappedValue == original.priority ? nil : priority.wrappedValue
        )
    }

    private var changedInBdMeanwhile: Bool {
        guard let latest = model.selectedIssue, latest.id == base.wrappedValue.id else { return false }
        return latest.updatedAt != base.wrappedValue.updatedAt
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(base.wrappedValue.id.rawValue)
                        .font(.callout.monospaced())
                        .foregroundStyle(.secondary)
                    Spacer()
                    Label("Editing", systemImage: "pencil")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(theme.pinned)
                }
                if changedInBdMeanwhile {
                    Label(
                        "This bead changed in bd since you started editing. Applying is refused if any field you changed was also changed there.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(theme.pinned)
                    .fixedSize(horizontal: false, vertical: true)
                }
                TextField("Title", text: title.projectedValue)
                    .textFieldStyle(.roundedBorder)
                    .font(.title3)
                Picker("Priority", selection: priority.projectedValue) {
                    ForEach(0...4, id: \.self) { Text(DisplayText.priority($0)).tag($0) }
                }
                .pickerStyle(.segmented)
                editor("Description", description.projectedValue)
                editor("Notes", notes.projectedValue)
                HStack {
                    Button("Cancel", action: onDone)
                    Spacer()
                    Button("Review Changes…") {
                        model.propose(.edit(base.wrappedValue.id, edit), basedOn: base.wrappedValue)
                    }
                    .disabled(edit.isEmpty)
                }
                Text("Only the fields you change are sent. Nothing is written until you confirm.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(16)
        }
    }

    private func editor(_ label: String, _ text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.headline)
            TextEditor(text: text)
                .font(.body)
                .frame(minHeight: 120)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3)))
        }
    }
}


/// Collapsed by default: every change bd has recorded for this bead, newest first. Reading it
/// runs `bd history`, so it only happens when the expander is opened.
struct HistorySection: View {
    @Environment(\.theme) private var theme
    let model: WorkspaceModel
    let issue: Issue
    private var isExpanded: State<Bool>

    /// `startExpanded` is for the offscreen snapshots, which have no one to click the expander.
    init(model: WorkspaceModel, issue: Issue, startExpanded: Bool = false) {
        self.model = model
        self.issue = issue
        isExpanded = State(initialValue: startExpanded)
    }

    var body: some View {
        DisclosureGroup(isExpanded: isExpanded.projectedValue) {
            content
                .padding(.top, 6)
        } label: {
            Text("History")
                .font(.headline)
        }
        .onAppear { load() }
        .onChange(of: isExpanded.wrappedValue) { load() }
        .onChange(of: issue.id) { isExpanded.wrappedValue = false }
        .onChange(of: issue.updatedAt) { if isExpanded.wrappedValue { load() } }
    }

    @ViewBuilder
    private var content: some View {
        switch model.history[issue.id] {
        case .loading, .none:
            ProgressView().controlSize(.small)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(theme.blocked)
        case .loaded(let events) where events.isEmpty:
            Text("bd has no recorded history for this bead.")
                .font(.caption)
                .foregroundStyle(theme.secondaryText)
        case .loaded(let events):
            VStack(alignment: .leading, spacing: 8) {
                ForEach(events) { event in
                    HistoryRow(event: event)
                }
            }
        }
    }

    private func load() {
        guard isExpanded.wrappedValue else { return }
        Task { await model.loadHistory(for: issue.id) }
    }
}

private struct HistoryRow: View {
    @Environment(\.theme) private var theme
    let event: HistoryEvent

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(event.field)
                    .font(.caption.weight(.semibold))
                Text(event.date.formatted(.relative(presentation: .named)))
                    .font(.caption)
                    .foregroundStyle(theme.secondaryText)
                if let actor = event.actor {
                    Text("· \(actor)")
                        .font(.caption)
                        .foregroundStyle(theme.secondaryText)
                }
            }
            Text(change)
                .font(.caption)
                .foregroundStyle(theme.secondaryText)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .help(event.date.formatted(date: .abbreviated, time: .standard))
    }

    private var change: String {
        if event.field == "created" { return event.to }
        if event.from.isEmpty { return event.to.isEmpty ? "cleared" : "set to \(event.to)" }
        return event.to.isEmpty ? "cleared (was \(event.from))" : "\(event.from) → \(event.to)"
    }
}
