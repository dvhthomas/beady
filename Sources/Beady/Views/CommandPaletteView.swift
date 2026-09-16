import AppKit
import BeadsCore
import BeadsPresentation
import SwiftUI

/// ⌘P: type a few letters to run any command or jump to a bead. Arrow keys move, Return runs,
/// Escape closes.
struct CommandPaletteView: View {
    @Environment(\.theme) private var theme
    let model: WorkspaceModel
    /// Query and highlight live in the shared UI state, not in view storage: see WorkspaceUI.
    let ui: WorkspaceUI
    let run: (AppCommand) -> Void
    let onClose: () -> Void
    /// `FocusState` as a plain DynamicProperty: Command Line Tools lack the @State macro plugin.
    private var isFocused = FocusState<Bool>()
    private var monitor = State<Any?>(initialValue: nil)

    init(model: WorkspaceModel, ui: WorkspaceUI, run: @escaping (AppCommand) -> Void, onClose: @escaping () -> Void) {
        self.model = model
        self.ui = ui
        self.run = run
        self.onClose = onClose
    }

    var body: some View {
        let results = CommandCatalog.results(for: ui.paletteQuery, model: model)
        VStack(spacing: 0) {
            TextField("Run a command or jump to a bead", text: query)
                .textFieldStyle(.plain)
                .font(.title3)
                .padding(14)
                .focused(isFocused.projectedValue)
            Divider()
            if results.isEmpty {
                VStack(spacing: 6) {
                    Text("Nothing matches “\(ui.paletteQuery)”")
                        .foregroundStyle(theme.secondaryText)
                    Text("Backspace to widen the search, or Escape to close.")
                        .font(.caption)
                        .foregroundStyle(theme.secondaryText)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                list(results)
            }
        }
        .frame(width: 580, height: 420)
        .background(theme.background)
        .onAppear {
            isFocused.wrappedValue = true
            startWatchingKeys()
        }
        .onDisappear(perform: stopWatchingKeys)
    }

    /// Typing resets the highlight, so Return always runs the best match rather than whatever
    /// happened to be highlighted for the previous query.
    private var query: Binding<String> {
        Binding(
            get: { ui.paletteQuery },
            set: {
                ui.paletteQuery = $0
                ui.paletteHighlight = 0
            }
        )
    }

    private func list(_ results: [AppCommand]) -> some View {
        ScrollViewReader { scroller in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(results.enumerated()), id: \.element.id) { index, command in
                        row(command, isHighlighted: index == ui.paletteHighlight)
                            .id(index)
                            .contentShape(Rectangle())
                            .onTapGesture { run(command) }
                    }
                }
                .padding(6)
            }
            .onChange(of: ui.paletteHighlight) { scroller.scrollTo(ui.paletteHighlight) }
        }
    }

    private func row(_ command: AppCommand, isHighlighted: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: command.isGoToIssue ? "circle.hexagongrid" : "command")
                .foregroundStyle(theme.secondaryText)
                .frame(width: 18)
            Text(command.title)
                .lineLimit(1)
            Spacer(minLength: 12)
            if let shortcut = command.shortcut {
                Text(shortcut)
                    .font(.caption.monospaced())
                    .foregroundStyle(theme.secondaryText)
            }
            Text(command.group)
                .font(.caption)
                .foregroundStyle(theme.secondaryText)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(isHighlighted ? theme.selection : .clear, in: RoundedRectangle(cornerRadius: 6))
    }

    /// Arrow keys, Return and Escape come through a local event monitor: the text field's editor
    /// takes arrows first, so a key handler on the field never sees them.
    private func startWatchingKeys() {
        guard monitor.wrappedValue == nil else { return }
        let ui = ui
        let model = model
        let run = run
        let onClose = onClose
        monitor.wrappedValue = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { @MainActor event in
            let results = CommandCatalog.results(for: ui.paletteQuery, model: model)
            switch event.keyCode {
            case 126, 125: // up, down
                // With nothing to move through, let the field have the key rather than eating it.
                guard !results.isEmpty else { return event }
                let delta = event.keyCode == 126 ? -1 : 1
                ui.paletteHighlight = (ui.paletteHighlight + delta + results.count) % results.count
                return nil
            case 36, 76: // return, enter
                guard results.indices.contains(ui.paletteHighlight) else { return event }
                run(results[ui.paletteHighlight])
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
