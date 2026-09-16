import AppKit
import BeadsCore
import BeadsPresentation
import SwiftUI

/// Dev aid for verifying the UI without a window on screen:
///
///     BEADY_SNAPSHOT_DIR=/tmp/shots Beady --workspace /path/to/project
///
/// loads the workspace, renders several views into offscreen windows, writes one PNG each, and
/// exits. It never applies a change and leaves saved preferences untouched.
@MainActor
enum SnapshotMode {
    static var outputDirectory: URL? {
        ProcessInfo.processInfo.environment["BEADY_SNAPSHOT_DIR"].map { URL(fileURLWithPath: $0) }
    }

    static func run(to directory: URL) -> Never {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let session = AppSession(preferences: nil)
        guard let model = session.model else { fail(session.openError ?? "no workspace; pass --workspace") }

        Task { await model.load() }
        pump(timeout: 60) { model.loadState != .idle && model.loadState != .loading }
        if case .failed(let message) = model.loadState { fail(message) }
        guard let snapshot = model.snapshot else { fail("load timed out") }

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            fail("can't create \(directory.path): \(error.localizedDescription)")
        }

        func capture<Content: View>(_ name: String, _ view: Content) {
            let url = directory.appendingPathComponent("\(name).png")
            let theme = session.themes.theme(for: session.themes.appearance == .light ? .light : .dark)
            render(
                view
                    .environment(\.theme, theme)
                    .tint(theme.accent)
                    .foregroundStyle(theme.text)
                    .background(theme.background),
                to: url
            )
            print("wrote \(url.path) (\(model.visibleIssues.count) issues in \(model.viewTitle))")
        }
        func captureWorkspace(_ name: String) {
            model.selection = model.visibleIssues.first { snapshot.progress(of: $0.id) == nil }?.id ?? model.visibleIssues.first?.id
            capture(name, WorkspaceView(model: model, ui: session.ui, persistsPreferences: false))
        }

        let labelCounts = Dictionary(snapshot.issues.flatMap(\.labels).map { ($0, 1) }, uniquingKeysWith: +)
        let topLabels = labelCounts.sorted { ($1.value, $0.key) < ($0.value, $1.key) }.prefix(2).map(\.key)

        // The README wants one of each: same view, both appearances.
        session.themes.appearance = .dark
        model.source = .lifecycle(.open)
        captureWorkspace("1-open-list")
        session.themes.appearance = .light
        captureWorkspace("1b-open-list-light")
        session.themes.appearance = .dark

        model.source = .lifecycle(.inFlight)
        captureWorkspace("2-in-flight-grouped-by-status")

        model.source = .lifecycle(.blocked)
        captureWorkspace("2b-blocked-view")

        model.source = .lifecycle(.all)
        model.layout = .board
        captureWorkspace("3-all-board-by-lifecycle")

        model.source = .lifecycle(.open)
        model.toggleFilterValue("1", in: .priority)
        model.toggleFilterValue("2", in: .priority)
        topLabels.prefix(1).forEach { model.toggleFilterValue($0, in: .labels) }
        captureWorkspace("4-open-with-filter-chips")

        // Nothing matches: the filter bar must stay its own height, not grow into the gap.
        model.searchText = "zzzz-nothing-matches-this"
        captureWorkspace("4b-empty-list")
        model.searchText = ""

        // Back to In Flight: its own (empty) filters, not Open's.
        model.source = .lifecycle(.inFlight)
        captureWorkspace("5-in-flight-keeps-its-own-filters")

        let parents = snapshot.issues.filter { !snapshot.children(of: $0.id).isEmpty }
        if let biggest = parents.max(by: { (snapshot.progress(of: $0.id)?.total ?? 0) < (snapshot.progress(of: $1.id)?.total ?? 0) }) {
            model.focus(on: biggest.id)
            captureWorkspace("6-focused-bead-tree")
        }

        model.source = .lifecycle(.open)
        capture("7-filter-menu-priority", FilterMenu(model: model, initialField: .priority).padding())

        // The confirmation sheet for moving a bead between epics. Only proposed, never applied:
        // snapshot mode must not write.
        if let source = parents.first?.id,
           let child = snapshot.children(of: source).first,
           let target = parents.map(\.id).first(where: { $0 != source && $0 != child.id }) {
            model.proposeParent(child.id, to: target)
            if let pending = model.pendingChange {
                capture("8-confirm-move", ChangeConfirmationView(model: model, pending: pending, onCancel: {}))
            }
            model.cancelPendingChange()
        }
        capture("9-command-palette", CommandPaletteView(model: model, run: { _ in }, onClose: {}))
        session.themes.preview(Theme.dark(named: "Dracula"))
        capture("11-themes", ThemePickerView(themes: session.themes, onClose: {}))
        session.themes.cancelPreview()

        // The graph sheet, on whatever is most tangled up.
        if let blocked = snapshot.issues.first(where: { snapshot.isBlocked($0) && !snapshot.openBlockers(of: $0).isEmpty }) {
            model.selection = blocked.id
            capture("13-graph", GraphSheet(model: model, onClose: {}))
        }

        // History reads from bd, so give it a moment before the shutter.
        if let busiest = snapshot.issues.max(by: { $0.updatedAt < $1.updatedAt }) {
            let section = HistorySection(model: model, issue: busiest, startExpanded: true)
            Task { await model.loadHistory(for: busiest.id) }
            pump(timeout: 10) { if case .loaded = model.history[busiest.id] { true } else { false } }
            capture("12-history", section.frame(width: 420).padding())
        }
        capture("10-shortcuts", ShortcutsView(model: model, onClose: {}))
        exit(0)
    }

    private static func render<Content: View>(_ view: Content, to url: URL) {
        let size = CGSize(width: 1440, height: 880)
        let hosting = NSHostingView(rootView: view)
        let window = NSWindow(
            contentRect: CGRect(origin: CGPoint(x: -30_000, y: -30_000), size: size),
            styleMask: [.titled, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        // Let SwiftUI lay out and AppKit-backed lists populate before capturing.
        pump(seconds: 1.0)
        hosting.layoutSubtreeIfNeeded()
        if let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) {
            hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
            try? bitmap.representation(using: .png, properties: [:])?.write(to: url)
        }
        window.close()
    }

    private static func pump(seconds: TimeInterval) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    private static func pump(timeout: TimeInterval, until done: () -> Bool) {
        let deadline = Date().addingTimeInterval(timeout)
        while !done(), Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
    }

    private static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data("snapshot: \(message)\n".utf8))
        exit(1)
    }
}
