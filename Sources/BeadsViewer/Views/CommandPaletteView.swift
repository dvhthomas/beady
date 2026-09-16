import BeadsCore
import BeadsPresentation
import SwiftUI

/// ⌘P: type a few letters to run any command or jump to a bead. Arrow keys move, Return runs,
/// Escape closes.
struct CommandPaletteView: View {
    let model: WorkspaceModel
    let run: (AppCommand) -> Void
    let onClose: () -> Void
    /// `State`/`FocusState` as plain DynamicProperties: Command Line Tools lack the @State macro.
    private var query = State(initialValue: "")
    private var highlighted = State(initialValue: 0)
    private var isFocused = FocusState<Bool>()

    init(model: WorkspaceModel, run: @escaping (AppCommand) -> Void, onClose: @escaping () -> Void) {
        self.model = model
        self.run = run
        self.onClose = onClose
    }

    var body: some View {
        let results = CommandCatalog.results(for: query.wrappedValue, model: model)
        VStack(spacing: 0) {
            TextField("Run a command or jump to a bead", text: query.projectedValue)
                .textFieldStyle(.plain)
                .font(.title3)
                .padding(14)
                .focused(isFocused.projectedValue)
                .onSubmit { activate(results) }
                .onKeyPress(.downArrow) { move(1, in: results) }
                .onKeyPress(.upArrow) { move(-1, in: results) }
                .onKeyPress(.escape) {
                    onClose()
                    return .handled
                }
                .onChange(of: query.wrappedValue) { highlighted.wrappedValue = 0 }
            Divider()
            if results.isEmpty {
                Text("Nothing matches “\(query.wrappedValue)”")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                list(results)
            }
        }
        .frame(width: 580, height: 420)
        .onAppear { isFocused.wrappedValue = true }
    }

    private func list(_ results: [AppCommand]) -> some View {
        ScrollViewReader { scroller in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(results.enumerated()), id: \.element.id) { index, command in
                        row(command, isHighlighted: index == highlighted.wrappedValue)
                            .id(index)
                            .contentShape(Rectangle())
                            .onTapGesture { run(command) }
                    }
                }
                .padding(6)
            }
            .onChange(of: highlighted.wrappedValue) { scroller.scrollTo(highlighted.wrappedValue) }
        }
    }

    private func row(_ command: AppCommand, isHighlighted: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: command.isGoToIssue ? "circle.hexagongrid" : "command")
                .foregroundStyle(.secondary)
                .frame(width: 18)
            Text(command.title)
                .lineLimit(1)
            Spacer(minLength: 12)
            if let shortcut = command.shortcut {
                Text(shortcut)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            Text(command.group)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(isHighlighted ? Color.accentColor.opacity(0.22) : .clear, in: RoundedRectangle(cornerRadius: 6))
    }

    private func move(_ delta: Int, in results: [AppCommand]) -> KeyPress.Result {
        guard !results.isEmpty else { return .handled }
        highlighted.wrappedValue = (highlighted.wrappedValue + delta + results.count) % results.count
        return .handled
    }

    private func activate(_ results: [AppCommand]) {
        guard results.indices.contains(highlighted.wrappedValue) else { return }
        run(results[highlighted.wrappedValue])
    }
}

/// The `?` sheet: every command, where it lives, and the key that runs it.
struct ShortcutsView: View {
    let model: WorkspaceModel
    let onClose: () -> Void

    var body: some View {
        let groups = Dictionary(grouping: CommandCatalog.all(for: model).filter { $0.shortcut != nil }, by: \.group)
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Keyboard Shortcuts").font(.headline)
                Spacer()
                Button("Done", action: onClose)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(14)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(groups.keys.sorted(), id: \.self) { group in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(group)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                            ForEach(groups[group] ?? []) { command in
                                HStack {
                                    Text(command.title)
                                    Spacer(minLength: 24)
                                    Text(command.shortcut ?? "")
                                        .font(.callout.monospaced())
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    Text("⌘P opens the command palette, where everything else lives.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(16)
            }
        }
        .frame(width: 460, height: 460)
    }
}


extension KeyBinding {
    var keyboardShortcut: KeyboardShortcut {
        var modifiers: EventModifiers = []
        if self.modifiers.contains(.command) { modifiers.insert(.command) }
        if self.modifiers.contains(.shift) { modifiers.insert(.shift) }
        if self.modifiers.contains(.option) { modifiers.insert(.option) }
        return KeyboardShortcut(KeyEquivalent(key), modifiers: modifiers)
    }
}

extension AppCommand {
    /// The ⌘ key for the menu bar, which keeps working while a field has the keyboard.
    var menuShortcut: KeyboardShortcut? {
        bindings.first { !$0.isPlainKey }?.keyboardShortcut
    }

    /// The bare key for a button in the window, or nil if this command has none.
    var plainShortcut: KeyboardShortcut? {
        bindings.first(where: \.isPlainKey)?.keyboardShortcut
    }
}
