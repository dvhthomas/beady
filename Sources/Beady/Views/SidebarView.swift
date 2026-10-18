import BeadsCore
import BeadsPresentation
import SwiftUI

/// Navigation only, as in Linear: views and nothing else. Filters live in each view's header,
/// and anything to do with one bead — including focusing on its subtree — happens in the main
/// panel. Each row carries its layout glyph, so you know before you click whether you're getting
/// a list, a board or a tree, and a dot when the view has unsaved changes.
struct SidebarView: View {
    let model: WorkspaceModel
    let ui: WorkspaceUI
    var run: (AppCommand) -> Void = { _ in }
    var importFiles: ([URL]) -> Void = { _ in }
    @Environment(\.theme) private var theme
    @Environment(\.sidebarStyle) private var style

    var body: some View {
        List(selection: selection) {
            ForEach(model.sidebarSections) { section in
                Section {
                    ForEach(section.entries) { entry in
                        row(entry)
                    }
                } header: {
                    header(section)
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

    @ViewBuilder
    private func header(_ section: SidebarSection) -> some View {
        if section.canAdd {
            HStack {
                Text(section.title)
                Spacer()
                Button {
                    ui.promptSaveAsNewView(suggesting: model.view.isBuiltIn ? "" : model.view.name)
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .help("Save the current view as a new view")
            }
        } else if !section.title.isEmpty {
            Text(section.title)
        }
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
            // The layout glyph says what you'll get; Starred keeps its star.
            Image(systemName: entry.id == .starred ? entry.symbol : DisplayText.layoutSymbol(entry.layout))
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
