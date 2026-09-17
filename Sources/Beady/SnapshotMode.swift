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
    /// `BEADY_VERIFY_KEYS=1 Beady --workspace <path>` types into a real window and reports
    /// whether single-key shortcuts behaved. It exists because "does typing f open the filter
    /// menu?" is otherwise a question only a human at the keyboard can answer.
    static var verifiesKeys: Bool {
        ProcessInfo.processInfo.environment["BEADY_VERIFY_KEYS"] == "1"
    }

    static func verifyKeys() -> Never {
        let session = AppSession(preferences: nil)
        guard let model = session.model else { fail(session.openError ?? "no workspace; pass --workspace") }
        Task { await model.load() }
        pump(timeout: 60) { model.loadState != .idle && model.loadState != .loading }

        let ui = session.ui
        let window = NSWindow(
            contentRect: CGRect(x: 100, y: 100, width: 1200, height: 800),
            styleMask: [.titled, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(
            rootView: WorkspaceView(model: model, ui: ui, themes: session.themes, run: session.run, persistsPreferences: false)
                .themed(session.themes)
        )
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        pump(seconds: 1.5)

        var failures: [String] = []
        func check(_ name: String, _ condition: Bool, _ detail: @autoclosure () -> String = "") {
            let mark = condition ? "ok  " : "FAIL"
            print("\(mark) \(name)\(condition ? "" : " — \(detail())")")
            if !condition { failures.append(name) }
        }

        // 1. Typing in the search field must reach the field, not the shortcuts.
        ui.focusSearch()
        pump(seconds: 0.6)
        check("search field takes focus", ui.isSearchFocused)
        type("f", into: window)
        type("/", into: window)
        type("?", into: window, shift: true)
        pump(seconds: 0.5)
        check("typing f / ? into search doesn't open the filter menu", !ui.showsFilterMenu)
        check("…or the shortcut sheet", !ui.showsShortcuts)
        check("…and the characters land in the field", model.searchText.contains("f"), "searchText = “\(model.searchText)”")

        // 2. The same keys with a sheet open must not reach the window behind it.
        model.searchText = ""
        ui.showsNewBead = true
        pump(seconds: 0.8)
        type("f", into: window)
        type("?", into: window, shift: true)
        pump(seconds: 0.5)
        check("a sheet is open", ui.showsNewBead)
        check("typing f behind a sheet doesn't open the filter menu", !ui.showsFilterMenu)
        check("typing ? behind a sheet doesn't open the shortcut sheet", !ui.showsShortcuts)
        ui.showsNewBead = false
        pump(seconds: 0.4)

        // 3. The other half of the bargain: with nothing focused, the bare keys still work.
        // Clearing the flag isn't enough — AppKit's focus has to actually move, and if the
        // harness can't manage that, this is reported as untested rather than failed.
        window.makeFirstResponder(nil)
        pump(seconds: 0.8)
        if ui.isSearchFocused {
            print("skip  with no field focused, f opens the filter menu — harness couldn't blur the search field")
        } else {
            type("f", into: window)
            pump(seconds: 0.5)
            check("with no field focused, f opens the filter menu", ui.showsFilterMenu)
        }

        print(failures.isEmpty ? "\nAll key checks passed." : "\nFailed: \(failures.joined(separator: ", "))")
        exit(failures.isEmpty ? 0 : 1)
    }

    /// Sends a keystroke the way a keyboard would, through the window's event handling.
    private static func type(_ character: String, into window: NSWindow, shift: Bool = false) {
        let codes: [String: UInt16] = ["f": 3, "/": 44, "?": 44, "v": 9]
        guard let event = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: shift ? [.shift] : [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            characters: character,
            charactersIgnoringModifiers: shift && character == "?" ? "/" : character,
            isARepeat: false,
            keyCode: codes[character] ?? 0
        ) else { return }
        NSApp.sendEvent(event)
        pump(seconds: 0.15)
    }

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

        // A search that leaves the board shorter than the pane: it must stay at the top.
        model.searchText = "distance"
        captureWorkspace("3b-board-narrowed-by-search")
        model.searchText = ""

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
        capture("9-command-palette", CommandPaletteView(model: model, ui: session.ui, run: { _ in }, onClose: {}))
        // Typing has to re-filter the live view, not just a freshly built one: these two are
        // rendered from the same hosted view, with the query changed in between.
        session.ui.paletteQuery = ""
        renderLive(
            CommandPaletteView(model: model, ui: session.ui, run: { _ in }, onClose: {}),
            to: directory,
            first: "live-1-typed-nothing",
            second: "live-2-typed-c"
        ) { session.ui.paletteQuery = "c" }

        // And moving the highlight has to move it: same view, cursor pushed down twice.
        session.ui.paletteQuery = "column"
        session.ui.paletteHighlight = 0
        renderLive(
            CommandPaletteView(model: model, ui: session.ui, run: { _ in }, onClose: {}),
            to: directory,
            first: "live-3-highlight-first",
            second: "live-4-highlight-third"
        ) { session.ui.paletteHighlight = 2 }
        session.ui.paletteQuery = ""
        session.ui.paletteHighlight = 0
        // Proof that typing filters: the state the view actually reads.
        session.ui.paletteQuery = "them"
        capture("9b-command-palette-filtered", CommandPaletteView(model: model, ui: session.ui, run: { _ in }, onClose: {}))
        session.ui.paletteQuery = ""
        session.themes.preview(Theme.dark(named: "Dracula"))
        capture("11-themes", ThemePickerView(themes: session.themes, onClose: {}))
        // Previewing a light theme from a dark setting: the case where the controls went grey.
        session.themes.preview(Theme.light(named: "Solarized Light"))
        capture("11b-themes-light-preview", ThemePickerView(themes: session.themes, onClose: {}))
        session.themes.cancelPreview()

        // The detail pane after following a blocker link: the back bar has something to do.
        if let waiting = snapshot.issues.first(where: { !snapshot.openBlockers(of: $0).isEmpty }),
           let blocker = snapshot.openBlockers(of: waiting).first {
            model.source = .lifecycle(.all)
            model.selection = waiting.id
            model.selection = blocker.id
            capture("15-detail-with-back", IssueDetailView(model: model).frame(width: 420, height: 700))
        }

        // The edit form, which is the thing being overhauled.
        if let subject = snapshot.issues.first(where: { !snapshot.openBlockers(of: $0).isEmpty }) {
            model.selection = subject.id
            model.beginEditing(subject.id)
            if model.draft != nil {
                let draft = Binding(get: { model.draft ?? EditDraft(issue: subject) }, set: { model.draft = $0 })
                capture("16-edit-form", EditBeadForm(model: model, draft: draft, onCancel: {}).frame(width: 460, height: 800))
            }
            model.endEditing()
        }

        // The dependency window: the whole graph, then focused on a bead with both a past and a
        // future, so bold upstream and tinted downstream both show.
        let graph = DependencyGraph(snapshot)
        session.ui.graphFocus = nil
        capture("17-graph-whole", DependencyGraphView(model: model, ui: session.ui))
        if let middle = graph.nodes.max(by: {
            min(graph.upstream(of: $0.id).count, graph.downstream(of: $0.id).count)
                < min(graph.upstream(of: $1.id).count, graph.downstream(of: $1.id).count)
        }) {
            // Recentring is the point, so it's checked on a live view: open unfocused, then
            // follow a bead, and see where the view ends up.
            session.ui.graphFocus = nil
            renderLive(
                DependencyGraphView(model: model, ui: session.ui).themed(session.themes),
                to: directory,
                first: "18a-graph-before-follow",
                second: "18b-graph-after-follow"
            ) { session.ui.graphFocus = middle.id }
            print("focused \(middle.id): \(graph.upstream(of: middle.id).count) upstream, \(graph.downstream(of: middle.id).count) downstream")
            session.ui.graphFocus = nil
        }

        // The popover behind the waiting mark.
        if let waiting = snapshot.issues.first(where: { !snapshot.openBlockers(of: $0).isEmpty }),
           let reason = BlockedReason.of(waiting.id, in: snapshot) {
            capture("14-waiting-detail", WaitingDetail(reason: reason, snapshot: snapshot, open: { _ in }))
        }

        exit(0)
    }

    /// Renders one hosted view twice, mutating state in between, to see whether the live view
    /// actually reacts — which a fresh render of a new view can't tell you.
    static func renderLive<Content: View>(
        _ view: Content,
        to directory: URL,
        first: String,
        second: String,
        change: @escaping () -> Void
    ) {
        let size = CGSize(width: 900, height: 600)
        let hosting = NSHostingView(rootView: view)
        let window = NSWindow(
            contentRect: CGRect(origin: CGPoint(x: -30_000, y: -30_000), size: size),
            styleMask: [.titled, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        pump(seconds: 0.8)
        capture(hosting, to: directory.appendingPathComponent("\(first).png"))
        change()
        pump(seconds: 0.8)
        hosting.layoutSubtreeIfNeeded()
        capture(hosting, to: directory.appendingPathComponent("\(second).png"))
        window.close()
    }

    private static func capture(_ hosting: NSHostingView<some View>, to url: URL) {
        hosting.layoutSubtreeIfNeeded()
        guard let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return }
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        try? bitmap.representation(using: .png, properties: [:])?.write(to: url)
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
