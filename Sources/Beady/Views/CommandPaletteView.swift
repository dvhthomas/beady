import AppKit
import BeadsCore
import BeadsPresentation
import SwiftUI

/// ⌘P: type a few letters to run any command or jump to a bead. Arrow keys move, Return runs,
/// Escape closes.
struct CommandPaletteView: View {
    @Environment(\.theme) private var theme
    let model: WorkspaceModel
    let run: (AppCommand) -> Void
    let onClose: () -> Void
    /// `State`/`FocusState` as plain DynamicProperties: Command Line Tools lack the @State macro.
    private var query = State(initialValue: "")
    private var highlighted = State(initialValue: 0)
    private var isFocused = FocusState<Bool>()
    /// The key monitor, kept alive while the palette is open.
    private var monitor = State<Any?>(initialValue: nil)

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
        .onAppear {
            isFocused.wrappedValue = true
            startWatchingKeys()
        }
        .onDisappear(perform: stopWatchingKeys)
    }

    /// Arrow keys, Return and Escape come through a local event monitor rather than
    /// `onKeyPress`: the text field's editor takes arrows first to move the caret, so a key
    /// handler on the field never sees them.
    private func startWatchingKeys() {
        guard monitor.wrappedValue == nil else { return }
        let query = query.projectedValue
        let highlighted = highlighted.projectedValue
        let model = model
        let run = run
        let onClose = onClose
        // The monitor is delivered on the main thread; NSEvent isn't Sendable, so the handler
        // keeps it local rather than capturing it anywhere.
        monitor.wrappedValue = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { @MainActor event in
            let results = CommandCatalog.results(for: query.wrappedValue, model: model)
            func move(_ delta: Int) {
                guard !results.isEmpty else { return }
                highlighted.wrappedValue = (highlighted.wrappedValue + delta + results.count) % results.count
            }
            switch event.keyCode {
            case 126: // up
                move(-1)
                return nil
            case 125: // down
                move(1)
                return nil
            case 36, 76: // return, enter
                if results.indices.contains(highlighted.wrappedValue) {
                    run(results[highlighted.wrappedValue])
                }
                return nil
            case 53: // escape
                onClose()
                return nil
            default:
                return event
            }
        }
    }

    private func stopWatchingKeys() {
        if let monitor = monitor.wrappedValue { NSEvent.removeMonitor(monitor) }
        monitor.wrappedValue = nil
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
        .background(isHighlighted ? theme.accent.opacity(0.22) : .clear, in: RoundedRectangle(cornerRadius: 6))
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
