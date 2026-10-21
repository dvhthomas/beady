import BeadsCore
import BeadsPresentation
import SwiftUI

/// Shown before any write: what changes, problems, the exact bd commands, and the outcome.
struct ChangeConfirmationView: View {
    @Environment(\.theme) private var theme
    @Bindable var model: WorkspaceModel
    let pending: PendingChange
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(pending.summary)
                    .font(.title3.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                if let subject = pending.subject {
                    Text(subject)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            box("What changes", comment: "Heading on the confirmation sheet: the change, line by line") {
                ForEach(Array(pending.details.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if !pending.problems.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(pending.problems.enumerated()), id: \.offset) { _, problem in
                        let isError = problem.severity == .error
                        Label(problem.message, systemImage: isError ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(isError ? theme.blocked : theme.pinned)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            if pending.asksForReason {
                TextField("Reason (stored by bd)", text: $model.pendingReason)
                    .textFieldStyle(.roundedBorder)
            }

            box("bd will run", comment: "Heading on the confirmation sheet: the exact bd commands") {
                ForEach(Array(model.pendingCommands.enumerated()), id: \.offset) { _, command in
                    Text(command)
                        .font(.callout.monospaced())
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Text("Right before writing, the bead is read again from bd, and nothing is written if a field you're changing has moved since you started. bd has no atomic check-and-write, so another session writing in that same instant can't be stopped; the read-back afterwards reports anything unexpected.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let notice = pending.notice {
                Label(notice, systemImage: "arrow.triangle.2.circlepath")
                    .foregroundStyle(theme.pinned)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let failure = pending.failure {
                Label(failure, systemImage: "xmark.octagon.fill")
                    .foregroundStyle(theme.blocked)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                if pending.isApplying {
                    ProgressView().controlSize(.small)
                    Text("Writing and verifying…").foregroundStyle(.secondary)
                }
                Spacer()
                Group {
                    if pending.failure == nil {
                        Button("Cancel", action: onCancel)
                    } else {
                        Button("Close", action: onCancel)
                    }
                }
                .keyboardShortcut(.cancelAction)
                .disabled(pending.isApplying)
                Button("Apply Change") {
                    Task { await model.confirmPendingChange() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!pending.canConfirm)
            }
        }
        .padding(20)
        .frame(width: 580)
        // Closing the sheet wouldn't stop bd, so it stays up until the write is resolved.
        .interactiveDismissDisabled(pending.isApplying)
    }

    private func box<Content: View>(_ title: LocalizedStringKey, comment: StaticString, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title, comment: comment).font(.headline)
            VStack(alignment: .leading, spacing: 4, content: content)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        }
    }
}

struct NewBeadForm: View {
    @Environment(\.theme) private var theme
    let model: WorkspaceModel
    let onCancel: () -> Void
    /// `State` as plain DynamicProperties: Command Line Tools lack the @State macro plugin.
    private var title = State(initialValue: "")
    private var type = State(initialValue: "task")
    private var priority = State(initialValue: 2)
    private var parent: State<IssueID?>
    private var description = State(initialValue: "")
    private var titleFocus = FocusState<Bool>()

    init(model: WorkspaceModel, onCancel: @escaping () -> Void) {
        self.model = model
        self.onCancel = onCancel
        let selected = model.selectedIssue
        parent = State(initialValue: selected?.type == "epic" ? selected?.id : selected?.parentID)
    }

    private var types: [String] {
        ChangeValidator.coreTypes.union(model.snapshot?.types ?? []).sorted()
    }

    private var parentChoices: [Issue] {
        var choices = model.parentChoices(for: nil)
        if let current = parent.wrappedValue, !choices.contains(where: { $0.id == current }),
           let issue = model.snapshot?.issue(current) {
            choices.insert(issue, at: 0)
        }
        return choices
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New Bead").font(.title3.weight(.semibold))
            FormField(title: "Title") {
                TextField("What needs doing?", text: title.projectedValue)
                    .textFieldStyle(.roundedBorder)
                    .font(.title3)
                    .labelsHidden()
                    .focused(titleFocus.projectedValue)
            }
            HStack(alignment: .top, spacing: 16) {
                FormField(title: "Type") {
                    Picker("Type", selection: type.projectedValue) {
                        ForEach(types, id: \.self) { type in
                            Label(type, systemImage: IssueTypeStyle.symbol(for: type)).tag(type)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                FormField(title: "Priority") {
                    Picker("Priority", selection: priority.projectedValue) {
                        ForEach(0...4, id: \.self) { Text(DisplayText.priority($0)).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
            }
            FormField(title: "Parent") {
                Picker("Parent", selection: parent.projectedValue) {
                    Text("None").tag(IssueID?.none)
                    ForEach(parentChoices) { issue in
                        Text("\(issue.id.rawValue) — \(issue.title)").lineLimit(1).tag(IssueID?.some(issue.id))
                    }
                }
                .labelsHidden()
            }
            FormField(title: "Description") {
                ProseEditor(text: description.projectedValue, prompt: "What is this bead about?", minHeight: 140)
            }
            HStack {
                Text("Nothing is created until you review and confirm.")
                    .font(.caption)
                    .foregroundStyle(theme.secondaryText)
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Review…") {
                    model.propose(.create(NewIssue(
                        title: title.wrappedValue,
                        type: type.wrappedValue,
                        priority: priority.wrappedValue,
                        description: description.wrappedValue,
                        parent: parent.wrappedValue
                    )))
                }
                .keyboardShortcut(.defaultAction)
                .disabled(title.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 560)
        .background(theme.background)
        .onAppear { titleFocus.wrappedValue = true }
    }
}

extension View {
    /// Makes an issue draggable (as its id) only while editing is unlocked.
    @ViewBuilder
    func draggableIssue(_ id: IssueID, when enabled: Bool) -> some View {
        if enabled {
            draggable(IssueDragPayload.encode(id))
        } else {
            self
        }
    }
}

// MARK: Saving a view

/// Name and icon for a new view saved from what's on screen.
struct SaveAsNewViewSheet: View {
    @Bindable var model: WorkspaceModel
    @Bindable var ui: WorkspaceUI
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Save as New View")
                .font(.headline)
            Text("Keeps this view's filters, layout, grouping and ordering under a name of its own.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            TextField("Name", text: $ui.newViewName)
                .textFieldStyle(.roundedBorder)
                .onSubmit(save)
            IconGrid(selection: $ui.newViewSymbol)
            HStack {
                Spacer()
                Button("Cancel") { ui.showsSaveAsNewView = false }
                    .keyboardShortcut(.cancelAction)
                Button("Save", action: save)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 380)
        .background(theme.background)
    }

    private func save() {
        let name = ui.newViewName.trimmingCharacters(in: .whitespacesAndNewlines)
        model.saveAsNewView(name: name.isEmpty ? String(localized: "\(model.view.name) copy", comment: "Default name for a view saved from another") : name, symbol: ui.newViewSymbol)
        ui.showsSaveAsNewView = false
    }
}

/// A new icon for a user view.
struct ChangeIconSheet: View {
    let model: WorkspaceModel
    @Bindable var ui: WorkspaceUI
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Change Icon")
                .font(.headline)
            IconGrid(selection: $ui.chosenIcon)
            HStack {
                Spacer()
                Button("Cancel") { ui.changingIconOf = nil }
                    .keyboardShortcut(.cancelAction)
                Button {
                    if let id = ui.changingIconOf { model.setIcon(ui.chosenIcon, for: id) }
                    ui.changingIconOf = nil
                } label: {
                    Text("Change", comment: "Button that applies the chosen icon")
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 380)
        .background(theme.background)
    }
}

/// The user's icon set, with the current choice shown even when it came from outside the set
/// (an imported view can name any SF Symbol).
struct IconGrid: View {
    @Binding var selection: String
    @Environment(\.theme) private var theme

    private let columns = Array(repeating: GridItem(.fixed(40), spacing: 6), count: 7)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(ViewIcon.choices(including: selection), id: \.self) { symbol in
                Button {
                    selection = symbol
                } label: {
                    Image(systemName: symbol)
                        .font(.title3)
                        .frame(width: 40, height: 34)
                        .background(
                            RoundedRectangle(cornerRadius: 7)
                                .fill(symbol == selection ? theme.accent.opacity(0.25) : Color.clear)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 7)
                                .strokeBorder(symbol == selection ? theme.accent : Color.clear, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .help(symbol)
            }
        }
    }
}

