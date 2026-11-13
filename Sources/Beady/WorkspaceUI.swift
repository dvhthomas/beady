import AppKit
import BeadsCore
import BeadsPresentation
import Foundation
import Observation

/// View state that both the window and the menu bar need to reach: which panels are open, and
/// the saved column layout. The model owns the data; this owns what's on screen around it.
@MainActor
@Observable
final class WorkspaceUI {
    /// Where the pinned pane's state is remembered between launches; nil for the offscreen
    /// snapshots, which must leave the saved layout alone.
    @ObservationIgnored private let preferences: UserDefaults?
    private static let graphPaneKey = "inspectorShowsGraph"
    private static let graphPaneHeightKey = "inspectorGraphHeight"

    init(preferences: UserDefaults? = nil) {
        self.preferences = preferences
        showsGraphPane = preferences?.bool(forKey: Self.graphPaneKey) ?? false
        let height = preferences?.double(forKey: Self.graphPaneHeightKey) ?? 0
        graphPaneHeight = height > 0 ? height : 280
    }

    /// The details pane: hidden, pinned open, or open only for the bead that was just selected.
    /// The rules for moving between those are `DetailsPane`'s.
    var details = DetailsPane.pinned
    /// Whether the pane is on screen. Setting it true is asking for the pane by name, which pins
    /// a hidden one.
    var showsInspector: Bool {
        get { details.isOpen }
        set { details = newValue ? details.shown() : .closed }
    }

    /// The bead the pane last showed. A floating pane goes on showing it while it slides away,
    /// after the selection that brought it has already been let go.
    var lastShownBead: IssueID?

    /// The selection changed: a hidden pane comes up for a bead, and one that came up for a
    /// bead goes when the bead is let go.
    func follow(selection: IssueID?) {
        if let selection { lastShownBead = selection }
        details = details.following(selection: selection)
    }

    /// Where the pane is in the window, for telling a click inside it from a click away: floating,
    /// it lies over the end of the filter bar.
    @ObservationIgnored weak var detailsPaneView: NSView?

    /// True when `point`, in `window`'s coordinates, is on the details pane.
    func detailsCover(_ point: CGPoint, in window: NSWindow) -> Bool {
        guard details.isOpen, let pane = detailsPaneView, pane.window === window else { return false }
        return pane.convert(pane.bounds, to: nil).contains(point)
    }

    /// The pane's own close button: the pane goes, and so does its hold on the bead — a card
    /// left highlighted with nothing showing it would need a second click to bring back.
    func closeDetails(of model: WorkspaceModel) {
        model.selection = nil
        details = .closed
    }

    /// A click somewhere that isn't the pane or a bead. A pane that came with the bead lets go
    /// of it, and closes as the selection empties; a pinned one stays. Like Escape, it stands
    /// down while an edit is open, so a stray click can't throw away what was typed.
    func clickedAway(in model: WorkspaceModel) {
        guard details.letsGoOnClickAway, model.draft == nil else { return }
        model.selection = nil
    }

    /// The dependency graph pinned into the details pane, following the selected bead. A pane
    /// rather than a window when the chain matters while you work down a list.
    var showsGraphPane: Bool {
        didSet { preferences?.set(showsGraphPane, forKey: Self.graphPaneKey) }
    }
    /// How tall the pinned graph is; dragged, and kept.
    var graphPaneHeight: Double {
        didSet { preferences?.set(graphPaneHeight, forKey: Self.graphPaneHeightKey) }
    }
    var showsNewBead = false
    var showsPalette = false
    var showsShortcuts = false
    var showsThemes = false
    /// The Reset Configuration sheet, from ⌘P or Settings.
    var showsResetConfiguration = false
    /// Offers a relaunch after the language changed from ⌘P; Settings shows its own button.
    var showsRelaunchPrompt = false
    /// The workspaces the switcher and the palette offer, in Open Recent's order, and which one
    /// is open. The session keeps both current; the sidebar and the palette only read them.
    var recentWorkspaces: [RecentWorkspace] = []
    var currentWorkspacePath: String?
    var showsFilterMenu = false
    var showsDisplayOptions = false
    /// The Save as New View sheet: name and icon live here so the sheet's fields are observable.
    var showsSaveAsNewView = false
    var newViewName = ""
    var newViewSymbol = ViewIcon.defaultUserChoice
    /// The user view being renamed, with the name as typed so far.
    var renamingView: IssueView.ID?
    var renameText = ""
    /// The user view whose icon is being changed, and the choice so far.
    var changingIconOf: IssueView.ID?
    var chosenIcon = ViewIcon.defaultUserChoice

    func promptSaveAsNewView(suggesting name: String) {
        newViewName = name
        newViewSymbol = ViewIcon.defaultUserChoice
        showsSaveAsNewView = true
    }

    func promptChangeIcon(of view: IssueView) {
        chosenIcon = view.symbol
        changingIconOf = view.id
    }

    func promptRename(_ view: IssueView) {
        renameText = view.name
        renamingView = view.id
    }
    /// True while the search field has the keyboard. Single-key shortcuts stand down then, so
    /// typing "?" into a search reaches the field instead of opening the shortcut sheet.
    var isSearchFocused = false
    /// Bumped to ask the search field to take focus; the view watches it.
    private(set) var searchFocusRequests = 0

    /// The palette's own state. It lives here rather than in the view because a
    /// `State(initialValue:)` stored property — this project's workaround for the @State macro
    /// missing under Command Line Tools — didn't reliably receive what was typed, leaving the
    /// list unfiltered while the field showed the text.
    var paletteQuery = ""
    /// The dependency window's state, here for the same reason as the palette's.
    var graphFocus: IssueID?
    var graphIncludesFinished = true
    /// Scoped to the beads the current view shows, or the whole database.
    var graphFollowsView = true
    var graphZoom: Double = 1
    /// Bumped to ask the root view to open the dependency window; only a view can do that.
    private(set) var graphWindowRequests = 0

    func openGraph(focusing id: IssueID?) {
        if let id { graphFocus = id }
        graphWindowRequests += 1
    }
    var paletteHighlight = 0

    @ObservationIgnored let columns = ColumnLayout()

    /// True while anything modal is up, so background key handling stands down.
    var isSheetOpen: Bool {
        showsPalette || showsThemes || showsNewBead || showsShortcuts || showsSaveAsNewView || renamingView != nil || changingIconOf != nil || showsResetConfiguration
    }

    /// Opens the palette empty, wherever it was left last time.
    func openPalette() {
        paletteQuery = ""
        paletteHighlight = 0
        showsPalette = true
    }

    func focusSearch() {
        searchFocusRequests += 1
    }
}
