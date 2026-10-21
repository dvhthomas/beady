import BeadsCore
import BeadsPresentation
import SwiftUI

/// Navigation only, as in Linear: views and nothing else. Filters live in each view's header,
/// and anything to do with one bead — including focusing on its subtree — happens in the main
/// panel. Each row carries the view's own icon (never the layout glyph: the header's switcher
/// owns those) and a dot when the view has unsaved changes.
struct SidebarView: View {
    let model: WorkspaceModel
    let ui: WorkspaceUI
    var run: (AppCommand) -> Void = { _ in }
    var importFiles: ([URL]) -> Void = { _ in }
    @Environment(\.theme) private var theme
    @Environment(\.sidebarStyle) private var style

    /// Sections the user has folded, by kind; the rest are open. Remembered like the rest of the
    /// sidebar's state.
    @AppStorage("collapsedSidebarSections") private var collapsedSections = ""

    var body: some View {
        // Plain rows rather than List sections: a sidebar Section's header grows a hover-only
        // disclosure control at its trailing edge, which shoved the + aside just as the pointer
        // reached it. Drawing the header ourselves keeps the + and the chevron where they are.
        List(selection: selection) {
            ForEach(model.sidebarSections) { section in
                if !section.title.isEmpty {
                    header(section)
                }
                if isExpanded(section) {
                    ForEach(section.entries) { entry in
                        row(entry)
                    }
                }
            }
        }
        // Themed: one coherent window. Translucent: macOS's own material, which no theme can
        // reproduce because it samples what's behind the window.
        .scrollContentBackground(style == .themed ? .hidden : .automatic)
        .background(style == .themed ? AnyShapeStyle(theme.surface) : AnyShapeStyle(.clear))
        // A .beadyview dropped anywhere on the sidebar lands under My Views.
        .dropDestination(for: URL.self) { urls, _ in
            let files = urls.filter { [ViewLibrary.fileExtension, ViewLibrary.bundleExtension].contains($0.pathExtension.lowercased()) }
            guard !files.isEmpty else { return false }
            importFiles(files)
            return true
        }
    }

    /// Title, then the + where the section takes one, then the disclosure: both at a fixed size,
    /// always drawn, so nothing moves under the pointer. The disclosure is disabled, not hidden,
    /// when there is nothing to fold away.
    private func header(_ section: SidebarSection) -> some View {
        HStack(spacing: 2) {
            Text(section.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            if section.canAdd {
                Button {
                    ui.promptSaveAsNewView(suggesting: model.view.isBuiltIn ? "" : model.view.name)
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .help("Save the current view as a new view")
            }
            Button {
                setExpanded(!isExpanded(section), section)
            } label: {
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .rotationEffect(.degrees(isExpanded(section) ? 0 : -90))
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .disabled(!section.canCollapse)
            .help(disclosureHelp(section))
        }
        .padding(.top, section.kind == .views ? 0 : 10)
        .selectionDisabled()
        .listRowSeparator(.hidden)
    }

    private func disclosureHelp(_ section: SidebarSection) -> String {
        guard section.canCollapse else { return String(localized: "Nothing to hide", comment: "Tooltip on a sidebar section's disclosure") }
        return isExpanded(section)
            ? String(localized: "Hide", comment: "Tooltip on a sidebar section's disclosure")
            : String(localized: "Show", comment: "Tooltip on a sidebar section's disclosure")
    }

    private func isExpanded(_ section: SidebarSection) -> Bool {
        !collapsedKinds.contains(section.kind.rawValue)
    }

    private func setExpanded(_ expanded: Bool, _ section: SidebarSection) {
        var kinds = collapsedKinds
        if expanded { kinds.remove(section.kind.rawValue) } else { kinds.insert(section.kind.rawValue) }
        collapsedSections = kinds.sorted().joined(separator: ",")
    }

    private var collapsedKinds: Set<String> {
        Set(collapsedSections.split(separator: ",").map(String.init))
    }

    private func row(_ entry: SidebarEntry) -> some View {
        Label {
            HStack(spacing: 5) {
                Text(entry.title)
                if entry.isModified {
                    Circle()
                        .fill(theme.accent)
                        .frame(width: 6, height: 6)
                        .help("Unsaved changes")
                }
            }
        } icon: {
            Image(systemName: entry.symbol)
        }
        .badge(entry.count)
        .tag(entry.id)
        .help(entry.help)
        .contextMenu {
            if entry.isBuiltIn {
                // A built-in is locked; a copy is how you get a variation of it.
                Button("Duplicate") { model.duplicateView(entry.id) }
            } else if let view = model.views.first(where: { $0.id == entry.id }) {
                Button("Rename…") { ui.promptRename(view) }
                Button("Change Icon…") { ui.promptChangeIcon(of: view) }
                Button("Duplicate") { model.duplicateView(entry.id) }
                Divider()
                Button("Export…") { run(.exportView(entry.id)) }
                if let file = exportFile(for: view) {
                    ShareLink(item: file) { Label("Share…", systemImage: "square.and.arrow.up") }
                }
                Divider()
                Button("Delete", role: .destructive) { model.removeView(entry.id) }
            }
        }
    }

    /// The view as a file in a scratch folder, for the share sheet, which wants a URL. Written
    /// when the menu opens; a share that never happens costs one tiny file.
    private func exportFile(for view: IssueView) -> URL? {
        guard let data = try? view.documentData() else { return nil }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Beady views", isDirectory: true)
        let url = folder.appendingPathComponent(view.exportFilename)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    private var selection: Binding<IssueView.ID?> {
        Binding(get: { model.viewID }, set: { if let id = $0 { model.viewID = id } })
    }
}
