import AppKit
import BeadsCore
import BeadsPresentation
import SwiftUI

@main
struct BeadyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    // The App struct is created once, so a plain property holds the session. (No @State:
    // Command Line Tools ship without the SwiftUI macro plugin that @State now needs.)
    private let session = AppSession()

    init() {
        if SnapshotMode.verifiesKeys {
            SnapshotMode.verifyKeys()
        }
        if let directory = SnapshotMode.outputDirectory {
            SnapshotMode.run(to: directory)
        }
    }

    var body: some Scene {
        Window("Beady", id: "main") {
            RootView(session: session)
        }
        .defaultSize(width: 1320, height: 820)
        .commands { AppCommands(session: session) }

        Window("Dependencies", id: "dependencies") {
            DependencyWindow(session: session)
        }
        .defaultSize(width: 1100, height: 720)

        Settings {
            SettingsView(themes: session.themes, session: session)
                .themed(session.themes)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Where files opened from Finder go. Set once the session's view is up; files that arrive
    /// first (a double-click that launched the app) wait here.
    static var openFiles: (([URL]) -> Void)? {
        didSet {
            guard let openFiles, !pendingFiles.isEmpty else { return }
            let urls = pendingFiles
            pendingFiles = []
            openFiles(urls)
        }
    }
    private static var pendingFiles: [URL] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Lets the bare SwiftPM binary behave like an app too (Dock icon, menu bar).
        NSApp.setActivationPolicy(.regular)
    }

    /// A .beadyview double-clicked or dropped on the Dock icon is imported into the Library.
    func application(_ application: NSApplication, open urls: [URL]) {
        if let openFiles = Self.openFiles {
            openFiles(urls)
        } else {
            Self.pendingFiles += urls
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

struct RootView: View {
    let session: AppSession
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        content
            .themed(session.themes)
            .onAppear {
                session.themes.watchAccessibility()
                if SnapshotMode.tracesPanes { SnapshotMode.tracePanes(ui: session.ui) }
                AppDelegate.openFiles = { [weak session] urls in session?.importViews(from: urls) }
            }
            // Only a view can open a window; commands ask through the UI state.
            .onChange(of: session.ui.graphWindowRequests) { openWindow(id: "dependencies") }
    }

    @ViewBuilder
    private var content: some View {
        Group {
            if let model = session.model {
                WorkspaceView(
                    model: model, ui: session.ui, themes: session.themes, run: session.run,
                    undo: session.undo, importFiles: session.importViews
                )
                    .id(ObjectIdentifier(model))
            } else {
                WelcomeView(session: session)
            }
        }
        .frame(minWidth: 960, minHeight: 600)
        // The welcome screen shows open errors inline; with a workspace open they need an alert.
        .alert("Couldn't Open Workspace", isPresented: showsOpenError) {
            Button("OK", role: .cancel) { session.dismissOpenError() }
        } message: {
            Text(session.openError ?? "")
        }
        .alert(session.databaseOffer?.plan.offerTitle ?? "", isPresented: showsDatabaseOffer) {
            Button("Create Database") { session.createDatabase() }
            Button("Cancel", role: .cancel) { session.declineDatabase() }
        } message: {
            Text(session.databaseOffer.map { $0.plan.offerMessage(command: $0.command) } ?? "")
        }
        .sheet(isPresented: showsResetConfiguration) {
            ResetConfigurationSheet(
                inventory: session.configurationInventory(),
                onExport: { session.exportLibraryViews() },
                onReset: { session.resetConfiguration(deletingLibrary: $0) },
                onCancel: { session.ui.showsResetConfiguration = false }
            )
            .themed(session.themes)
        }
        .alert("Couldn't Import View", isPresented: showsViewFileError) {
            Button("OK", role: .cancel) { session.dismissViewFileError() }
        } message: {
            Text(session.viewFileError ?? "")
        }
        .alert("Relaunch Beady?", isPresented: showsRelaunchPrompt) {
            Button("Relaunch Now") { session.relaunch() }
            Button("Later", role: .cancel) {}
        } message: {
            Text("The language setting takes effect when Beady next launches.")
        }
    }

    private var showsRelaunchPrompt: Binding<Bool> {
        Binding(
            get: { session.ui.showsRelaunchPrompt },
            set: { session.ui.showsRelaunchPrompt = $0 }
        )
    }

    private var showsResetConfiguration: Binding<Bool> {
        Binding(
            get: { session.ui.showsResetConfiguration },
            set: { session.ui.showsResetConfiguration = $0 }
        )
    }

    private var showsViewFileError: Binding<Bool> {
        Binding(
            get: { session.viewFileError != nil },
            set: { if !$0 { session.dismissViewFileError() } }
        )
    }

    private var showsDatabaseOffer: Binding<Bool> {
        Binding(
            get: { session.databaseOffer != nil },
            set: { if !$0 { session.declineDatabase() } }
        )
    }

    private var showsOpenError: Binding<Bool> {
        Binding(
            get: { session.model != nil && session.openError != nil },
            set: { if !$0 { session.dismissOpenError() } }
        )
    }
}

/// The menu bar, built from the same `AppCommand`s the palette runs, so every action has a
/// visible home and a documented key.
struct AppCommands: Commands {
    let session: AppSession

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            item(.openWorkspace)
            Menu("Open Recent") {
                ForEach(session.recentPaths, id: \.self) { path in
                    Button(path) { session.open(URL(fileURLWithPath: path)) }
                }
            }
            .disabled(session.recentPaths.isEmpty)
            Divider()
            item(.closeWorkspace, needsWorkspace: true)
        }
        CommandGroup(replacing: .textEditing) {
            item(.focusSearch, needsWorkspace: true)
            item(.addFilter, needsWorkspace: true)
            item(.clearFilters, needsWorkspace: true)
        }
        CommandMenu("Go") {
            Button("Command Palette…") { session.ui.openPalette() }
                .keyboardShortcut("p")
                .disabled(session.model == nil)
            Divider()
            item(.goBack, needsWorkspace: true)
            item(.goForward, needsWorkspace: true)
            Divider()
            ForEach(IssueView.builtIns) { view in
                Button(view.name) { session.run(.showView(view.id)) }
                    .disabled(session.model == nil)
            }
            Divider()
            item(.saveView, needsWorkspace: true)
            item(.saveViewAs, needsWorkspace: true)
            item(.resetView, needsWorkspace: true)
            Divider()
            Button("Export View…") { if let id = session.model?.viewID { session.run(.exportView(id)) } }
                .disabled(session.model == nil)
            item(.importViews, needsWorkspace: true)
        }
        CommandMenu("Beads") {
            item(.newBead, needsWorkspace: true)
            item(.editSelected, needsWorkspace: true)
            item(.showGraph, needsWorkspace: true)
            Divider()
            item(.refresh, needsWorkspace: true)
        }
        CommandGroup(after: .sidebar) {
            ForEach(WorkspaceModel.Layout.allCases) { layout in
                item(.setLayout(layout), needsWorkspace: true)
            }
            Divider()
            item(.toggleDetails, needsWorkspace: true)
            item(.displayOptions, needsWorkspace: true)
            Divider()
            item(.chooseTheme, needsWorkspace: true)
        }
        CommandGroup(replacing: .help) {
            item(.showShortcuts, needsWorkspace: true)
            // A menu item can only display one key, and it shows the ⌘ one; this is where the
            // bare "?" gets taught.
            Text("Press ? anywhere in the window for the shortcut list")
            Divider()
            Link("Beady on GitHub", destination: URL(string: "https://github.com/dvhthomas/beady")!)
        }
    }

    /// A menu item for a command, taking its key from the command itself.
    private func item(_ command: AppCommand, needsWorkspace: Bool = false) -> some View {
        Button(command.title) { session.run(command) }
            .keyboardShortcut(command.menuShortcut)
            .disabled(needsWorkspace && session.model == nil)
    }
}
