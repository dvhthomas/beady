import BeadsCore
import BeadsPresentation
import SwiftUI

struct IssueDetailView: View {
    @Bindable var model: WorkspaceModel

    init(model: WorkspaceModel) {
        self.model = model
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if model.canGoBack || model.canGoForward {
                historyBar
            }
            content
        }
        .onChange(of: model.selection) { model.endEditing() }
        .onChange(of: model.editRequests) {
            if let id = model.selection { model.beginEditing(id) }
        }
        .onChange(of: model.activity.first?.id) {
            if model.activity.first?.succeeded == true { model.endEditing() }
        }
    }

    /// A binding to the draft that survives the draft being cleared underneath it.
    ///
    /// `Binding($model.draft)` looks tidier and force-unwraps: when a write lands and editing
    /// ends, SwiftUI updates the binding before the view goes away and traps on the nil. This
    /// falls back to the last value instead.
    private func draftBinding(for issue: Issue) -> Binding<EditDraft>? {
        guard let current = model.draft, current.id == issue.id else { return nil }
        return Binding(
            get: { model.draft ?? current },
            set: { model.draft = $0 }
        )
    }

    /// Following a blocker link replaces what's in this pane, so there has to be a way back to
    /// the bead you came from.
    private var historyBar: some View {
        HStack(spacing: 6) {
            Button { model.goBack() } label: {
                Label("Back", systemImage: "chevron.left")
            }
            .disabled(!model.canGoBack)
            .help("Back to the last bead you were looking at (⌘[)")

            Button { model.goForward() } label: {
                Label("Forward", systemImage: "chevron.right")
            }
            .disabled(!model.canGoForward)
            .help("Forward (⌘])")

            Spacer(minLength: 0)
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.accessoryBar)
        .controlSize(.small)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var content: some View {
        Group {
            if let issue = model.selectedIssue, let snapshot = model.snapshot {
                if let draft = draftBinding(for: issue) {
                    EditBeadForm(model: model, draft: draft) { model.endEditing() }
                } else {
                    IssueDetailContent(issue: issue, snapshot: snapshot, model: model) {
                        model.beginEditing(issue.id)
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
                if let reason = model.blockedReason(for: issue.id) {
                    Label(reason.summary, systemImage: "pause.circle")
                        .font(.caption)
                        .foregroundStyle(theme.color(.frozen))
                        .help("bd calls this blocked; it means something upstream has to finish first.")
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
            ForEach(IssueMark.allCases, id: \.self) { mark in
                Button {
                    Task { await model.toggleMark(mark, on: issue.id) }
                } label: {
                    // Icon only: the action row is tight, and a filled pin or star says enough.
                    Image(systemName: issue.has(mark)
                        ? MarkStyle.symbol(mark)
                        : MarkStyle.symbol(mark).replacingOccurrences(of: ".fill", with: ""))
                        .foregroundStyle(issue.has(mark) ? (mark == .pinned ? theme.pinned : theme.starred) : theme.secondaryText)
                }
                .accessibilityLabel(MarkStyle.action(mark, isOn: issue.has(mark)))
                .help(mark == .pinned
                    ? "Pinned beads lead every list, tree and board column (bd label “pinned”)"
                    : "Starred beads collect in the Starred view (bd label “starred”)")
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
        VStack(alignment: .leading, spacing: 8) {
            Button {
                isExpanded.wrappedValue.toggle()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .rotationEffect(.degrees(isExpanded.wrappedValue ? 90 : 0))
                    Text("History")
                        .font(.headline)
                    Spacer(minLength: 0)
                }
                // The whole row is the target, not the chevron.
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(isExpanded.wrappedValue ? "Hide this bead's history" : "Every change bd has recorded for this bead")

            if isExpanded.wrappedValue {
                content
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
