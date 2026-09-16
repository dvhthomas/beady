import BeadsCore
import BeadsPresentation
import SwiftUI

extension StatusCategory {
    var color: Color {
        switch self {
        case .active: .blue
        case .wip: .orange
        case .frozen: .teal
        case .done: .green
        }
    }

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

    private var color: Color {
        switch priority {
        case 0: .red
        case 1: .orange
        case 2: .blue
        default: .gray
        }
    }
}

struct StatusBadge: View {
    let status: String
    let category: StatusCategory

    var body: some View {
        Label(DisplayText.status(status), systemImage: category.symbolName)
            .font(.caption)
            .foregroundStyle(category.color)
            .lineLimit(1)
    }
}

struct TypeLabel: View {
    let type: String

    var body: some View {
        Label(type, systemImage: IssueTypeStyle.symbol(for: type))
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }
}

struct BlockedMark: View {
    var body: some View {
        Image(systemName: "exclamationmark.octagon.fill")
            .foregroundStyle(.red)
            .help("Blocked")
    }
}

struct CompletionMeter: View {
    let completion: Completion

    var body: some View {
        HStack(spacing: 6) {
            ProgressView(value: completion.fraction)
                .progressViewStyle(.linear)
                .tint(.green)
                .frame(width: 56)
            Text("\(completion.closed)/\(completion.total)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .help("\(completion.closed) of \(completion.total) descendants closed")
    }
}
