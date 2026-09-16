import BeadsCore
import BeadsPresentation
import SwiftUI

/// Shown before any write: what changes, problems, the exact bd commands, and the outcome.
struct ChangeConfirmationView: View {
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

            box("Change") {
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
                            .foregroundStyle(isError ? Color.red : Color.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            if pending.asksForReason {
                TextField("Reason (stored by bd)", text: $model.pendingReason)
                    .textFieldStyle(.roundedBorder)
            }

            box("bd will run") {
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
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let failure = pending.failure {
                Label(failure, systemImage: "xmark.octagon.fill")
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                if pending.isApplying {
                    ProgressView().controlSize(.small)
                    Text("Writing and verifying…").foregroundStyle(.secondary)
                }
                Spacer()
                Button(pending.failure == nil ? "Cancel" : "Close", action: onCancel)
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

    private func box<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            VStack(alignment: .leading, spacing: 4, content: content)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        }
    }
}

struct NewBeadForm: View {
    let model: WorkspaceModel
    let onCancel: () -> Void
    /// `State` as plain DynamicProperties: Command Line Tools lack the @State macro plugin.
    private var title = State(initialValue: "")
    private var type = State(initialValue: "task")
    private var priority = State(initialValue: 2)
    private var parent: State<IssueID?>
    private var description = State(initialValue: "")

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
        VStack(alignment: .leading, spacing: 12) {
            Text("New Bead").font(.title3.weight(.semibold))
            Form {
                TextField("Title", text: title.projectedValue)
                Picker("Type", selection: type.projectedValue) {
                    ForEach(types, id: \.self) { Text($0).tag($0) }
                }
                Picker("Priority", selection: priority.projectedValue) {
                    ForEach(0...4, id: \.self) { Text(DisplayText.priority($0)).tag($0) }
                }
                Picker("Parent", selection: parent.projectedValue) {
                    Text("None").tag(IssueID?.none)
                    ForEach(parentChoices) { issue in
                        Text("\(issue.id.rawValue) — \(issue.title)").lineLimit(1).tag(IssueID?.some(issue.id))
                    }
                }
                LabeledContent("Description") {
                    TextEditor(text: description.projectedValue)
                        .font(.body)
                        .frame(minHeight: 110)
                }
            }
            .formStyle(.grouped)
            HStack {
                Text("Nothing is created until you review and confirm.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
