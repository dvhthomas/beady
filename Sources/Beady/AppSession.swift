import AppKit
import BeadsData
import BeadsPresentation
import Foundation
import Observation

/// Composition root: turns a folder into a wired-up WorkspaceModel and remembers recents.
@MainActor
@Observable
final class AppSession {
    private(set) var model: WorkspaceModel?
    private(set) var workspace: BeadsWorkspace?
    private(set) var openError: String?
    private(set) var recentPaths: [String]
    /// Panels, sheets and column layout, shared with the menu bar.
    let ui = WorkspaceUI()
    /// Appearance, themes and text size.
    let themes = ThemeStore()

    /// Reports bd's writes as they land, so the view refreshes without polling.
    @ObservationIgnored private var watcher: BDChangeWatcher?

    private static let recentsKey = "recentWorkspaces"

    /// `--workspace <path>` on the command line wins over the most recent workspace.
    init(arguments: [String] = CommandLine.arguments) {
        recentPaths = (UserDefaults.standard.stringArray(forKey: Self.recentsKey) ?? [])
            .filter { FileManager.default.fileExists(atPath: $0) }
        if let path = Self.value(of: "--workspace", in: arguments) ?? recentPaths.first {
            open(URL(fileURLWithPath: path))
        }
    }

    func open(_ url: URL) {
        do {
            // Everything that reads or writes beads goes through this one gateway.
            let gateway = try BDGateway.open(url)
            let store = BDStore(gateway: gateway)
            workspace = gateway.workspace
            model = WorkspaceModel(title: gateway.workspace.displayName, store: store)
            openError = nil
            watcher?.stop()
            // Passive FSEvents on bd's folder: every write rewrites issues.jsonl and appends to
            // the interaction log, so this fires within a moment of any agent's change.
            watcher = gateway.watchChanges { [weak self] in
                Task { @MainActor in await self?.model?.refreshIfChanged() }
            }
            remember(gateway.workspace.projectDirectory.path)
        } catch {
            openError = error.localizedDescription
            if let dataError = error as? BeadsDataError, case .notAWorkspace = dataError {
                forget(url.standardizedFileURL.path)
            }
        }
    }

    func dismissOpenError() {
        openError = nil
    }

    func close() {
        watcher?.stop()
        watcher = nil
        model = nil
        workspace = nil
    }

    func chooseWorkspace() {
        let panel = NSOpenPanel()
        panel.title = "Open Beads Workspace"
        panel.message = "Choose a project folder containing .beads, or the .beads folder itself."
        panel.prompt = "Open"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        if panel.runModal() == .OK, let url = panel.url {
            open(url)
        }
    }

    private func remember(_ path: String) {
        recentPaths = Array(([path] + recentPaths.filter { $0 != path }).prefix(8))
        UserDefaults.standard.set(recentPaths, forKey: Self.recentsKey)
    }

    private func forget(_ path: String) {
        recentPaths.removeAll { $0 == path }
        UserDefaults.standard.set(recentPaths, forKey: Self.recentsKey)
    }

    /// The one place a command turns into an action, whether it came from the palette, a menu
    /// or a key. Anything the app can do is in `AppCommand`, so nothing can be reachable one way
    /// and missing the other.
    func run(_ command: AppCommand) {
        ui.showsPalette = false
        switch command {
        case .openWorkspace: chooseWorkspace()
        case .closeWorkspace: close()
        case .refresh: if let model { Task { await model.load() } }
        case .newBead: if model?.canEdit == true { ui.showsNewBead = true }
        case .editSelected: model?.beginEditingSelection()
        case .focusSearch: ui.focusSearch()
        case .addFilter: ui.showsFilterMenu = true
        case .clearFilters:
            model?.clearFilters()
            model?.searchText = ""
        case .displayOptions: ui.showsDisplayOptions = true
        case .toggleDetails: ui.showsInspector.toggle()
        case .showShortcuts: ui.showsShortcuts = true
        case .showView(let source): model?.source = source
        case .setLayout(let layout): model?.layout = layout
        case .setGrouping(let grouping): model?.grouping = grouping
        case .setOrdering(let sort): model?.ordering = sort
        case .goToIssue(let id, _):
            model?.selection = id
            ui.showsInspector = true
        case .chooseTheme: ui.showsThemes = true
        case .setTheme(let name):
            // Choosing a theme also says which appearance you meant.
            if let theme = Theme.dark(named: name) {
                themes.darkThemeName = theme.name
                themes.appearance = .dark
            } else if let theme = Theme.light(named: name) {
                themes.lightThemeName = theme.name
                themes.appearance = .light
            }
        case .setAppearance(let appearance): themes.appearance = appearance
        case .setTextSize(let size): themes.textSize = size
        }
    }

    private static func value(of flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }
}
