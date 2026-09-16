import BeadsCore
import BeadsPresentation
import SwiftUI

struct WorkspaceView: View {
    @Bindable var model: WorkspaceModel
    /// Panels and sheets, shared with the menu bar so both run the same commands.
    let ui: WorkspaceUI
    /// Runs a command; the session decides what each one means.
    let run: (AppCommand) -> Void
    /// Off for offscreen snapshots, so they neither pick up nor overwrite the saved view.
    var persistsPreferences = true
    @AppStorage("scope") private var storedScope = Scope.open.rawValue
    /// `FocusState` as a plain DynamicProperty: Command Line Tools lack the @State macro plugin.
    private var searchFocus = FocusState<Bool>()

    init(model: WorkspaceModel, ui: WorkspaceUI, run: @escaping (AppCommand) -> Void = { _ in }, persistsPreferences: Bool = true) {
        self.model = model
        self.ui = ui
        self.run = run
        self.persistsPreferences = persistsPreferences
    }

    var body: some View {
        NavigationSplitView {
            SidebarView(model: model)
                .navigationSplitViewColumnWidth(min: 200, ideal: 240)
        } detail: {
            VStack(spacing: 0) {
                FilterBar(model: model, ui: ui, run: run)
                content
            }
            .inspector(isPresented: inspectorPresented) {
                IssueDetailView(model: model)
                    .inspectorColumnWidth(min: 280, ideal: 360, max: 640)
            }
        }
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
                case .board: IssueBoardView(model: model)
                case .tree: IssueOutlineView(model: model)
                }
            }
        }
    }

    /// One sheet serves both the new-bead form and the confirmation of any change, so a create
    /// can move from form to confirmation (and back, on cancel) without stacking sheets.
    private var inspectorPresented: Binding<Bool> {
        Binding(get: { ui.showsInspector }, set: { ui.showsInspector = $0 })
    }

    /// One sheet, shown for whichever thing is open; a change being confirmed wins.
    private var sheetPresented: Binding<Bool> {
        Binding(
            get: { model.pendingChange != nil || ui.showsNewBead || ui.showsPalette || ui.showsShortcuts },
            set: { presented in
                if !presented {
                    model.cancelPendingChange()
                    ui.showsNewBead = false
                    ui.showsPalette = false
                    ui.showsShortcuts = false
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
            CommandPaletteView(model: model, run: run) { ui.showsPalette = false }
        } else if ui.showsShortcuts {
            ShortcutsView(model: model) { ui.showsShortcuts = false }
        }
    }

    private var subtitle: String {
        guard let snapshot = model.snapshot else { return model.title }
        var parts = [model.title, "\(model.visibleIssues.count) of \(snapshot.issues.count)"]
        if !model.canEdit { parts.append("read-only") }
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
                Task { await model.load() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .disabled(model.isLoading)
            .help("Reload from bd (⌘R). Changes are picked up automatically too.")

            Button {
                run(.toggleDetails)
            } label: {
                Label("Details", systemImage: "sidebar.right")
            }
            .help("Show or hide issue details")
        }
    }
}
