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

    private var color: Color { theme.priority(priority) }
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

    var body: some View {
        HStack(spacing: 6) {
            ProgressView(value: completion.fraction)
                .progressViewStyle(.linear)
                .tint(theme.color(.done))
                .frame(width: 56)
            Text("\(completion.closed)/\(completion.total)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(theme.secondaryText)
        }
        .help("\(completion.closed) of \(completion.total) descendants closed")
    }
}
