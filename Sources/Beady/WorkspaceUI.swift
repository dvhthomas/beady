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
    var showsFilterMenu = false
    var showsDisplayOptions = false
    /// True while the search field has the keyboard. Single-key shortcuts stand down then, so
    /// typing "?" into a search reaches the field instead of opening the shortcut sheet.
    var isSearchFocused = false
    /// Bumped to ask the search field to take focus; the view watches it.
    private(set) var searchFocusRequests = 0

    @ObservationIgnored let columns = ColumnLayout()

    func focusSearch() {
        searchFocusRequests += 1
    }
}
