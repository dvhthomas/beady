import AppKit
import BeadsCore
import BeadsPresentation
import SwiftUI

extension StatusCategory {
    var symbolName: String {
        switch self {
        case .active: "circle"
        case .wip: "circle.lefthalf.filled"
        case .frozen: "snowflake"
        case .done: "checkmark.circle.fill"
        }
    }
}

extension Scope {
    var symbolName: String {
        switch self {
        case .all: "tray.full"
        case .open: "circle"
        case .ready: "play.circle"
        case .inFlight: "circle.lefthalf.filled"
        case .blocked: "pause.circle"
        case .deferred: "snowflake"
        case .closed: "checkmark.circle"
        }
    }
}

enum IssueTypeStyle {
    static func symbol(for type: String) -> String {
        switch type {
        case "bug": "ladybug"
        case "feature": "sparkles"
        case "epic": "square.stack.3d.up"
        case "task": "checklist"
        case "chore": "wrench.and.screwdriver"
        case "decision": "signpost.right"
        case "spike": "flask"
        default: "circle.dashed"
        }
    }
}

struct PriorityBadge: View {
    let priority: Int
    @Environment(\.theme) private var theme
    @Environment(\.backgroundProminence) private var prominence

    var body: some View {
        Text(DisplayText.priority(priority))
            .font(.caption2.weight(.semibold))
            .monospacedDigit()
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .foregroundStyle(color)
            .background(color.opacity(0.15), in: Capsule())
            .help("Priority \(priority) (0 is highest)")
    }

    private var color: Color { prominence == .increased ? .primary : theme.priority(priority) }
}

struct StatusBadge: View {
    let status: String
    let category: StatusCategory
    @Environment(\.theme) private var theme

    var body: some View {
        Label(DisplayText.status(status), systemImage: category.symbolName)
            .font(.caption)
            .foregroundStyle(theme.color(category))
            .lineLimit(1)
    }
}

struct TypeLabel: View {
    let type: String
    @Environment(\.theme) private var theme

    var body: some View {
        Label(type, systemImage: IssueTypeStyle.symbol(for: type))
            .font(.caption)
            .foregroundStyle(theme.secondaryText)
            .lineLimit(1)
    }
}

/// A bead that is waiting, said quietly and made useful: the mark is a button, and it opens a
/// popover naming what it's waiting on, with each blocker a link straight to it.
///
/// bd's "blocked" means an upstream bead has to land first, so this is information, not an alarm —
/// red stays for writes that actually failed.
struct WaitingMark: View {
    let reason: BlockedReason
    let snapshot: IssueSnapshot?
    let open: (IssueID) -> Void
    @Environment(\.theme) private var theme
    @Environment(\.backgroundProminence) private var prominence
    /// `State` as a plain DynamicProperty: Command Line Tools lack the @State macro plugin.
    private var showsDetail = State(initialValue: false)

    init(reason: BlockedReason, snapshot: IssueSnapshot?, open: @escaping (IssueID) -> Void) {
        self.reason = reason
        self.snapshot = snapshot
        self.open = open
    }

    var body: some View {
        Button {
            showsDetail.wrappedValue = true
        } label: {
            Image(systemName: "pause.circle")
                .foregroundStyle(prominence == .increased ? .primary : theme.color(.frozen))
        }
        .buttonStyle(.plain)
        .help(tooltip)
        .popover(isPresented: showsDetail.projectedValue, arrowEdge: .bottom) {
            WaitingDetail(reason: reason, snapshot: snapshot) { id in
                showsDetail.wrappedValue = false
                open(id)
            }
        }
    }

    private var tooltip: String {
        switch reason.kind {
        case .waitingOnBeads:
            let names = reason.blockers.map { "\($0.id) \($0.title)" }.joined(separator: "\n")
            return "Waiting on:\n\(names)\n\nClick for details."
        case .waitingOnAnotherProject:
            return "Waiting on another project: \(reason.externalCapabilities.joined(separator: ", "))"
        case .declared:
            return "Someone set this bead's status to blocked. bd records no reason for that."
        }
    }
}

/// What the waiting mark opens: the blockers, enough detail to judge them, and a link each.
struct WaitingDetail: View {
    let reason: BlockedReason
    let snapshot: IssueSnapshot?
    let open: (IssueID) -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(reason.summary, systemImage: "pause.circle")
                .font(.headline)
                .foregroundStyle(theme.color(.frozen))

            switch reason.kind {
            case .waitingOnBeads:
                ForEach(reason.blockers) { blocker in
                    blockerRow(blocker)
                }
            case .waitingOnAnotherProject:
                Text("Another project has to ship \(reason.externalCapabilities.joined(separator: ", ")) before this can move.")
                    .font(.caption)
                    .foregroundStyle(theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            case .declared:
                Text("Its status was set to blocked. bd keeps no reason for that, and nothing upstream is recorded.")
                    .font(.caption)
                    .foregroundStyle(theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if reason.isDeclared, reason.kind != .declared {
                Text("Its status is also set to blocked.")
                    .font(.caption)
                    .foregroundStyle(theme.secondaryText)
            }
        }
        .padding(14)
        .frame(width: 320)
        .background(theme.background)
    }

    private func blockerRow(_ blocker: Issue) -> some View {
        let category = snapshot?.category(of: blocker) ?? .active
        return Button {
            open(blocker.id)
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Image(systemName: category.symbolName)
                        .foregroundStyle(theme.color(category))
                    Text(blocker.id.rawValue)
                        .font(.caption.monospaced())
                        .foregroundStyle(theme.secondaryText)
                    Text(DisplayText.status(blocker.status))
                        .font(.caption)
                        .foregroundStyle(theme.secondaryText)
                    if let assignee = blocker.assignee, !assignee.isEmpty {
                        Text("· \(assignee)")
                            .font(.caption)
                            .foregroundStyle(theme.secondaryText)
                    }
                }
                HStack(spacing: 4) {
                    Text(blocker.title)
                        .multilineTextAlignment(.leading)
                        .foregroundStyle(theme.accent)
                    Image(systemName: "arrow.right")
                        .font(.caption)
                        .foregroundStyle(theme.accent)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(theme.surface, in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .help("Open \(blocker.id)")
    }
}

struct CompletionMeter: View {
    let completion: Completion
    @Environment(\.theme) private var theme
    @Environment(\.backgroundProminence) private var prominence

    var body: some View {
        HStack(spacing: 6) {
            ProgressView(value: completion.fraction)
                .progressViewStyle(.linear)
                .tint(prominence == .increased ? Color.primary : theme.color(.done))
                .frame(width: 56)
            Text("\(completion.closed)/\(completion.total)")
                .font(.caption.monospacedDigit())
                .rowForeground(theme.secondaryText, secondary: true)
        }
        .help("\(completion.closed) of \(completion.total) descendants closed")
    }
}


enum MarkStyle {
    static func symbol(_ mark: IssueMark) -> String {
        switch mark {
        case .pinned: "pin.fill"
        case .starred: "star.fill"
        }
    }

    /// What the menu item says, given what the bead already is.
    static func action(_ mark: IssueMark, isOn: Bool) -> String {
        switch (mark, isOn) {
        case (.pinned, false): "Pin to Top"
        case (.pinned, true): "Unpin"
        case (.starred, false): "Star"
        case (.starred, true): "Unstar"
        }
    }
}

/// The pin and star a bead is wearing, if any.
struct MarkGlyphs: View {
    let issue: Issue
    @Environment(\.theme) private var theme
    @Environment(\.backgroundProminence) private var prominence

    var body: some View {
        ForEach(IssueMark.allCases.filter(issue.has), id: \.self) { mark in
            Image(systemName: MarkStyle.symbol(mark))
                .font(.caption)
                .foregroundStyle(color(for: mark))
                .help(mark.title)
        }
    }

    private func color(for mark: IssueMark) -> Color {
        guard prominence != .increased else { return .primary }
        return mark == .pinned ? theme.pinned : theme.starred
    }
}


/// macOS paints a highlighted row in the colour the user chose, and everything on top of it
/// should be the single colour the system picked to sit there — white on most accents, dark on
/// pale ones. `backgroundProminence` is how SwiftUI says "this row is highlighted"; asking the
/// model which row is selected doesn't work, because table cells aren't re-evaluated for it.
private struct RowForeground: ViewModifier {
    @Environment(\.backgroundProminence) private var prominence
    let color: Color
    let secondary: Bool

    func body(content: Content) -> some View {
        content.foregroundStyle(style)
    }

    private var style: AnyShapeStyle {
        guard prominence == .increased else { return AnyShapeStyle(color) }
        return secondary ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary)
    }
}

extension View {
    /// Draws in `color` normally, and in the system's selected-content colour on a highlighted row.
    func rowForeground(_ color: Color, secondary: Bool = false) -> some View {
        modifier(RowForeground(color: color, secondary: secondary))
    }
}
