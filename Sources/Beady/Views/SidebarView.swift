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
            WorkspaceSwitcher(model: model, ui: ui, run: run)
                .selectionDisabled()
                .listRowSeparator(.hidden)
            ForEach(model.sidebarSections) { section in
                if !section.title.isEmpty {
                    header(section)
                        .background(dropTarget(section.dropTier))
                }
                if isExpanded(section) {
                    ForEach(section.entries) { entry in
                        row(entry)
                            .background(dropTarget(section.dropTier))
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
        .padding(.top, section.kind == .views ? 4 : 10)
        .selectionDisabled()
        .listRowSeparator(.hidden)
        .help(section.kind == .workspace ? Text("Views kept in this workspace's .beads/beady/views, for everyone who opens it; drag a view here to share it") : Text(verbatim: ""))
    }

    /// A view dragged from the other tier lands here: the file moves with it.
    @ViewBuilder
    private func dropTarget(_ tier: ViewTier?) -> some View {
        if let tier {
            Color.clear.dropDestination(for: String.self) { items, _ in
                guard let id = ViewDragPayload.decode(items) else { return false }
                return model.moveView(id, to: tier)
            }
        }
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
        .draggableView(entry.id, when: !entry.isBuiltIn)
        .contextMenu {
            if entry.isBuiltIn {
                // A built-in is locked; a copy is how you get a variation of it.
                Button("Duplicate") { model.duplicateView(entry.id) }
                Divider()
                Button(AppCommand.copyAsBDCommand(entry.id).title) { run(.copyAsBDCommand(entry.id)) }
            } else if let view = model.views.first(where: { $0.id == entry.id }) {
                Button("Rename…") { ui.promptRename(view) }
                Button("Change Icon…") { ui.promptChangeIcon(of: view) }
                Button("Duplicate") { model.duplicateView(entry.id) }
                if model.canShareViews {
                    Divider()
                    if entry.tier == .workspace {
                        Button("Move to My Views") { model.moveView(entry.id, to: .library) }
                    } else {
                        Button("Move to This Workspace") { model.moveView(entry.id, to: .workspace) }
                    }
                }
                Divider()
                Button("Export…") { run(.exportView(entry.id)) }
                if let file = exportFile(for: view) {
                    ShareLink(item: file) { Label("Share…", systemImage: "square.and.arrow.up") }
                }
                Button(AppCommand.copyAsBDCommand(entry.id).title) { run(.copyAsBDCommand(entry.id)) }
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

extension View {
    /// Makes a sidebar row draggable as its view, so it can be dropped on the other tier.
    @ViewBuilder
    func draggableView(_ id: IssueView.ID, when enabled: Bool) -> some View {
        if enabled {
            draggable(ViewDragPayload.encode(id))
        } else {
            self
        }
    }
}

/// The top of the sidebar: which database this is, and a way to another one. Clicking opens
/// the eight recents in File › Open Recent's order, each with its path (two checkouts of one
/// project differ only there) and the bd prefix Beady has seen in it, then Open Other….
/// Switching swaps the model in place, as opening always has; the Library's views stay, the
/// counts change.
struct WorkspaceSwitcher: View {
    let model: WorkspaceModel
    let ui: WorkspaceUI
    let run: (AppCommand) -> Void
    @Environment(\.theme) private var theme
    /// `State` as a plain DynamicProperty: Command Line Tools lack the @State macro plugin.
    private var showsList = State(initialValue: false)

    init(model: WorkspaceModel, ui: WorkspaceUI, run: @escaping (AppCommand) -> Void) {
        self.model = model
        self.ui = ui
        self.run = run
    }

    var body: some View {
        Button {
            showsList.wrappedValue = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "cylinder.split.1x2")
                    .foregroundStyle(theme.accent)
                Text(model.title)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let prefix = model.issuePrefix {
                    PrefixBadge(prefix: prefix)
                        .help("The issue prefix bd uses in this workspace")
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Switch workspace (⌃⌘O cycles the recent ones)")
        .padding(.bottom, 6)
        .popover(isPresented: showsList.projectedValue, arrowEdge: .bottom) {
            WorkspaceList(workspaces: ui.recentWorkspaces, current: ui.currentWorkspacePath) { command in
                showsList.wrappedValue = false
                run(command)
            }
        }
    }
}

/// What the switcher opens: the recents, the current one ticked, and Open Other….
struct WorkspaceList: View {
    let workspaces: [RecentWorkspace]
    let current: String?
    let run: (AppCommand) -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(workspaces) { workspace in
                let isCurrent = workspace.path == current
                Button {
                    run(.switchWorkspace(path: workspace.path))
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: isCurrent ? "checkmark" : "folder")
                            .frame(width: 16)
                            .foregroundStyle(isCurrent ? theme.accent : theme.secondaryText)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(workspace.name)
                                .lineLimit(1)
                            Text(workspace.path)
                                .font(.caption)
                                .foregroundStyle(theme.secondaryText)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer(minLength: 8)
                        if let prefix = workspace.prefix {
                            PrefixBadge(prefix: prefix)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(isCurrent)
                .help(workspace.path)
            }
            if !workspaces.isEmpty { Divider().padding(.vertical, 4) }
            Button {
                run(.openWorkspace)
            } label: {
                Label(AppCommand.openWorkspace.title, systemImage: "ellipsis.circle")
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
        .frame(width: 340)
        .background(theme.background)
    }
}

/// The issue prefix bd uses in a workspace, as a small capsule.
struct PrefixBadge: View {
    let prefix: String
    @Environment(\.theme) private var theme

    var body: some View {
        Text(prefix)
            .font(.caption.monospaced())
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(theme.accent.opacity(0.18), in: Capsule())
    }
}
