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

        Settings {
            SettingsView(themes: session.themes)
                .themed(session.themes)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Lets the bare SwiftPM binary behave like an app too (Dock icon, menu bar).
        NSApp.setActivationPolicy(.regular)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

struct RootView: View {
    let session: AppSession

    var body: some View {
        content
            .themed(session.themes)
            .onAppear { session.themes.watchAccessibility() }
    }

    @ViewBuilder
    private var content: some View {
        Group {
            if let model = session.model {
                WorkspaceView(model: model, ui: session.ui, themes: session.themes, run: session.run)
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
            Button("Command Palette…") { session.ui.showsPalette = true }
                .keyboardShortcut("p")
                .disabled(session.model == nil)
            Divider()
            ForEach(Scope.allCases) { scope in
                Button(DisplayText.scope(scope)) { session.run(.showView(.lifecycle(scope))) }
                    .disabled(session.model == nil)
            }
        }
        CommandMenu("Beads") {
            item(.newBead, needsWorkspace: true)
            item(.editSelected, needsWorkspace: true)
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
