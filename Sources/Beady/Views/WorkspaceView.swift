import AppKit
import BeadsCore
import BeadsPresentation
import SwiftUI

struct WorkspaceView: View {
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The window's undo manager: bead changes register on it, so ⌘Z and the Edit menu work
    /// the way they do everywhere on the Mac. Nil in offscreen snapshots.
    @Environment(\.undoManager) private var windowUndoManager
    @Bindable var model: WorkspaceModel
    /// Panels and sheets, shared with the menu bar so both run the same commands.
    let ui: WorkspaceUI
    /// Appearance settings, for the ⌘T sheet; nil in offscreen snapshots.
    var themes: ThemeStore?
    /// Runs a command; the session decides what each one means.
    let run: (AppCommand) -> Void
    /// Takes back a change listed under Changes that offers it; the session reports a failure.
    let undo: (ChangeRecord) -> Void
    /// Off for offscreen snapshots, so they neither pick up nor overwrite the saved view.
    var persistsPreferences = true
    /// Imports .beadyview files dropped on the sidebar; the session does the work.
    var importFiles: ([URL]) -> Void = { _ in }
    @AppStorage("view") private var storedView = IssueView.ID.frontier.rawValue
    /// Where older Beadys kept the last lifecycle view; read once and moved over.
    @AppStorage("scope") private var legacyScope = ""
    @AppStorage("inspectorWidth") private var inspectorWidth = 360.0
    /// `FocusState` as a plain DynamicProperty: Command Line Tools lack the @State macro plugin.
    private var searchFocus = FocusState<Bool>()
    private var escapeMonitor = State<Any?>(initialValue: nil)

    init(
        model: WorkspaceModel,
        ui: WorkspaceUI,
        themes: ThemeStore? = nil,
        run: @escaping (AppCommand) -> Void = { _ in },
        undo: @escaping (ChangeRecord) -> Void = { _ in },
        persistsPreferences: Bool = true,
        importFiles: @escaping ([URL]) -> Void = { _ in }
    ) {
        self.model = model
        self.ui = ui
        self.themes = themes
        self.run = run
        self.undo = undo
        self.persistsPreferences = persistsPreferences
        self.importFiles = importFiles
    }

    var body: some View {
        NavigationSplitView {
            SidebarView(model: model, ui: ui, run: run, importFiles: importFiles)
                // Anywhere in the sidebar is away from a bead: a pane that came with one closes.
                .background(clickAwayWatcher)
                .navigationSplitViewColumnWidth(min: 200, ideal: 240)
        } detail: {
            // Not `.inspector`: that grows the right pane by pushing the whole window's layout,
            // which squeezed the sidebar and snapped it back. Here the center pane is the only
            // thing that gives way, and each pane animates on its own.
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    FilterBar(model: model, ui: ui, run: run)
                        // So is the filter bar. A floating pane moves nothing when it goes, so
                        // the control that was clicked is still under the pointer and still works.
                        .background(clickAwayWatcher)
                    content
                        // Switching sidebar views must not leave the sidebar's own list holding the
                        // keyboard — otherwise the first arrow key after a click walks the sidebar
                        // instead of the beads.
                        .background(FocusesOnChange(trigger: model.viewID))
                }
                .frame(maxWidth: .infinity)
                // Pinned, the pane is docked: the beads make room for it.
                if ui.details == .pinned {
                    Color.clear.frame(width: inspectorWidth + InspectorDivider.thickness)
                }
            }
            // The pane itself always lies over that row, at its trailing edge. Peeking, that is
            // all there is to it: it came up for one bead and will be gone again, so it flies
            // in over the beads and out without moving anything underneath. Pinning it only
            // clears the room above, so the pane stays put while the beads step aside.
            .overlay(alignment: .trailing) {
                if ui.details.isOpen {
                    detailsPane(floating: ui.details.floats)
                        .shadow(color: .black.opacity(ui.details.floats ? 0.22 : 0), radius: 14, x: -4)
                        .transition(paneTransition)
                }
            }
            .clipped()
            .animation(.smooth(duration: 0.25), value: ui.details)
        }
        .background(theme.background)
        .toolbarBackground(theme.surface, for: .windowToolbar)
        .navigationTitle(model.viewTitle)
        .navigationSubtitle(subtitle)
        .searchable(text: $model.searchText, placement: .toolbar, prompt: "Search this view")
        .searchFocused(searchFocus.projectedValue)
        .onChange(of: ui.searchFocusRequests) { searchFocus.wrappedValue = true }
        .onChange(of: searchFocus.wrappedValue) { ui.isSearchFocused = searchFocus.wrappedValue }
        .toolbar { toolbar }
        .sheet(isPresented: sheetPresented) { sheetContent }
        .sheet(isPresented: Binding(get: { ui.showsShareBeads }, set: { ui.showsShareBeads = $0 })) {
            ShareBeadsSheet(model: model, ui: ui, run: run)
        }
        .sheet(isPresented: Binding(get: { ui.showsWorkspaceSetup }, set: { ui.showsWorkspaceSetup = $0 })) {
            WorkspaceSetupSheet(model: model, ui: ui, run: run)
        }
        .sheet(isPresented: Binding(get: { ui.showsSaveAsNewView }, set: { ui.showsSaveAsNewView = $0 })) {
            SaveAsNewViewSheet(model: model, ui: ui)
        }
        .sheet(isPresented: Binding(get: { ui.changingIconOf != nil }, set: { if !$0 { ui.changingIconOf = nil } })) {
            ChangeIconSheet(model: model, ui: ui)
        }
        .alert("Rename View", isPresented: Binding(get: { ui.renamingView != nil }, set: { if !$0 { ui.renamingView = nil } })) {
            TextField("Name", text: Binding(get: { ui.renameText }, set: { ui.renameText = $0 }))
            Button("Rename") {
                if let id = ui.renamingView { model.renameView(id, to: ui.renameText) }
                ui.renamingView = nil
            }
            Button("Cancel", role: .cancel) { ui.renamingView = nil }
        }
        .onAppear(perform: restoreStoredView)
        .onAppear { model.attachUndoManager(windowUndoManager) }
        // The environment's undo manager can arrive after the first appearance.
        .onChange(of: windowUndoManager.map(ObjectIdentifier.init)) { model.attachUndoManager(windowUndoManager) }
        .onChange(of: ObjectIdentifier(model)) {
            // A switched workspace arrives as a new model in the same hierarchy (RootView says
            // why there is no remount), so whatever captured the old model re-arms here. The
            // session detached the old model; the window's undo stack starts over with the new.
            model.attachUndoManager(windowUndoManager)
            restoreStoredView()
            if let monitor = escapeMonitor.wrappedValue { NSEvent.removeMonitor(monitor) }
            escapeMonitor.wrappedValue = nil
            watchEscape()
        }
        .onChange(of: model.viewID) {
            if persistsPreferences { storedView = model.viewID.rawValue }
        }
        .onChange(of: model.selection) {
            // Selecting a bead brings the pane up if it was hidden; letting go of the bead takes
            // that pane away again. The pane can leave in this same update, before its own
            // onChange runs, so an edit it had open ends here too.
            model.endEditing()
            ui.follow(selection: model.selection)
        }
        .onChange(of: model.activity.first?.id) {
            if model.activity.first?.succeeded == true { ui.showsNewBead = false }
        }
        .onAppear(perform: watchEscape)
        .onDisappear {
            if let monitor = escapeMonitor.wrappedValue { NSEvent.removeMonitor(monitor) }
            escapeMonitor.wrappedValue = nil
        }
        .task(id: ObjectIdentifier(model)) {
            await model.load()
            // Once per open, not per reload: this is the read that asks the remote.
            await model.refreshSharing()
            // FSEvents on the .beads folder is the real trigger (AppSession). This is only a
            // backstop for changes it can't see, such as a database on a network volume.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                await model.refreshIfChanged()
            }
        }
    }

    /// The details, with the edge you drag to resize them. A floating pane keeps showing its
    /// bead while it leaves; a docked one says when nothing is selected.
    private func detailsPane(floating: Bool) -> some View {
        HStack(spacing: 0) {
            InspectorDivider(width: $inspectorWidth)
            IssueDetailView(model: model, ui: ui, leavesWithItsBead: floating)
                .scrollContentBackground(.hidden)
                .frame(width: inspectorWidth)
        }
        .background(theme.background)
        .background(ViewMarker { ui.detailsPaneView = $0 })
    }

    /// Planted behind the sidebar and the filter bar: a click there lets go of the bead a
    /// floating pane came up for. Not a click on the pane itself, where it covers the bar's end.
    private var clickAwayWatcher: some View {
        ClickWatcher(except: { ui.detailsCover($0, in: $1) }) { ui.clickedAway(in: model) }
    }

    /// The pane slides in from the trailing edge; under Reduce Motion it fades instead.
    private var paneTransition: AnyTransition {
        reduceMotion ? .opacity : .move(edge: .trailing)
    }

    @ViewBuilder
    private var content: some View {
        switch model.loadState {
        case .idle, .loading:
            ProgressView("Loading beads…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            ContentUnavailableView {
                Label("Couldn't load beads", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("Try Again") { Task { await model.load() } }
            }
        case .loaded:
            if model.visibleIssues.isEmpty && model.presentedLayout != .board {
                let narrowed = model.hasClearableFilters || !model.searchText.isEmpty
                ContentUnavailableView {
                    if narrowed {
                        Label("Nothing matches", systemImage: "line.3.horizontal.decrease.circle")
                    } else {
                        Label("No issues", systemImage: "line.3.horizontal.decrease.circle")
                    }
                } description: {
                    if narrowed {
                        Text("No issues in \(model.viewTitle) match this view's filters.")
                    } else {
                        Text("\(model.viewTitle) is empty.")
                    }
                } actions: {
                    if model.hasClearableFilters || !model.searchText.isEmpty {
                        Button("Clear Filters") {
                            model.clearFilters()
                            model.searchText = ""
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.presentedLayout == .board, let split = model.boardNeedsSplitting {
                // Only reached by asking for the board: a view never opens here on its own. Say
                // so, and offer the groupings that would split it, or the list.
                ContentUnavailableView {
                    Label("Nothing to split", systemImage: "rectangle.split.3x1")
                } description: {
                    let grouping = DisplayText.grouping(model.grouping == .none ? .category : model.grouping)
                    if split.groupings.isEmpty {
                        Text("Everything here lands in one \(grouping) column, and no other grouping would spread it out.")
                    } else {
                        Text("Everything here lands in one \(grouping) column. Group by something that would spread it out, or show the list:")
                    }
                } actions: {
                    ForEach(split.groupings) { grouping in
                        Button(DisplayText.grouping(grouping)) { model.grouping = grouping }
                            .help(DisplayText.help(for: grouping))
                    }
                    Button("Show as List") { model.showBoardAsList() }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                switch model.presentedLayout {
                case .list: IssueListView(model: model, columns: ui.columns)
                case .board: IssueBoardView(model: model, ui: ui)
                case .tree: IssueOutlineView(model: model)
                }
            }
        }
    }

    /// One sheet serves both the new-bead form and the confirmation of any change, so a create
    /// can move from form to confirmation (and back, on cancel) without stacking sheets.
    /// Escape lets go of the selected bead in the list, tree or board — which closes a details
    /// pane that only opened for that bead (`DetailsPane`). It stands down whenever
    /// something else has a better claim on the key: a sheet (Escape cancels it), the search
    /// field (Escape clears it), any other text field, or an edit in progress. Text that can
    /// only be selected has no claim: clicking into the details to copy an id must not leave
    /// Escape dead.
    private func watchEscape() {
        guard escapeMonitor.wrappedValue == nil else { return }
        let model = model
        let ui = ui
        escapeMonitor.wrappedValue = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { @MainActor event in
            guard event.keyCode == 53,
                  event.window?.identifier?.rawValue.contains("dependencies") != true,
                  model.selection != nil,
                  model.draft == nil,
                  model.pendingChange == nil,
                  !ui.isSheetOpen,
                  !ui.isSearchFocused,
                  (NSApp.keyWindow?.firstResponder as? NSTextView)?.isEditable != true
            else { return event }
            model.selection = nil
            return nil
        }
    }

    /// The last-used view, remembered across launches and applied to each workspace as it opens.
    private func restoreStoredView() {
        guard persistsPreferences else { return }
        if !legacyScope.isEmpty {
            if let id = ViewLibrary.builtIn(forScope: legacyScope) { storedView = id.rawValue }
            legacyScope = ""
        }
        let id = IssueView.ID(rawValue: storedView)
        if model.views.contains(where: { $0.id == id }) { model.viewID = id }
    }

    /// The whole backup UI: one word about whether this database could be recovered, and a click
    /// to do something about it.
    ///
    /// It sits in the toolbar rather than the window subtitle: feeding it through
    /// `navigationSubtitle` put a state read into the title-bar update and AttributeGraph
    /// reported a cycle for it.
    @ViewBuilder
    private var backupIndicator: some View {
        if let summary = model.backupSummary {
            Button {
                run(model.backup.isConfigured ? .backUpNow : .setUpBackup)
            } label: {
                Label(summary, systemImage: symbol)
            }
            .labelStyle(.titleAndIcon)
            .controlSize(.small)
            .disabled(model.isBackingUp)
            .help(helpText)
        }
    }

    private var symbol: String {
        if model.isBackingUp { return "arrow.triangle.2.circlepath" }
        return model.backup.lastSync == nil ? "externaldrive.badge.exclamationmark" : "externaldrive.badge.checkmark"
    }

    private var helpText: String {
        guard let destination = model.backup.destination else {
            return String(localized: "Nothing is backing this database up. bd's JSONL export carries the issues, not their history — click to choose a folder.")
        }
        if let size = model.backup.databaseSize {
            return String(localized: "Backed up to \(destination) · \(size). Click to back up now.", comment: "Tooltip: the backup folder, then the database size")
        }
        return String(localized: "Backed up to \(destination). Click to back up now.", comment: "Tooltip: the backup folder")
    }

    /// One sheet, shown for whichever thing is open; a change being confirmed wins.
    private var sheetPresented: Binding<Bool> {
        Binding(
            get: { model.pendingChange != nil || ui.showsNewBead || ui.showsPalette || ui.showsShortcuts || ui.showsThemes },
            set: { presented in
                if !presented {
                    model.cancelPendingChange()
                    ui.showsNewBead = false
                    ui.showsPalette = false
                    ui.showsShortcuts = false
                    if ui.showsThemes { themes?.cancelPreview() }
                    ui.showsThemes = false
                }
            }
        )
    }

    @ViewBuilder
    private var sheetContent: some View {
        if let pending = model.pendingChange {
            ChangeConfirmationView(model: model, pending: pending) { model.cancelPendingChange() }
        } else if ui.showsNewBead {
            NewBeadForm(model: model) { ui.showsNewBead = false }
        } else if ui.showsPalette {
            CommandPaletteView(model: model, ui: ui, run: run) { ui.showsPalette = false }
        } else if ui.showsShortcuts {
            ShortcutsView(model: model, ui: ui) { ui.showsShortcuts = false }
        } else if ui.showsThemes, let themes {
            ThemePickerView(themes: themes) { ui.showsThemes = false }
        }
    }

    private var subtitle: String {
        guard let snapshot = model.snapshot else { return model.title }
        var parts = [model.title, String(localized: "\(model.visibleIssues.count) of \(snapshot.issues.count)", comment: "Window subtitle: beads shown, beads in the database")]
        if !model.canEdit { parts.append(String(localized: "read-only", comment: "Window subtitle")) }
        if snapshot.unreadableRecordCount > 0 {
            parts.append(String(localized: "\(snapshot.unreadableRecordCount) unreadable records skipped", comment: "Window subtitle; plural on the number of records"))
        }
        if let lastLoaded = model.lastLoaded {
            parts.append(String(localized: "refreshed \(lastLoaded.formatted(date: .omitted, time: .standard))", comment: "Window subtitle; the value is a time of day"))
        }

        return parts.joined(separator: " · ")
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            // Where the beads live besides this Mac. Until bd has said, or when it won't, the
            // backup word stands in, as it did before sharing had one.
            if model.sharingSummary != nil {
                SharingIndicator(model: model, ui: ui, run: run)
            } else {
                backupIndicator
            }

            Button {
                run(.newBead)
            } label: {
                Label("New Bead", systemImage: "plus")
            }
            .disabled(!model.canEdit)
            .help("Create a bead (⌘N)")

            Menu {
                if model.activity.isEmpty {
                    Text("No changes this session")
                }
                ForEach(model.activity) { record in
                    Button {
                        if let id = record.issueID { model.selection = id }
                    } label: {
                        Label(
                            "\(record.summary) · \(record.date.formatted(date: .omitted, time: .shortened))",
                            systemImage: record.succeeded ? "checkmark.circle" : "xmark.octagon"
                        )
                    }
                    .help(record.message ?? String(localized: "Applied and verified", comment: "Tooltip on a change that landed"))
                    // Bead changes are taken back with ⌘Z, not here: this menu is the history.
                    if record.undo != nil {
                        Button {
                            undo(record)
                        } label: {
                            Label("Undo: turn the journal back off", systemImage: "arrow.uturn.backward")
                        }
                        .help("Writes the journal settings back to off, in this workspace's bd config")
                    }
                }
            } label: {
                Label("Changes", systemImage: "clock.arrow.circlepath")
            }
            .help("Changes made this session")

            Button {
                run(.toggleDetails)
            } label: {
                Label("Details", systemImage: "sidebar.right")
            }
            .help("Show or hide issue details")
        }
    }
}

/// The draggable edge between the center pane and the details.
private struct InspectorDivider: View {
    @Environment(\.theme) private var theme
    @Binding var width: Double
    private var startWidth = State<Double?>(initialValue: nil)

    static let range = 280.0...640.0
    /// The hairline and the margin either side of it that takes the drag.
    static let thickness = 7.0

    init(width: Binding<Double>) {
        _width = width
    }

    var body: some View {
        Rectangle()
            .fill(theme.border)
            .frame(width: 1)
            .padding(.horizontal, (Self.thickness - 1) / 2)
            .contentShape(Rectangle())
            .onHover { inside in
                if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { drag in
                        let start = startWidth.wrappedValue ?? width
                        startWidth.wrappedValue = start
                        width = min(max(start - drag.translation.width, Self.range.lowerBound), Self.range.upperBound)
                    }
                    .onEnded { _ in startWidth.wrappedValue = nil }
            )
    }
}

/// Reports a left click that lands on whatever this is planted behind with `.background(...)`,
/// without taking the click: the row, button or drag under the pointer still gets it.
///
/// A SwiftUI gesture can't do this over a `List` — the table underneath takes the mouse first —
/// so it watches the window's events and compares against its own frame. Clicks in a sheet,
/// popover or menu belong to other windows and never match; the strip under the toolbar is left
/// out, since a sidebar runs up behind it.
struct ClickWatcher: NSViewRepresentable {
    /// True for a point, in the window's coordinates, where something lying over this view
    /// keeps the click for itself.
    var except: @MainActor (CGPoint, NSWindow) -> Bool = { _, _ in false }
    let onClick: @MainActor () -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.watch(view)
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        context.coordinator.except = except
        context.coordinator.onClick = onClick
    }

    static func dismantleNSView(_ view: NSView, coordinator: Coordinator) {
        coordinator.stop()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(except: except, onClick: onClick)
    }

    @MainActor
    final class Coordinator {
        var except: @MainActor (CGPoint, NSWindow) -> Bool
        var onClick: @MainActor () -> Void
        private var monitor: Any?

        init(except: @escaping @MainActor (CGPoint, NSWindow) -> Bool, onClick: @escaping @MainActor () -> Void) {
            self.except = except
            self.onClick = onClick
        }

        func watch(_ view: NSView) {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { @MainActor [weak self, weak view] event in
                // Control-click is a right click: it opens a menu, it doesn't click away.
                if let self, let view, let window = view.window, event.window === window,
                   window.attachedSheet == nil,
                   !event.modifierFlags.contains(.control),
                   event.locationInWindow.y <= window.contentLayoutRect.maxY,
                   view.convert(view.bounds, to: nil).contains(event.locationInWindow),
                   !self.except(event.locationInWindow, window) {
                    self.onClick()
                }
                return event
            }
        }

        func stop() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }
    }
}

/// Hands back the `NSView` planted behind a SwiftUI view with `.background(...)`: its frame in
/// the window is that view's, which is how AppKit-side code finds out where a SwiftUI view is.
struct ViewMarker: NSViewRepresentable {
    let found: @MainActor (NSView) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        found(view)
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {}
}
