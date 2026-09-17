import BeadsCore
import BeadsPresentation
import SwiftUI

/// Editing a bead, with a control for each thing bd can actually set.
///
/// The draft lives in the model, so a background refresh can't overwrite what's being typed and
/// nothing depends on view-local storage. Status and parent keep their own buttons: bd treats
/// them as different writes (closing wants a reason, reparenting checks for loops), and mixing
/// them into this form would hide that.
struct EditBeadForm: View {
    @Environment(\.theme) private var theme
    @Bindable var model: WorkspaceModel
    let draft: Binding<EditDraft>
    let onCancel: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                titleField
                HStack(alignment: .top, spacing: 16) {
                    typeField
                    priorityField
                }
                assigneeField
                labelsField
                blockersField
                textField("Description", draft.description, prompt: "What is this bead about?")
                textField("Notes", draft.notes, prompt: "Anything worth knowing while working on it")
                footer
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(theme.background)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(draft.wrappedValue.id.rawValue)
                .font(.callout.monospaced())
                .foregroundStyle(theme.secondaryText)
            Spacer()
            statusAndParent
        }
    }

    /// The two changes that aren't part of an edit, kept within reach.
    private var statusAndParent: some View {
        HStack(spacing: 8) {
            Menu {
                ForEach(model.knownStatuses, id: \.self) { status in
                    Button(DisplayText.status(status)) {
                        model.proposeStatus(draft.wrappedValue.id, to: status)
                    }
                    .disabled(status == draft.wrappedValue.original.status)
                }
            } label: {
                Label(DisplayText.status(draft.wrappedValue.original.status), systemImage: "circle.lefthalf.filled")
            }
            .help("Status is its own change: closing asks for a reason")

            Menu {
                Button("No Parent") { model.proposeParent(draft.wrappedValue.id, to: nil) }
                    .disabled(draft.wrappedValue.original.parentID == nil)
                Divider()
                ForEach(model.parentChoices(for: draft.wrappedValue.id)) { parent in
                    Button("\(parent.id.rawValue) — \(parent.title)") {
                        model.proposeParent(draft.wrappedValue.id, to: parent.id)
                    }
                }
            } label: {
                Label("Parent", systemImage: "arrow.turn.down.right")
            }
            .help("Moving a bead is its own change: bd checks for loops")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .controlSize(.small)
    }

    private var titleField: some View {
        field("Title") {
            TextField("Title", text: draft.title)
                .textFieldStyle(.roundedBorder)
                .font(.title3)
                .labelsHidden()
        }
    }

    private var typeField: some View {
        field("Type") {
            Picker("Type", selection: draft.type) {
                ForEach(model.knownTypes, id: \.self) { type in
                    Label(type, systemImage: IssueTypeStyle.symbol(for: type)).tag(type)
                }
            }
            .labelsHidden()
            .fixedSize()
        }
    }

    private var priorityField: some View {
        field("Priority") {
            Picker("Priority", selection: draft.priority) {
                ForEach(0...4, id: \.self) { Text(DisplayText.priority($0)).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
        }
    }

    private var assigneeField: some View {
        field("Assignee") {
            HStack(spacing: 8) {
                TextField("Unassigned", text: draft.assignee)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 260)
                if !model.knownAssignees.isEmpty {
                    Menu {
                        ForEach(model.knownAssignees, id: \.self) { person in
                            Button(person) { draft.wrappedValue.assignee = person }
                        }
                        Divider()
                        Button("Unassigned") { draft.wrappedValue.assignee = "" }
                    } label: {
                        Image(systemName: "person.crop.circle")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .help("Someone already working in this database")
                }
            }
        }
    }

    private var labelsField: some View {
        field("Labels") {
            VStack(alignment: .leading, spacing: 8) {
                if draft.wrappedValue.labels.isEmpty {
                    Text("None")
                        .font(.callout)
                        .foregroundStyle(theme.secondaryText)
                } else {
                    // A wrapping row of chips: labels are short, and there are rarely many.
                    HStack(spacing: 6) {
                        ForEach(draft.wrappedValue.labels, id: \.self) { label in
                            chip(label)
                        }
                    }
                }
                HStack(spacing: 8) {
                    LabelEntry { draft.wrappedValue.addLabel($0) }
                    let offered = draft.wrappedValue.labelsToOffer(from: model.knownLabels)
                    if !offered.isEmpty {
                        Menu {
                            ForEach(offered, id: \.self) { label in
                                Button(label) { draft.wrappedValue.addLabel(label) }
                            }
                        } label: {
                            Label("Existing", systemImage: "tag")
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                        .help("Labels this database already uses")
                    }
                }
            }
        }
    }

    /// Blockers are dependencies, not fields, so each change here is its own confirmation —
    /// which is right: rewiring the graph deserves more ceremony than typing a title.
    private var blockersField: some View {
        let issue = draft.wrappedValue.original
        let blockers = model.snapshot?.blockers(of: issue) ?? []
        let choices = model.blockerChoices(for: issue.id)
        return field("Blocked by") {
            VStack(alignment: .leading, spacing: 6) {
                if blockers.isEmpty {
                    Text("Nothing")
                        .font(.callout)
                        .foregroundStyle(theme.secondaryText)
                }
                ForEach(blockers) { blocker in
                    HStack(spacing: 6) {
                        Image(systemName: (model.snapshot?.category(of: blocker) ?? .active).symbolName)
                            .foregroundStyle(theme.color(model.snapshot?.category(of: blocker) ?? .active))
                        Text(blocker.id.rawValue)
                            .font(.caption.monospaced())
                            .foregroundStyle(theme.secondaryText)
                        Text(blocker.title)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Button {
                            model.proposeBlocker(issue.id, blocker: blocker.id, on: false)
                        } label: {
                            Image(systemName: "xmark.circle")
                        }
                        .buttonStyle(.plain)
                        .help("Stop waiting for \(blocker.id)")
                    }
                    .font(.callout)
                }
                if !choices.isEmpty {
                    Menu {
                        ForEach(choices.prefix(50)) { candidate in
                            Button("\(candidate.id.rawValue) — \(candidate.title)") {
                                model.proposeBlocker(issue.id, blocker: candidate.id, on: true)
                            }
                        }
                    } label: {
                        Label("Wait for another bead", systemImage: "plus.circle")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .help("Beads that could block this one, minus anything that would make a loop")
                }
            }
        }
    }

    private func chip(_ label: String) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.caption)
            Button {
                draft.wrappedValue.removeLabel(label)
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2)
            }
            .buttonStyle(.plain)
            .help("Remove “\(label)”")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(theme.surface, in: Capsule())
        .overlay(Capsule().strokeBorder(theme.border))
    }

    private func textField(_ title: String, _ text: Binding<String>, prompt: String) -> some View {
        field(title) {
            TextEditor(text: text)
                .font(.body)
                .scrollContentBackground(.hidden)
                .padding(6)
                .frame(minHeight: title == "Description" ? 140 : 90)
                .background(theme.surface, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(theme.border))
                .overlay(alignment: .topLeading) {
                    if text.wrappedValue.isEmpty {
                        Text(prompt)
                            .foregroundStyle(theme.secondaryText)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 14)
                            .allowsHitTesting(false)
                    }
                }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Review Changes…") { model.reviewDraft() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!draft.wrappedValue.hasChanges)
            }
            Text(summary)
                .font(.caption)
                .foregroundStyle(theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Says what would be written, so Review Changes isn't a leap.
    private var summary: String {
        guard case .edit(_, let edit)? = draft.wrappedValue.change else {
            return "Nothing changed yet. Only the fields you touch are sent."
        }
        var parts: [String] = []
        if edit.title != nil { parts.append("title") }
        if edit.type != nil { parts.append("type") }
        if edit.priority != nil { parts.append("priority") }
        if edit.assignee != nil { parts.append("assignee") }
        if !edit.addedLabels.isEmpty { parts.append("+\(edit.addedLabels.sorted().joined(separator: ", +"))") }
        if !edit.removedLabels.isEmpty { parts.append("−\(edit.removedLabels.sorted().joined(separator: ", −"))") }
        if edit.description != nil { parts.append("description") }
        if edit.notes != nil { parts.append("notes") }
        return "Will change \(parts.joined(separator: ", ")). Nothing is written until you confirm."
    }

    private func field(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(theme.secondaryText)
            content()
        }
    }
}

/// Typing a label that doesn't exist yet. Its own view so the text it holds is its own business.
private struct LabelEntry: View {
    let add: (String) -> Void
    private var text = State(initialValue: "")

    init(add: @escaping (String) -> Void) {
        self.add = add
    }

    var body: some View {
        TextField("Add a label", text: text.projectedValue)
            .textFieldStyle(.roundedBorder)
            .frame(maxWidth: 180)
            .onSubmit {
                add(text.wrappedValue)
                text.wrappedValue = ""
            }
    }
}
