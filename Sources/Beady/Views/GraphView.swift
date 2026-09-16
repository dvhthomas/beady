import BeadsCore
import BeadsPresentation
import SwiftUI

/// The answer to "what has to happen before this can start", as a list rather than a canvas:
/// layers of work, nearest first, each row a bead you can jump to.
struct UnblockPathView: View {
    @Environment(\.theme) private var theme
    let model: WorkspaceModel
    let path: UnblockPath

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Blocked by \(path.work.count) unfinished \(path.work.count == 1 ? "bead" : "beads")", systemImage: "exclamationmark.octagon")
                .font(.headline)
                .foregroundStyle(theme.blocked)
            if path.hasCycle {
                Label("These blockers form a loop, so nothing here can finish first.", systemImage: "arrow.triangle.capsulepath")
                    .font(.caption)
                    .foregroundStyle(theme.pinned)
            }
            ForEach(Array(path.layers.enumerated()), id: \.offset) { index, layer in
                VStack(alignment: .leading, spacing: 4) {
                    Text(index == 0 ? "Start now" : "Then")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(theme.secondaryText)
                    ForEach(layer) { issue in
                        Button {
                            model.selection = issue.id
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: (model.snapshot?.category(of: issue) ?? .active).symbolName)
                                    .foregroundStyle(theme.color(model.snapshot?.category(of: issue) ?? .active))
                                Text(issue.id.rawValue)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(theme.secondaryText)
                                Text(issue.title)
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                            }
                        }
                        .buttonStyle(.plain)
                        .help(DisplayText.preview(issue.title) ?? "")
                    }
                }
            }
        }
    }
}

/// ⌘G: the selected bead and what sits immediately around it — blockers on the left, dependents
/// on the right, family below. Deliberately one hop: a whole-database graph is a hairball.
struct GraphSheet: View {
    @Environment(\.theme) private var theme
    let model: WorkspaceModel
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Dependencies").font(.headline)
                Spacer()
                Button("Done", action: onClose)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(14)
            Divider()
            if let id = model.selection, let graph = model.neighbourhood(around: id) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        columns(graph)
                        if let path = model.unblockPath(for: id) {
                            Divider()
                            UnblockPathView(model: model, path: path)
                        }
                    }
                    .padding(16)
                }
            } else {
                ContentUnavailableView("No Bead Selected", systemImage: "point.3.connected.trianglepath.dotted")
            }
        }
        .frame(width: 720, height: 560)
        .background(theme.background)
    }

    private func columns(_ graph: IssueNeighbourhood) -> some View {
        HStack(alignment: .top, spacing: 14) {
            column("Waiting on", graph.blockers, arrow: "arrow.right")
            VStack(spacing: 8) {
                card(graph.subject, emphasised: true)
                if let parent = graph.parent {
                    Text("in \(parent.id.rawValue)")
                        .font(.caption)
                        .foregroundStyle(theme.secondaryText)
                }
                if !graph.children.isEmpty {
                    Text("\(graph.children.count) children")
                        .font(.caption)
                        .foregroundStyle(theme.secondaryText)
                }
            }
            column("Waiting on this", graph.dependents, arrow: "arrow.left")
        }
    }

    @ViewBuilder
    private func column(_ title: String, _ issues: [Issue], arrow: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: arrow)
                .font(.caption.weight(.semibold))
                .foregroundStyle(theme.secondaryText)
            if issues.isEmpty {
                Text("Nothing")
                    .font(.caption)
                    .foregroundStyle(theme.secondaryText)
            } else {
                ForEach(issues) { card($0, emphasised: false) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func card(_ issue: Issue, emphasised: Bool) -> some View {
        let category = model.snapshot?.category(of: issue) ?? .active
        return Button {
            model.selection = issue.id
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: category.symbolName)
                        .foregroundStyle(theme.color(category))
                    Text(issue.id.rawValue)
                        .font(.caption.monospaced())
                        .foregroundStyle(theme.secondaryText)
                    MarkGlyphs(issue: issue)
                }
                Text(issue.title)
                    .font(emphasised ? .callout.weight(.semibold) : .caption)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(theme.surface, in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(emphasised ? theme.accent : theme.border, lineWidth: emphasised ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
        .help(DisplayText.preview(issue.title) ?? "")
    }
}
