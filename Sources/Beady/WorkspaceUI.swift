import BeadsCore
import BeadsPresentation
import Observation

/// View state that both the window and the menu bar need to reach: which panels are open, and
/// the saved column layout. The model owns the data; this owns what's on screen around it.
@MainActor
@Observable
final class WorkspaceUI {
    var showsInspector = true
    var showsNewBead = false
    var showsPalette = false
    var showsShortcuts = false
    var showsThemes = false
    var showsFilterMenu = false
    var showsDisplayOptions = false
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
        showsPalette || showsThemes || showsNewBead || showsShortcuts
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
