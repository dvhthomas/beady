import AppKit
import BeadsCore
import BeadsPresentation
import SwiftUI

struct WorkspaceView: View {
    @Environment(\.theme) private var theme
    @Bindable var model: WorkspaceModel
    /// Panels and sheets, shared with the menu bar so both run the same commands.
    let ui: WorkspaceUI
    /// Appearance settings, for the ⌘T sheet; nil in offscreen snapshots.
    var themes: ThemeStore?
    /// Runs a command; the session decides what each one means.
    let run: (AppCommand) -> Void
    /// Off for offscreen snapshots, so they neither pick up nor overwrite the saved view.
    var persistsPreferences = true
    @AppStorage("scope") private var storedScope = Scope.open.rawValue
    @AppStorage("inspectorWidth") private var inspectorWidth = 360.0
    /// `FocusState` as a plain DynamicProperty: Command Line Tools lack the @State macro plugin.
    private var searchFocus = FocusState<Bool>()
    private var escapeMonitor = State<Any?>(initialValue: nil)

    init(
        model: WorkspaceModel,
        ui: WorkspaceUI,
        themes: ThemeStore? = nil,
        run: @escaping (AppCommand) -> Void = { _ in },
        persistsPreferences: Bool = true
    ) {
        self.model = model
        self.ui = ui
        self.themes = themes
        self.run = run
        self.persistsPreferences = persistsPreferences
    }

    var body: some View {
        NavigationSplitView {
            SidebarView(model: model)
                .navigationSplitViewColumnWidth(min: 200, ideal: 240)
        } detail: {
            // Not `.inspector`: that grows the right pane by pushing the whole window's layout,
            // which squeezed the sidebar and snapped it back. Here the center pane is the only
            // thing that gives way, and each pane animates on its own.
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    FilterBar(model: model, ui: ui, run: run)
                    content
                        // Switching sidebar views must not leave the sidebar's own list holding the
                        // keyboard — otherwise the first arrow key after a click walks the sidebar
                        // instead of the beads.
                        .background(FocusesOnChange(trigger: model.source))
                }
                .frame(maxWidth: .infinity)
                if ui.showsInspector {
                    InspectorDivider(width: $inspectorWidth)
                    IssueDetailView(model: model)
                        .scrollContentBackground(.hidden)
                        .frame(width: inspectorWidth)
                        .background(theme.background)
                        .transition(.move(edge: .trailing))
                }
            }
            .clipped()
            .animation(.smooth(duration: 0.25), value: ui.showsInspector)
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
        .onAppear {
            guard persistsPreferences, let scope = Scope(rawValue: storedScope) else { return }
            model.source = .lifecycle(scope)
        }
        .onChange(of: model.source) {
            if persistsPreferences, case .lifecycle(let scope) = model.source { storedScope = scope.rawValue }
        }
        .onChange(of: model.selection) { if model.selection != nil { ui.showsInspector = true } }
        .onChange(of: model.activity.first?.id) {
            if model.activity.first?.succeeded == true { ui.showsNewBead = false }
        }
        .onAppear(perform: watchEscape)
        .onDisappear {
            if let monitor = escapeMonitor.wrappedValue { NSEvent.removeMonitor(monitor) }
            escapeMonitor.wrappedValue = nil
        }
        .task {
            await model.load()
            // FSEvents on the .beads folder is the real trigger (AppSession). This is only a
            // backstop for changes it can't see, such as a database on a network volume.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                await model.refreshIfChanged()
            }
        }
    }

    private func failedView(_ message: String) -> some View {
        ContentUnavailableView {
            Label("Couldn't load beads", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button("Try Again") { Task { await model.load() } }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.loadState {
        case .idle, .loading:
            ProgressView("Loading beads…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            if let mismatch = model.schemaMismatch {
                SchemaMismatchView(mismatch: mismatch, model: model, ui: ui, run: run)
            } else {
                failedView(message)
            }
        case .loaded:
            if model.visibleIssues.isEmpty && model.layout != .board {
                ContentUnavailableView {
                    Label(model.filter.isEmpty ? "No issues" : "Nothing matches", systemImage: "line.3.horizontal.decrease.circle")
                } description: {
                    Text(model.filter.isEmpty ? "\(model.viewTitle) is empty." : "No issues in \(model.viewTitle) match this view's filters.")
                } actions: {
                    if !model.filter.isEmpty {
                        Button("Clear Filters") {
                            model.clearFilters()
                            model.searchText = ""
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                switch model.layout {
                case .list: IssueListView(model: model, columns: ui.columns)
                case .board: IssueBoardView(model: model, ui: ui)
                case .tree: IssueOutlineView(model: model)
                }
            }
        }
    }

    /// One sheet serves both the new-bead form and the confirmation of any change, so a create
    /// can move from form to confirmation (and back, on cancel) without stacking sheets.
    /// Escape lets go of the selected bead in the list, tree or board. It stands down whenever
    /// something else has a better claim on the key: a sheet (Escape cancels it), the search
    /// field (Escape clears it), any other text field, or an edit in progress.
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
                  !(NSApp.keyWindow?.firstResponder is NSTextView)
            else { return event }
            model.selection = nil
            return nil
        }
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

    /// Shown only while there's a choice to make: bd is new enough to keep a change journal,
    /// it's off, and nobody has said no. Once it's on, or declined, it gets out of the way.
    @ViewBuilder
    private var journalIndicator: some View {
        if model.offersJournal {
            Button {
                run(.turnOnJournal)
            } label: {
                Label("Who's working?", systemImage: "person.2.badge.gearshape")
            }
            .labelStyle(.titleAndIcon)
            .controlSize(.small)
            .help("bd can record who made each change, so Beady can say which agent is working on a bead. Click to see what turning it on changes.")
        }
    }

    private var symbol: String {
        if model.isBackingUp { return "arrow.triangle.2.circlepath" }
        return model.backup.lastSync == nil ? "externaldrive.badge.exclamationmark" : "externaldrive.badge.checkmark"
    }

    private var helpText: String {
        guard let destination = model.backup.destination else {
            return "Nothing is backing this database up. bd's JSONL export carries the issues, not their history — click to choose a folder."
        }
        let size = model.backup.databaseSize.map { " · \($0)" } ?? ""
        return "Backed up to \(destination)\(size). Click to back up now."
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
            ShortcutsView(model: model) { ui.showsShortcuts = false }
        } else if ui.showsThemes, let themes {
            ThemePickerView(themes: themes) { ui.showsThemes = false }
        }
    }

    private var subtitle: String {
        guard let snapshot = model.snapshot else { return model.title }
        var parts = [model.title, "\(model.visibleIssues.count) of \(snapshot.issues.count)"]
        if model.isReadingPastSchemaSkew {
            parts.append("read-only: newer schema than your bd")
        } else if !model.canEdit {
            parts.append("read-only")
        }
        if snapshot.unreadableRecordCount > 0 {
            parts.append("\(snapshot.unreadableRecordCount) unreadable records skipped")
        }
        if let lastLoaded = model.lastLoaded {
            parts.append("refreshed \(lastLoaded.formatted(date: .omitted, time: .standard))")
        }

        return parts.joined(separator: " · ")
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            journalIndicator
            backupIndicator

            Button {
                run(.newBead)
            } label: {
                Label("New Bead", systemImage: "plus")
            }
            .disabled(!model.canEdit)
            .help("Create a bead (⌘N). Every change is confirmed before it's written.")

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
                    .help(record.message ?? "Applied and verified")
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

    init(width: Binding<Double>) {
        _width = width
    }

    var body: some View {
        Rectangle()
            .fill(theme.border)
            .frame(width: 1)
            .padding(.horizontal, 3)
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
