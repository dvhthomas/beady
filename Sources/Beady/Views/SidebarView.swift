import BeadsCore
import BeadsPresentation
import SwiftUI

/// Navigation only, as in Linear: the built-in views. Filters live in each view's
/// header, and anything to do with one bead — including focusing on its subtree — happens in the
/// main panel, so epics aren't a special case here.
struct SidebarView: View {
    let model: WorkspaceModel
    @Environment(\.theme) private var theme
    @Environment(\.sidebarStyle) private var style

    var body: some View {
        List(selection: selection) {
            Section("Views") {
                ForEach(model.sidebarViews) { entry in
                    Label(entry.title, systemImage: entry.symbol)
                        .badge(entry.count)
                        .tag(entry.id)
                }
            }
        }
        // Themed: one coherent window. Translucent: macOS's own material, which no theme can
        // reproduce because it samples what's behind the window.
        .scrollContentBackground(style == .themed ? .hidden : .automatic)
        .background(style == .themed ? AnyShapeStyle(theme.surface) : AnyShapeStyle(.clear))
    }

    private var selection: Binding<IssueView.ID?> {
        Binding(get: { model.viewID }, set: { if let id = $0 { model.viewID = id } })
    }
}
