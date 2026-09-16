import BeadsCore
import BeadsPresentation
import SwiftUI

/// Navigation only, as in Linear: the built-in lifecycle views. Filters live in each view's
/// header, and anything to do with one bead — including focusing on its subtree — happens in the
/// main panel, so epics aren't a special case here.
struct SidebarView: View {
    let model: WorkspaceModel
    @Environment(\.theme) private var theme

    var body: some View {
        List(selection: selection) {
            Section("Views") {
                ForEach(model.sidebarViews) { entry in
                    Label(entry.title, systemImage: symbol(for: entry.source))
                        .badge(entry.count)
                        .tag(entry.source)
                }
            }
        }
        // The theme paints the sidebar too, which costs macOS's translucency and buys a window
        // that looks like one thing.
        .scrollContentBackground(.hidden)
        .background(theme.surface)
    }

    private var selection: Binding<ViewSource?> {
        Binding(get: { model.source }, set: { if let source = $0 { model.source = source } })
    }

    private func symbol(for source: ViewSource) -> String {
        switch source {
        case .lifecycle(let scope): scope.symbolName
        case .focused: "square.stack.3d.up"
        case .label(let label): label == IssueMark.starred.label ? "star.fill" : "tag"
        }
    }
}
