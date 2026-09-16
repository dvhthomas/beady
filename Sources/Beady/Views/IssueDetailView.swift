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
    let issue: Issue
    let snapshot: IssueSnapshot
    let model: WorkspaceModel
    let onEdit: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let recent = model.recentChange(to: issue.id) {
                    liveWork(recent)
                }
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
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// bd has no lock to take, so the app says who else is working here and keeps going.
    private func liveWork(_ entry: ActivityEntry) -> some View {
        Label(
            "\(entry.actor) changed \(entry.field ?? "this bead") \(entry.date.formatted(.relative(presentation: .named))). Your edits will land on top.",
            systemImage: "person.wave.2"
        )
        .font(.callout)
        .foregroundStyle(.orange)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
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
                        .foregroundStyle(.red)
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
                .tint(.green)
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
                            .foregroundStyle(category.color)
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
                        .foregroundStyle(.orange)
                }
                if changedInBdMeanwhile {
                    Label(
                        "This bead changed in bd since you started editing. Applying is refused if any field you changed was also changed there.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(.orange)
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
