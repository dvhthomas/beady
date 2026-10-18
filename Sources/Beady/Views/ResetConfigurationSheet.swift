import BeadsPresentation
import SwiftUI

/// What Reset Configuration will remove, with counts, the same commands for Terminal, and the
/// one choice: whether the saved views go too. In the style of the change sheet.
struct ResetConfigurationSheet: View {
    @Environment(\.theme) private var theme
    let inventory: ConfigurationInventory
    let onExport: () -> Void
    let onReset: (_ deletingLibrary: Bool) -> Void
    let onCancel: () -> Void
    /// `State` as a plain DynamicProperty: Command Line Tools lack the @State macro plugin.
    private var deleteLibrary = State(initialValue: false)

    init(inventory: ConfigurationInventory, onExport: @escaping () -> Void, onReset: @escaping (Bool) -> Void, onCancel: @escaping () -> Void) {
        self.inventory = inventory
        self.onExport = onExport
        self.onReset = onReset
        self.onCancel = onCancel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Reset Configuration")
                    .font(.title3.weight(.semibold))
                Text("Removes Beady's own settings on this Mac, like a fresh install. Beady returns to its welcome screen; no relaunch is needed.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            box("What goes") {
                if inventory.isEmpty {
                    Text("Nothing is stored yet.").foregroundStyle(.secondary)
                }
                ForEach(inventory.lines) { line in
                    HStack {
                        Text(line.title)
                        Spacer()
                        Text(line.detail).foregroundStyle(.secondary)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Toggle("Also delete my saved views (\(inventory.libraryViews) in the Library)", isOn: deleteLibrary.projectedValue)
                    .disabled(inventory.libraryViews == 0)
                HStack(spacing: 10) {
                    Button("Export them first…", action: onExport)
                        .disabled(inventory.libraryViews == 0)
                    Text("Writes one .beadyviews file you can import later.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            box("The same from Terminal") {
                ForEach(inventory.commands(deletingLibrary: deleteLibrary.wrappedValue), id: \.self) { command in
                    Text(command)
                        .font(.callout.monospaced())
                        .textSelection(.enabled)
                }
            }

            Text(ConfigurationInventory.leavesAlone)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Reset", role: .destructive) { onReset(deleteLibrary.wrappedValue) }
            }
        }
        .padding(20)
        .frame(width: 580)
        .background(theme.background)
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
