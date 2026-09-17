import BeadsCore
import BeadsPresentation
import SwiftUI

/// The whole dependency graph, to move around in.
///
/// What can start now is on the left, and lines run toward what waits on it. Click a bead to
/// focus it: the view brings it to the middle, draws everything it's waiting on in bold, tints
/// everything waiting on it, and lets the rest recede.
struct DependencyGraphView: View {
    @Environment(\.theme) private var theme
    let model: WorkspaceModel
    let ui: WorkspaceUI
    /// Set when the graph is its own window: it needs nothing from you, so Escape closes it.
    var close: (() -> Void)?

    private static let cell = CGSize(width: 230, height: 76)
    private static let gap = CGSize(width: 64, height: 16)
    private static let margin: CGFloat = 32

    var body: some View {
        let graph = DependencyGraph(model.snapshot ?? IssueSnapshot(issues: []), includeFinished: ui.graphIncludesFinished)
        let positions = graph.layout()
        VStack(spacing: 0) {
            toolbar(graph)
            Divider()
            if graph.nodes.isEmpty {
                ContentUnavailableView(
                    "No Dependencies",
                    systemImage: "point.3.connected.trianglepath.dotted",
                    description: Text(ui.graphIncludesFinished
                        ? "Nothing in this database waits on anything else."
                        : "Nothing unfinished waits on anything else. Show finished work to see the rest.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                canvas(graph, positions)
            }
        }
        .background(theme.background)
    }

    // MARK: Toolbar

    private func toolbar(_ graph: DependencyGraph) -> some View {
        HStack(spacing: 12) {
            if let focus = ui.graphFocus, let issue = model.snapshot?.issue(focus) {
                Label {
                    Text("\(issue.id.rawValue)  \(issue.title)")
                        .lineLimit(1)
                } icon: {
                    Image(systemName: "scope")
                }
                .font(.callout)
                Button("Show in Main Window") {
                    model.selection = focus
                }
                .help("Select this bead in the main window")
            } else {
                Text("Click a bead to follow it")
                    .foregroundStyle(theme.secondaryText)
            }
            Spacer()
            legend
            Toggle("Finished work", isOn: binding(\.graphIncludesFinished))
                .toggleStyle(.checkbox)
                .help("Closed beads, drawn faded")
            HStack(spacing: 2) {
                Button { zoom(by: -0.15) } label: { Image(systemName: "minus.magnifyingglass") }
                    .keyboardShortcut("-", modifiers: .command)
                Button { ui.graphZoom = 1 } label: { Text("\(Int(ui.graphZoom * 100))%").monospacedDigit() }
                    .keyboardShortcut("0", modifiers: .command)
                Button { zoom(by: 0.15) } label: { Image(systemName: "plus.magnifyingglass") }
                    .keyboardShortcut("=", modifiers: .command)
            }
            .buttonStyle(.accessoryBar)
            if let close {
                Button("Close", action: close)
                    .keyboardShortcut(.cancelAction)
            }
        }
        .controlSize(.small)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private var legend: some View {
        HStack(spacing: 10) {
            legendItem(width: 3, color: theme.text, "has to finish first")
            legendItem(width: 2, color: theme.accent, "waiting on it")
        }
        .font(.caption)
        .foregroundStyle(theme.secondaryText)
        .opacity(ui.graphFocus == nil ? 0 : 1)
    }

    private func legendItem(width: CGFloat, color: Color, _ title: String) -> some View {
        HStack(spacing: 4) {
            Capsule().fill(color).frame(width: 16, height: width)
            Text(title)
        }
    }

    // MARK: The graph

    private func canvas(_ graph: DependencyGraph, _ positions: [IssueID: DependencyGraph.Position]) -> some View {
        let focus = ui.graphFocus.flatMap { id in graph.nodes.contains { $0.id == id } ? id : nil }
        let upstream = focus.map(graph.upstream(of:)) ?? []
        let downstream = focus.map(graph.downstream(of:)) ?? []
        let zoom = ui.graphZoom
        let columns = (positions.values.map(\.column).max() ?? 0) + 1
        let rows = (positions.values.map(\.row).max() ?? 0) + 1
        let size = CGSize(
            width: (CGFloat(columns) * (Self.cell.width + Self.gap.width) + Self.margin * 2) * zoom,
            height: (CGFloat(rows) * (Self.cell.height + Self.gap.height) + Self.margin * 2) * zoom
        )

        return ScrollViewReader { scroller in
            ScrollView([.horizontal, .vertical]) {
                ZStack(alignment: .topLeading) {
                    Canvas { context, _ in
                        for edge in graph.edges {
                            guard let from = positions[edge.from], let to = positions[edge.to] else { continue }
                            let style = edgeStyle(edge, focus: focus, upstream: upstream, downstream: downstream)
                            drawEdge(from: from, to: to, style: style, zoom: zoom, in: &context)
                        }
                    }
                    .frame(width: size.width, height: size.height)

                    ForEach(graph.nodes) { issue in
                        if let position = positions[issue.id] {
                            let origin = origin(of: position, zoom: zoom)
                            node(issue, role: role(of: issue.id, focus: focus, upstream: upstream, downstream: downstream))
                                .frame(width: Self.cell.width * zoom, height: Self.cell.height * zoom)
                                // Alignment guides, not .position(): they move the card's layout
                                // frame, which is what scrollTo aims at. .position() only moved
                                // the drawing, and recentring landed somewhere else entirely.
                                .alignmentGuide(.leading) { _ in -origin.x }
                                .alignmentGuide(.top) { _ in -origin.y }
                                .id(issue.id)
                        }
                    }
                }
                .frame(width: size.width, height: size.height, alignment: .topLeading)
            }
            .onAppear {
                if let focus { scroller.scrollTo(focus, anchor: .center) }
            }
            .onChange(of: ui.graphFocus) {
                guard let focus = ui.graphFocus else { return }
                withAnimation(.easeInOut(duration: 0.35)) {
                    scroller.scrollTo(focus, anchor: .center)
                }
            }
        }
    }

    private enum Role {
        case focus, upstream, downstream, unrelated, idle
    }

    private func role(of id: IssueID, focus: IssueID?, upstream: Set<IssueID>, downstream: Set<IssueID>) -> Role {
        guard let focus else { return .idle }
        if id == focus { return .focus }
        if upstream.contains(id) { return .upstream }
        if downstream.contains(id) { return .downstream }
        return .unrelated
    }

    private func node(_ issue: Issue, role: Role) -> some View {
        let category = model.snapshot?.category(of: issue) ?? .active
        let finished = category == .done
        let zoom = ui.graphZoom
        return Button {
            ui.graphFocus = issue.id
        } label: {
            VStack(alignment: .leading, spacing: 4 * zoom) {
                HStack(spacing: 6 * zoom) {
                    Image(systemName: category.symbolName)
                        .foregroundStyle(theme.color(category))
                    Text(issue.id.rawValue)
                        .font(.system(size: 11 * zoom, design: .monospaced))
                        .foregroundStyle(theme.secondaryText)
                    Spacer(minLength: 0)
                    MarkGlyphs(issue: issue)
                }
                .font(.system(size: 12 * zoom))
                Text(issue.title)
                    .font(.system(size: 13 * zoom, weight: role == .focus || role == .upstream ? .semibold : .regular))
                    .strikethrough(finished, color: theme.secondaryText)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(10 * zoom)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(background(for: role), in: RoundedRectangle(cornerRadius: 8 * zoom))
            .overlay(
                RoundedRectangle(cornerRadius: 8 * zoom)
                    .strokeBorder(border(for: role), lineWidth: role == .focus ? 2.5 : (role == .upstream ? 2 : 1))
            )
            .opacity(role == .unrelated ? 0.3 : (finished && role == .idle ? 0.6 : 1))
        }
        .buttonStyle(.plain)
        .help("\(issue.id.rawValue) \(issue.title)\nClick to follow · Show in Main Window to open it")
        .contextMenu {
            Button("Follow This Bead") { ui.graphFocus = issue.id }
            Button("Show in Main Window") { model.selection = issue.id }
        }
    }

    private func background(for role: Role) -> Color {
        switch role {
        case .downstream: theme.accent.opacity(0.16)
        case .focus: theme.selection
        default: theme.surface
        }
    }

    private func border(for role: Role) -> Color {
        switch role {
        case .focus: theme.accent
        case .upstream: theme.text
        case .downstream: theme.accent.opacity(0.7)
        default: theme.border
        }
    }

    // MARK: Edges

    private struct EdgeStyle {
        let color: Color
        let width: CGFloat
        let opacity: Double
    }

    /// Bold for the chain that has to finish first, tinted for what's waiting, faint otherwise.
    private func edgeStyle(_ edge: DependencyGraph.Edge, focus: IssueID?, upstream: Set<IssueID>, downstream: Set<IssueID>) -> EdgeStyle {
        guard let focus else { return EdgeStyle(color: theme.secondaryText, width: 1.2, opacity: 0.7) }
        let upstreamChain = upstream.union([focus])
        if upstream.contains(edge.from), upstreamChain.contains(edge.to) {
            return EdgeStyle(color: theme.text, width: 3, opacity: 1)
        }
        let downstreamCluster = downstream.union([focus])
        if downstreamCluster.contains(edge.from), downstream.contains(edge.to) {
            return EdgeStyle(color: theme.accent, width: 2, opacity: 0.9)
        }
        return EdgeStyle(color: theme.border, width: 1, opacity: 0.35)
    }

    private func drawEdge(
        from: DependencyGraph.Position,
        to: DependencyGraph.Position,
        style: EdgeStyle,
        zoom: CGFloat,
        in context: inout GraphicsContext
    ) {
        let start = CGPoint(x: center(of: from, zoom: zoom).x + Self.cell.width * zoom / 2, y: center(of: from, zoom: zoom).y)
        let end = CGPoint(x: center(of: to, zoom: zoom).x - Self.cell.width * zoom / 2, y: center(of: to, zoom: zoom).y)
        let bend = max((end.x - start.x) * 0.5, 30 * zoom)
        var path = Path()
        path.move(to: start)
        path.addCurve(
            to: end,
            control1: CGPoint(x: start.x + bend, y: start.y),
            control2: CGPoint(x: end.x - bend, y: end.y)
        )
        let shading = GraphicsContext.Shading.color(style.color.opacity(style.opacity))
        context.stroke(path, with: shading, style: StrokeStyle(lineWidth: style.width * zoom, lineCap: .round))

        // An arrowhead where the line meets the waiting bead.
        let head = 7 * zoom
        var arrow = Path()
        arrow.move(to: end)
        arrow.addLine(to: CGPoint(x: end.x - head, y: end.y - head * 0.6))
        arrow.addLine(to: CGPoint(x: end.x - head, y: end.y + head * 0.6))
        arrow.closeSubpath()
        context.fill(arrow, with: shading)
    }

    private func origin(of position: DependencyGraph.Position, zoom: CGFloat) -> CGPoint {
        let middle = center(of: position, zoom: zoom)
        return CGPoint(x: middle.x - Self.cell.width * zoom / 2, y: middle.y - Self.cell.height * zoom / 2)
    }

    private func center(of position: DependencyGraph.Position, zoom: CGFloat) -> CGPoint {
        CGPoint(
            x: (Self.margin + CGFloat(position.column) * (Self.cell.width + Self.gap.width) + Self.cell.width / 2) * zoom,
            y: (Self.margin + CGFloat(position.row) * (Self.cell.height + Self.gap.height) + Self.cell.height / 2) * zoom
        )
    }

    private func zoom(by delta: Double) {
        ui.graphZoom = min(max(ui.graphZoom + delta, 0.4), 2)
    }

    private func binding(_ keyPath: ReferenceWritableKeyPath<WorkspaceUI, Bool>) -> Binding<Bool> {
        Binding(get: { ui[keyPath: keyPath] }, set: { ui[keyPath: keyPath] = $0 })
    }
}

/// The dependency window: follows the open workspace, and the main window's selection.
struct DependencyWindow: View {
    let session: AppSession
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        Group {
            if let model = session.model {
                DependencyGraphView(model: model, ui: session.ui) { dismissWindow(id: "dependencies") }
                    .onChange(of: model.selection) {
                        // Picking a bead in the main window moves the graph too.
                        if let id = model.selection { session.ui.graphFocus = id }
                    }
            } else {
                ContentUnavailableView("No Workspace", systemImage: "folder", description: Text("Open a beads workspace to see its dependencies."))
            }
        }
        .frame(minWidth: 700, minHeight: 420)
        .themed(session.themes)
    }
}
