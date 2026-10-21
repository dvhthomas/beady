import AppKit
import BeadsCore
import BeadsData
import BeadsPresentation
import Foundation
import Observation
import UniformTypeIdentifiers

extension UTType {
    /// Declared in the bundle's Info.plist (scripts/bundle.sh) so Finder opens the files with
    /// Beady; the fallback keeps the bare SwiftPM binary working.
    static let beadyView = UTType("me.bitsby.beady.view") ?? UTType(filenameExtension: ViewLibrary.fileExtension) ?? .json
    static let beadyViews = UTType("me.bitsby.beady.views") ?? UTType(filenameExtension: ViewLibrary.bundleExtension) ?? .json
}

/// What the Create Database alert shows: the plan, and the exact command line it will run.
struct NewDatabaseOffer {
    let plan: NewDatabasePlan
    let command: String
}

/// Composition root: turns a folder into a wired-up WorkspaceModel and remembers recents.
@MainActor
@Observable
final class AppSession {
    private(set) var model: WorkspaceModel?
    private(set) var workspace: BeadsWorkspace?
    private(set) var openError: String?
    private(set) var recentPaths: [String]
    /// A git repository without a database, waiting for the user's yes or no.
    private(set) var databaseOffer: NewDatabaseOffer?
    /// True while bd is making a database the user said yes to.
    private(set) var isCreatingDatabase = false
    /// The setting: turn bd's change journal on in workspaces that don't have it. On by default;
    /// nil preferences (the offscreen snapshots) mean nothing is ever written.
    var turnsOnJournal: Bool {
        didSet { preferences?.set(turnsOnJournal, forKey: Self.turnsOnJournalKey) }
    }
    /// The language Beady is shown in, or nil for the system's. Stored under the key macOS
    /// itself reads for a per-app language, so this and System Settings can't disagree; bundles
    /// follow it from the next launch.
    var language: String? {
        didSet {
            guard let preferences else { return }
            if let stored = LanguageSetting.stored(for: language) {
                preferences.set(stored, forKey: LanguageSetting.key)
            } else {
                preferences.removeObject(forKey: LanguageSetting.key)
            }
        }
    }
    /// What this process launched with: when `language` differs, a relaunch is what applies it.
    private let languageAtLaunch: String?
    /// Panels, sheets and column layout, shared with the menu bar.
    let ui = WorkspaceUI()
    /// Appearance, themes and text size.
    let themes = ThemeStore()

    /// Reports bd's writes as they land, so the view refreshes without polling.
    @ObservationIgnored private var watcher: BDChangeWatcher?
    /// Reports changes to the view Library folder: a file dropped in, a sync, a hand edit.
    @ObservationIgnored private var libraryWatcher: BDChangeWatcher?
    /// A view file to import that arrived before a workspace was open.
    @ObservationIgnored private var pendingImports: [URL] = []
    /// What went wrong importing or exporting a view, for an alert.
    private(set) var viewFileError: String?

    private static let recentsKey = "recentWorkspaces"
    private static let turnsOnJournalKey = "turnsOnEventsJournal"
    /// Workspaces where Beady turned bd's change journal on. One found off again later was
    /// turned off by hand (an Undo here, or `bd config` elsewhere), and is left that way.
    private static let journalsTurnedOnKey = "eventsJournalTurnedOn"

    /// Where view state is remembered; nil for the offscreen snapshots, which must not disturb
    /// the saved views.
    @ObservationIgnored private let preferences: UserDefaults?

    /// The Library tier of views: ~/Library/Application Support/Beady/views, one .beadyview each.
    /// Nil when preferences are off, so snapshots never touch it.
    @ObservationIgnored private let viewsDirectory: URL?

    /// `--workspace <path>` on the command line wins over the most recent workspace.
    init(arguments: [String] = CommandLine.arguments, preferences: UserDefaults? = .standard) {
        self.preferences = preferences
        turnsOnJournal = preferences.map {
            $0.object(forKey: Self.turnsOnJournalKey) == nil || $0.bool(forKey: Self.turnsOnJournalKey)
        } ?? false
        // Read from Beady's own domain: `object(forKey:)` would answer with the system's list.
        let chosen = LanguageSetting.chosen(from: preferences?.persistentDomain(forName: Self.preferencesDomain)?[LanguageSetting.key])
        language = chosen
        languageAtLaunch = chosen
        viewsDirectory = preferences == nil ? nil : FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Beady/views", isDirectory: true)
        recentPaths = (UserDefaults.standard.stringArray(forKey: Self.recentsKey) ?? [])
            .filter { FileManager.default.fileExists(atPath: $0) }
        if let viewsDirectory {
            try? FileManager.default.createDirectory(at: viewsDirectory, withIntermediateDirectories: true)
            libraryWatcher = BDChangeWatcher(path: viewsDirectory.path) { [weak self] in
                Task { @MainActor in self?.model?.reloadViews() }
            }
        }
        if let path = Self.value(of: "--workspace", in: arguments) ?? recentPaths.first {
            open(URL(fileURLWithPath: path))
        }
    }

    /// Opens a database, offers to make one in a git repository that has none, or says why
    /// neither can happen. The decision is `WorkspaceOpening`'s; this gathers the facts.
    func open(_ url: URL) {
        let found = BeadsWorkspace.inspect(url)
        let folder = ChosenFolder(
            path: found.projectDirectory.path,
            hasBeadsDatabase: found.hasBeadsDatabase,
            isGitRepository: found.isGitRepository
        )
        switch WorkspaceOpening.decide(folder) {
        case .open:
            openWorkspace(url)
        case .offerNewDatabase(let plan):
            forget(found.projectDirectory.path)
            offerNewDatabase(plan)
        case .refuse(let reason):
            forget(found.projectDirectory.path)
            openError = reason
        }
    }

    private func offerNewDatabase(_ plan: NewDatabasePlan) {
        do {
            // The same gateway that will run it builds the preview, so what's shown is what runs.
            let gateway = try BDGateway.forNewWorkspace(at: URL(fileURLWithPath: plan.projectPath))
            databaseOffer = NewDatabaseOffer(plan: plan, command: gateway.preview(.initDatabase(prefix: plan.prefix)))
            openError = nil
        } catch {
            openError = error.localizedDescription
        }
    }

    /// Yes to the offer: run bd init, then open the folder like any other workspace.
    func createDatabase() {
        guard let offer = databaseOffer, !isCreatingDatabase else { return }
        databaseOffer = nil
        isCreatingDatabase = true
        let url = URL(fileURLWithPath: offer.plan.projectPath)
        Task {
            defer { isCreatingDatabase = false }
            do {
                _ = try await BDGateway.forNewWorkspace(at: url).run(.initDatabase(prefix: offer.plan.prefix))
                open(url)
            } catch {
                openError = String(localized: "Couldn't create a beads database in \(offer.plan.folderName): \(error.localizedDescription)", comment: "The folder's name, then bd's error")
            }
        }
    }

    /// No to the offer: nothing is written, and nothing is remembered.
    func declineDatabase() {
        databaseOffer = nil
    }

    private func openWorkspace(_ url: URL) {
        do {
            // Everything that reads or writes beads goes through this one gateway.
            let gateway = try BDGateway.open(url)
            let store = BDStore(gateway: gateway)
            workspace = gateway.workspace
            let path = gateway.workspace.projectDirectory.path
            model = WorkspaceModel(
                title: gateway.workspace.displayName,
                store: store,
                preferences: preferences,
                viewsDirectory: viewsDirectory,
                journalPolicy: JournalPolicy(
                    turnsOnAutomatically: turnsOnJournal,
                    wasTurnedOffByHand: journalsTurnedOn.contains(path),
                    noteTurnedOn: { [weak self] in self?.rememberJournalTurnedOn(at: path) }
                )
            )
            openError = nil
            watcher?.stop()
            // Passive FSEvents on bd's folder: every write touches a marker file and grows Dolt's
            // storage, so this fires within a moment of any agent's change. It stays the wake-up
            // even with bd's events journal on: following that journal would mean a bd process
            // held open for as long as the window is, and FSEvents costs nothing. The events
            // journal is read after the wake-up, to say who made the change.
            watcher = gateway.watchChanges { [weak self] in
                Task { @MainActor in await self?.model?.refreshIfChanged() }
            }
            remember(gateway.workspace.projectDirectory.path)
            if !pendingImports.isEmpty {
                let urls = pendingImports
                pendingImports = []
                importViews(from: urls)
            }
        } catch {
            openError = error.localizedDescription
        }
    }

    /// Workspace-level: remembered by path, because the journal is this database's setting,
    /// not this window's.
    private var journalsTurnedOn: [String] {
        preferences?.stringArray(forKey: Self.journalsTurnedOnKey) ?? []
    }

    private func rememberJournalTurnedOn(at path: String) {
        guard let preferences, !journalsTurnedOn.contains(path) else { return }
        preferences.set(journalsTurnedOn + [path], forKey: Self.journalsTurnedOnKey)
    }

    /// ⌘P, for a workspace the setting left alone: the same write, listed under Changes with
    /// its Undo.
    func turnOnJournal() {
        guard let model else { return }
        Task { await report(await model.enableJournal()) }
    }

    func undo(_ entry: ChangeRecord) {
        guard let model else { return }
        Task { await report(await model.undo(entry)) }
    }

    func dismissOpenError() {
        openError = nil
    }

    func dismissViewFileError() {
        viewFileError = nil
    }

    // MARK: Language

    /// True once the language setting differs from the one this process launched with.
    var needsRelaunchForLanguage: Bool { language != languageAtLaunch }

    /// Starts a fresh copy of the app and quits this one, which is how a language change takes
    /// effect: bundles pick their language once, at launch. The bare SwiftPM binary has no
    /// bundle to reopen, so it only quits.
    func relaunch() {
        let url = Bundle.main.bundleURL
        guard url.pathExtension == "app" else {
            NSApp.terminate(nil)
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }

    // MARK: Reset Configuration

    /// The preferences domain a reset removes: the bundle's, or the inventory's name when running
    /// the bare binary.
    private static var preferencesDomain: String {
        Bundle.main.bundleIdentifier ?? ConfigurationInventory.preferencesDomain
    }

    /// What a reset would remove, counted from what is actually stored right now.
    func configurationInventory() -> ConfigurationInventory {
        let stored = preferences?.persistentDomain(forName: Self.preferencesDomain) ?? [:]
        return ConfigurationInventory(
            presentKeys: Set(stored.keys),
            recentWorkspaces: (stored[Self.recentsKey] as? [String])?.count ?? recentPaths.count,
            journalWorkspaces: (stored[Self.journalsTurnedOnKey] as? [String])?.count ?? 0,
            libraryViews: libraryViews.count
        )
    }

    /// The user's own views in the Library folder, read from disk so this works with no
    /// workspace open.
    private var libraryViews: [IssueView] {
        guard let viewsDirectory else { return [] }
        return ViewLibrary.load(from: viewsDirectory, preferences: nil).views.filter { !$0.isBuiltIn }
    }

    /// Writes every saved view to one .beadyviews file, for before a reset that deletes them.
    func exportLibraryViews() {
        let views = libraryViews
        guard !views.isEmpty else { return }
        let panel = NSSavePanel()
        panel.title = String(localized: "Export Saved Views")
        panel.nameFieldStringValue = "\(String(localized: "Beady views", comment: "Default file name for an export of every saved view")).\(ViewLibrary.bundleExtension)"
        panel.allowedContentTypes = [.beadyViews]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try ViewLibrary.documentData(for: views).write(to: url, options: .atomic)
        } catch {
            viewFileError = "\(url.lastPathComponent): \(error.localizedDescription)"
        }
    }

    /// Removes Beady's own settings on this Mac — the preferences domain, and the Library when
    /// asked — and returns to the welcome screen with defaults. In-memory state is put back first
    /// and the stores wiped last, so nothing written on the way back survives. No relaunch: the
    /// window and the stores reload in place.
    func resetConfiguration(deletingLibrary: Bool) {
        let plan = configurationInventory().plan(deletingLibrary: deletingLibrary)
        ui.showsResetConfiguration = false
        close()
        recentPaths = []
        pendingImports = []
        themes.restoreDefaults()
        turnsOnJournal = true
        language = nil
        do {
            try ConfigurationReset.perform(
                plan,
                defaults: preferences ?? .standard,
                domain: Self.preferencesDomain,
                libraryFolder: viewsDirectory?.deletingLastPathComponent()
            )
        } catch {
            openError = String(localized: "Couldn't remove the Library folder: \(error.localizedDescription)")
        }
        // An empty Library folder is recreated so views can be saved again, and watched again,
        // since the watch died with the folder.
        if plan.removesLibrary, let viewsDirectory {
            try? FileManager.default.createDirectory(at: viewsDirectory, withIntermediateDirectories: true)
            libraryWatcher?.stop()
            libraryWatcher = BDChangeWatcher(path: viewsDirectory.path) { [weak self] in
                Task { @MainActor in self?.model?.reloadViews() }
            }
        }
    }

    // MARK: View files

    /// Imports every .beadyview / .beadyviews given — from Finder, a drop on the sidebar, or
    /// Import Views…. With no workspace open yet they wait for one: the Library is the user's,
    /// but the model that holds it comes with a workspace.
    func importViews(from urls: [URL]) {
        guard let model else {
            pendingImports += urls
            return
        }
        var failures: [String] = []
        for url in urls {
            do {
                try model.importViews(fromDocument: Data(contentsOf: url))
            } catch {
                failures.append("\(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
        if !failures.isEmpty { viewFileError = failures.joined(separator: "\n") }
    }

    func chooseViewsToImport() {
        let panel = NSOpenPanel()
        panel.title = String(localized: "Import Views")
        panel.message = String(localized: "Choose .beadyview or .beadyviews files.")
        panel.prompt = String(localized: "Import", comment: "Open panel button")
        panel.allowedContentTypes = [.beadyView, .beadyViews]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        if panel.runModal() == .OK { importViews(from: panel.urls) }
    }

    /// Writes a view as saved to a file of the user's choosing.
    func exportView(_ id: IssueView.ID) {
        guard let model, let view = model.views.first(where: { $0.id == id }) else { return }
        let panel = NSSavePanel()
        panel.title = String(localized: "Export View")
        panel.nameFieldStringValue = view.exportFilename
        panel.allowedContentTypes = [.beadyView]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            guard let data = try model.exportDocument(for: id) else { return }
            try data.write(to: url, options: .atomic)
        } catch {
            viewFileError = "\(url.lastPathComponent): \(error.localizedDescription)"
        }
    }

    func close() {
        watcher?.stop()
        watcher = nil
        model = nil
        workspace = nil
    }

    /// A folder to back up into — anywhere Time Machine or a sync service already reaches.
    func chooseBackupFolder() {
        guard let model else { return }
        let panel = NSOpenPanel()
        panel.title = String(localized: "Choose a Backup Folder")
        panel.message = String(localized: "bd will push this database there: tables, branches and history, not just the issues.")
        panel.prompt = String(localized: "Back Up Here", comment: "Open panel button")
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await report(await model.startBackingUp(to: url.path)) }
    }

    /// Backup failures surface in the same alert as a workspace that wouldn't open.
    private func report(_ failure: String?) {
        guard let failure else { return }
        openError = failure
    }

    func chooseWorkspace() {
        let panel = NSOpenPanel()
        panel.title = String(localized: "Open Beads Workspace")
        panel.message = String(localized: "Choose a project folder containing .beads, or a git repository to create one in.")
        panel.prompt = String(localized: "Open", comment: "Open panel button")
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
        case .showView(let id): model?.viewID = id
        case .saveView: model?.save()
        case .saveViewAs: ui.promptSaveAsNewView(suggesting: model.map { $0.view.isBuiltIn ? "" : $0.view.name } ?? "")
        case .resetView: model?.reset()
        case .exportView(let id): exportView(id)
        case .importViews: chooseViewsToImport()
        case .resetConfiguration:
            ui.showsResetConfiguration = true
            NSApp.activate(ignoringOtherApps: true)
        case .setLayout(let layout): model?.layout = layout
        case .setGrouping(let grouping): model?.grouping = grouping
        case .setOrdering(let sort): model?.ordering = sort
        case .goToIssue(let id, _):
            model?.selection = id
            ui.showsInspector = true
        case .toggleMark(let mark):
            if let model, let id = model.selection {
                Task { await model.toggleMark(mark, on: id) }
            }
        case .showGraph: ui.openGraph(focusing: model?.selection)
        case .goBack: model?.goBack()
        case .goForward: model?.goForward()
        case .focusSelected: if let id = model?.selection { model?.focus(on: id) }
        case .unfocus: model?.unfocus()
        case .expandAll: model?.expandAll()
        case .collapseAll: model?.collapseAll()
        case .toggleColumn(let column): ui.columns.setVisible(column, !ui.columns.isVisible(column))
        case .resetColumns: ui.columns.reset()
        case .setSidebarStyle(let style): themes.sidebarStyle = style
        case .backUpNow:
            if let model { Task { await report(await model.backUpNow()) } }
        case .setUpBackup: chooseBackupFolder()
        case .turnOnJournal: turnOnJournal()
        case .openSettings: NSApp?.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        case .chooseTheme: ui.showsThemes = true
        case .setTextSize(let size): themes.textSize = size
        case .setLanguage(let code):
            language = code
            if needsRelaunchForLanguage { ui.showsRelaunchPrompt = true }
        }
    }

    private static func value(of flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }
}
