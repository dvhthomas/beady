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

        // 0. Before anything takes focus: Escape lets go of the selection.
        model.selection = model.visibleIssues.first?.id
        pump(seconds: 0.4)
        check("a bead is selected", model.selection != nil)
        check("…and nothing has the keyboard yet", !ui.isSearchFocused)
        type("\u{1b}", into: window)
        pump(seconds: 0.4)
        check("Escape clears the selection", model.selection == nil, "selection = \(model.selection?.rawValue ?? "nil")")

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

        // 4. Escape lets go of the selection — but not while search has the keyboard.
        ui.showsFilterMenu = false
        pump(seconds: 0.4)
        model.selection = model.visibleIssues.first?.id
        ui.focusSearch()
        pump(seconds: 0.5)
        if ui.isSearchFocused {
            type("\u{1b}", into: window)
            pump(seconds: 0.3)
            check("Escape in the search field leaves the selection alone", model.selection != nil)
        }

        // 5. Sheets that need nothing from you close on Escape.
        ui.showsShortcuts = true
        pump(seconds: 0.8)
        type("\u{1b}", into: NSApp.keyWindow ?? window)
        pump(seconds: 0.6)
        check("Escape closes the shortcuts sheet", !ui.showsShortcuts)

        // 6. So does the dependency window.
        var graphClosed = false
        let graphWindow = NSWindow(
            contentRect: CGRect(x: 160, y: 160, width: 900, height: 600),
            styleMask: [.titled, .resizable],
            backing: .buffered,
            defer: false
        )
        graphWindow.isReleasedWhenClosed = false
        graphWindow.contentView = NSHostingView(
            rootView: DependencyGraphView(model: model, ui: ui) { graphClosed = true }.themed(session.themes)
        )
        graphWindow.makeKeyAndOrderFront(nil)
        pump(seconds: 0.8)
        type("\u{1b}", into: graphWindow)
        pump(seconds: 0.4)
        check("Escape closes the dependency window", graphClosed)
        graphWindow.close()

        // 7. Switching sidebar views must hand the keyboard to the center pane — otherwise the
        // first arrow key after a click walks the sidebar's own list instead of the beads.
        // (NSOutlineView, which backs both List and Table, is itself an NSTableView, so the
        // sidebar's single "Views" column and the center pane's ten columns tell them apart.)
        model.viewID = .frontier
        pump(seconds: 0.4)
        let tables = allTables(in: window.contentView!)
        if let sidebarTable = tables.first(where: { $0.tableColumns.count < 3 }),
           let centerTable = tables.first(where: { $0.tableColumns.count >= 3 }) {
            window.makeFirstResponder(sidebarTable)
            check("the sidebar can be made first responder, as a click would leave it", window.firstResponder === sidebarTable)
            model.viewID = .deferred
            pump(seconds: 0.6)
            check(
                "switching views hands the keyboard to the center pane",
                window.firstResponder === centerTable,
                "firstResponder = \(String(describing: window.firstResponder))"
            )
        } else {
            print("skip  switching views refocuses the center pane — harness couldn't find both tables")
        }

        // 8. Opening the detail pane must not squeeze the sidebar: the two panes are independent.
        if let sidebarTable = allTables(in: window.contentView!).first(where: { $0.tableColumns.count < 3 }) {
            func sidebarWidth() -> CGFloat { sidebarTable.window == nil ? 0 : sidebarTable.convert(sidebarTable.bounds, to: nil).maxX }
            window.setContentSize(CGSize(width: 960, height: 800))
            ui.showsInspector = false
            pump(seconds: 1.0)
            let resting = sidebarWidth()
            var narrowest = resting
            ui.showsInspector = true
            let deadline = Date().addingTimeInterval(1.2)
            while Date() < deadline {
                pump(seconds: 0.016)
                narrowest = min(narrowest, sidebarWidth())
            }
            check(
                "opening the detail pane leaves the sidebar alone",
                narrowest >= resting - 1 && sidebarWidth() >= resting - 1,
                "sidebar \(Int(resting))pt at rest, \(Int(narrowest))pt at its narrowest, \(Int(sidebarWidth()))pt after"
            )
        }

        print(failures.isEmpty ? "\nAll key checks passed." : "\nFailed: \(failures.joined(separator: ", "))")
        exit(failures.isEmpty ? 0 : 1)
    }

    /// Sends a keystroke the way a keyboard would, through the window's event handling.
    private static func type(_ character: String, into window: NSWindow, shift: Bool = false) {
        let codes: [String: UInt16] = ["f": 3, "/": 44, "?": 44, "v": 9, "\u{1b}": 53]
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

    /// Every table in this view's subtree, sidebar and center pane alike — used only to seed the
    /// harness with the sidebar's table as first responder, the way a real click would leave it.
    private static func allTables(in view: NSView) -> [NSTableView] {
        var found: [NSTableView] = []
        if let table = view as? NSTableView { found.append(table) }
        for subview in view.subviews { found += allTables(in: subview) }
        return found
    }

    private static func splitWidths(in view: NSView) -> [[Int]] {
        var found: [[Int]] = []
        if let split = view as? NSSplitView { found.append(split.arrangedSubviews.map { split.isSubviewCollapsed($0) ? -1 : Int($0.frame.width) }) }
        for sub in view.subviews { found += splitWidths(in: sub) }
        return found
    }

    /// `BEADY_TRACE_PANES=1`: in the real app window, closes then opens the detail pane and logs
    /// every split-view pane's width through the animation, then quits.
    static var tracesPanes: Bool { ProcessInfo.processInfo.environment["BEADY_TRACE_PANES"] == "1" }

    static func tracePanes(ui: WorkspaceUI) {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            guard let window = NSApp.windows.first(where: { $0.contentView != nil && $0.isVisible }),
                  let root = window.contentView else { FileHandle.standardError.write(Data("trace no window: \(NSApp.windows.map { "\($0.title)|\($0.isVisible)" })\n".utf8)); exit(2) }
            @MainActor func log(_ label: String) {
                FileHandle.standardError.write(Data("trace \(label) window=\(Int(window.frame.width)) \(splitWidths(in: root))\n".utf8))
            }
            ui.showsInspector = false
            try? await Task.sleep(for: .seconds(1.5))
            log("closed")
            ui.showsInspector = true
            for step in 0..<60 {
                try? await Task.sleep(for: .milliseconds(16))
                log("open+\(step)")
            }
            exit(0)
        }
    }

    static var outputDirectory: URL? {
        ProcessInfo.processInfo.environment["BEADY_SNAPSHOT_DIR"].map { URL(fileURLWithPath: $0) }
    }

    /// `BEADY_VERIFY_SWITCH=/tmp/shots Beady --workspace /path/a --switch-to /path/b`: hosts the
    /// app's root content offscreen the way RootView does, lets workspace A settle, switches to
    /// B, and captures the window at intervals — so "does the theme hold through a workspace
    /// switch?" is answerable by machine. Dracula is previewed first, because the glitch is the
    /// difference between a chosen theme and the colours a freshly made hierarchy falls back to.
    static var switchDirectory: URL? {
        if let path = ProcessInfo.processInfo.environment["BEADY_VERIFY_SWITCH"] { return URL(fileURLWithPath: path) }
        // As an argument too, because `open` (which is what gets the harness real window
        // activation) passes arguments and not environment.
        if let index = CommandLine.arguments.firstIndex(of: "--verify-switch"),
           CommandLine.arguments.indices.contains(index + 1) {
            return URL(fileURLWithPath: CommandLine.arguments[index + 1])
        }
        return nil
    }

    static func verifySwitch(to directory: URL) -> Never {
        // A real, key window, as verifyKeys hosts: the sidebar's selection emphasis and tint
        // follow the window's key state — the very thing under test.
        let session = AppSession(preferences: nil)
        guard session.model != nil else { fail(session.openError ?? "no workspace; pass --workspace") }
        guard let argumentIndex = CommandLine.arguments.firstIndex(of: "--switch-to"),
              CommandLine.arguments.indices.contains(argumentIndex + 1) else { fail("pass --switch-to <path>") }
        let target = URL(fileURLWithPath: CommandLine.arguments[argumentIndex + 1])
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            fail("can't create \(directory.path): \(error.localizedDescription)")
        }

        // Mirrors RootView.content: same hosting, same (absence of) remounting, but with
        // preferences off, as snapshots keep them.
        struct Harness: View {
            let session: AppSession
            var body: some View {
                Group {
                    if let model = session.model {
                        WorkspaceView(model: model, ui: session.ui, themes: session.themes, run: session.run, persistsPreferences: false)
                    }
                }
                .themed(session.themes)
            }
        }

        session.themes.preview(Theme.dark(named: "Dracula"))
        let hosting = NSHostingView(rootView: Harness(session: session))
        let window = NSWindow(
            contentRect: CGRect(x: 100, y: 100, width: 1200, height: 800),
            styleMask: [.titled, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        // The selected sidebar row's emphasis is the machine-readable form of the glitch: an
        // emphasized row draws the accent selection, an unemphasized one the grey.
        func emphasis() -> String {
            guard let sidebar = allTables(in: hosting).first(where: { $0.tableColumns.count < 3 }) else { return "no sidebar table" }
            var states: [String] = []
            sidebar.enumerateAvailableRowViews { row, index in
                if row.isSelected { states.append("row \(index) selected, emphasized=\(row.isEmphasized)") }
            }
            return states.isEmpty ? "no selected row" : states.joined(separator: "; ")
        }
        let log = directory.appendingPathComponent("log.txt")
        func snap(_ name: String) {
            capture(hosting, to: directory.appendingPathComponent("\(name).png"))
            let line = "\(name).png loadState=\(String(describing: session.model?.loadState)) key=\(window.isKeyWindow) \(emphasis())\n"
            print(line, terminator: "")
            if let handle = try? FileHandle(forWritingTo: log) { handle.seekToEndOfFile(); handle.write(Data(line.utf8)); try? handle.close() }
        }
        FileManager.default.createFile(atPath: log.path, contents: nil)

        pump(timeout: 60) { session.model?.loadState != .idle && session.model?.loadState != .loading }
        pump(seconds: 1.0)
        snap("1-settled-a")
        session.open(target)
        pump(seconds: 0.05)
        snap("2-switch+0.05s")
        pump(seconds: 0.25)
        snap("3-switch+0.3s")
        pump(seconds: 0.7)
        snap("4-switch+1s")
        pump(timeout: 60) { session.model?.loadState != .idle && session.model?.loadState != .loading }
        pump(seconds: 2.0)
        snap("5-switch-settled")
        // The duplicate affordance, exercised the way the sidebar's context menu runs it: the
        // copy must appear under My Views.
        _ = session.model?.duplicateView(.pipeline)
        pump(seconds: 0.6)
        snap("6-duplicated-pipeline")
        window.close()
        exit(0)
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
        model.viewID = .frontier
        captureWorkspace("1-open-list")
        session.themes.appearance = .light
        captureWorkspace("1b-open-list-light")
        session.themes.appearance = .dark

        model.viewID = .inFlight
        captureWorkspace("2-in-flight-grouped-by-status")

        model.viewID = .stuck
        captureWorkspace("2b-blocked-view")

        model.viewID = .everything
        model.layout = .board
        captureWorkspace("3-all-board-by-lifecycle")

        // A search that leaves the board shorter than the pane: it must stay at the top.
        model.searchText = "distance"
        captureWorkspace("3b-board-narrowed-by-search")
        model.searchText = ""

        model.viewID = .frontier
        model.toggleFilterValue("1", in: .priority)
        model.toggleFilterValue("2", in: .priority)
        topLabels.prefix(1).forEach { model.toggleFilterValue($0, in: .labels) }
        captureWorkspace("4-open-with-filter-chips")

        // Nothing matches: the filter bar must stay its own height, not grow into the gap.
        model.searchText = "zzzz-nothing-matches-this"
        captureWorkspace("4b-empty-list")
        model.searchText = ""

        // Back to In Flight: its own filters, not Ready's.
        model.viewID = .inFlight
        captureWorkspace("5-in-flight-keeps-its-own-filters")

        // Views as the sidebar (bdv-jlx.4): a user view in My Views, Ready modified with the
        // Save control and the dot, Pipeline as a board, and a board that has collapsed to one
        // column saying so. Preferences are off, so none of this is kept.
        model.viewID = .everything
        model.toggleFilterValue("epic", in: .type)
        model.saveAsNewView(name: "Epics")
        model.viewID = .frontier
        model.toggleFilterValue("1", in: .priority)
        captureWorkspace("20-sidebar-views-and-modified-frontier")
        model.reset()
        model.viewID = .pipeline
        captureWorkspace("21-pipeline-board")
        // The same board with sub-tasks folded into their parents' cards, the biggest one open.
        model.nestsSubtasks = true
        if let parent = model.boardColumns.flatMap(\.cards).max(by: { $0.children.count < $1.children.count }), !parent.children.isEmpty {
            model.toggleBoardCard(parent.id)
        }
        captureWorkspace("25-pipeline-board-nested")
        model.nestsSubtasks = false
        // On a workspace whose live beads sit in one lifecycle column, 21 is a list; asking for
        // the board anyway shows what there is to split.
        model.chooseLayout(.board)
        captureWorkspace("21b-pipeline-board-asked-for")
        model.showBoardAsList()
        model.viewID = .everything
        model.toggleFilterValue(StatusCategory.active.rawValue, in: .lifecycle)
        model.layout = .board
        model.grouping = .none
        captureWorkspace("22-board-nothing-to-split")
        model.reset()
        model.viewID = .frontier

        let parents = snapshot.issues.filter { !snapshot.children(of: $0.id).isEmpty }
        if let biggest = parents.max(by: { (snapshot.progress(of: $0.id)?.total ?? 0) < (snapshot.progress(of: $1.id)?.total ?? 0) }) {
            // Under Everything, so the whole subtree shows, not only what Ready lets through.
            model.viewID = .everything
            model.focus(on: biggest.id)
            model.layout = .tree
            captureWorkspace("6-focused-bead-tree")
            model.reset()
            model.viewID = .frontier
        }

        model.viewID = .frontier
        capture("7-filter-menu-priority", FilterMenu(model: model, initialField: .priority).padding())
        // The workspace switcher's list: the recents this Mac knows, the open one ticked.
        capture("23-workspace-switcher", WorkspaceList(workspaces: session.ui.recentWorkspaces, current: session.ui.currentWorkspacePath, run: { _ in }).padding())

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
        // The Reset Configuration sheet, over a made-up but typical inventory: snapshot runs keep
        // preferences off, so there is nothing real to count.
        capture("19-reset-configuration", ResetConfigurationSheet(
            inventory: ConfigurationInventory(
                presentKeys: ["recentWorkspaces", "views", "liveViews", "view", "appearance", "textSize", "issueListColumns", "inspectorWidth", "eventsJournalTurnedOn", "NSNavPanelExpandedSizeForOpenMode"],
                recentWorkspaces: 3, journalWorkspaces: 2, libraryViews: 4
            ),
            onExport: {}, onReset: { _ in }, onCancel: {}
        ))
        // Previewing a light theme from a dark setting: the case where the controls went grey.
        session.themes.preview(Theme.light(named: "Solarized Light"))
        capture("11b-themes-light-preview", ThemePickerView(themes: session.themes, onClose: {}))
        session.themes.cancelPreview()

        // The detail pane after following a blocker link: the back bar has something to do.
        if let waiting = snapshot.issues.first(where: { !snapshot.openBlockers(of: $0).isEmpty }),
           let blocker = snapshot.openBlockers(of: waiting).first {
            model.viewID = .everything
            model.selection = waiting.id
            model.selection = blocker.id
            capture("15-detail-with-back", IssueDetailView(model: model).frame(width: 420, height: 700))
            // The dependency graph pinned under the details, following the selection.
            session.ui.showsGraphPane = true
            capture("24-detail-with-graph-pane", IssueDetailView(model: model, ui: session.ui).frame(width: 420, height: 820))
            session.ui.showsGraphPane = false
            // Nothing selected but history behind it: the bar stays at the top and the placeholder
            // centres in what's left, at two heights, and says what the arrows do.
            model.selection = nil
            capture("15b-detail-empty-with-history", IssueDetailView(model: model).frame(width: 420, height: 700))
            capture("15c-detail-empty-short", IssueDetailView(model: model).frame(width: 420, height: 340))
        }

        model.selection = nil
        capture("10-new-bead", NewBeadForm(model: model, onCancel: {}))

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
        // Whole means whole: the graph follows the view by default now.
        session.ui.graphFollowsView = false
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
