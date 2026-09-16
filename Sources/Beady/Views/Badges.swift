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
        case .blocked: "exclamationmark.octagon"
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

struct BlockedMark: View {
    @Environment(\.theme) private var theme

    var body: some View {
        Image(systemName: "exclamationmark.octagon.fill")
            .foregroundStyle(theme.blocked)
            .help("Blocked")
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
