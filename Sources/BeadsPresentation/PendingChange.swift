import BeadsCore
import Foundation

/// A change waiting for confirmation, with everything needed to judge it first.
public struct PendingChange: Identifiable, Sendable {
    public let id = UUID()
    public var change: IssueChange
    /// The issue as the user saw it when they started, for the live conflict check.
    public let base: Issue?
    public let summary: String
    /// The bead being changed, by id and title.
    public let subject: String?
    public let details: [String]
    public internal(set) var problems: [ChangeProblem]
    public let asksForReason: Bool
    /// Something to look at before applying, such as checks that changed after a refresh.
    public internal(set) var notice: String?
    public internal(set) var failure: String?
    public internal(set) var isApplying = false

    public var canConfirm: Bool {
        !isApplying && failure == nil && !problems.contains { $0.severity == .error }
    }
}

/// One entry in the session's change history.
public struct ChangeRecord: Identifiable, Sendable {
    public let id = UUID()
    public let date: Date
    public let summary: String
    public let issueID: IssueID?
    public let succeeded: Bool
    public let message: String?
}

/// What a dragged bead carries. The private prefix means text dragged in from another app (an id
/// copied from a terminal, say) is never mistaken for a bead being moved.
public enum IssueDragPayload {
    private static let prefix = "beads-viewer-issue:"

    public static func encode(_ id: IssueID) -> String {
        prefix + id.rawValue
    }

    /// The dragged bead, only when exactly one of this app's payloads was dropped.
    public static func decode(_ items: [String]) -> IssueID? {
        guard items.count == 1, let item = items.first, item.hasPrefix(prefix) else { return nil }
        let raw = String(item.dropFirst(prefix.count))
        return raw.isEmpty ? nil : IssueID(raw)
    }
}

/// Human-readable descriptions of a change, shown before confirming. Beads are named by id and
/// title, so it's clear which epic something is moving to.
enum ChangeDescriber {
    /// "2 minutes ago", for warnings about other sessions.
    static func ago(_ date: Date, from now: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: now)
    }

    static func summary(_ change: IssueChange) -> String {
        switch change {
        case .edit(let id, _):
            return "Edit \(id)"
        case .setStatus(let id, let from, let to, _):
            if to == "closed" { return "Close \(id)" }
            if from == "closed" { return "Reopen \(id)" }
            return "Move \(id) to \(DisplayText.status(to))"
        case .setParent(let id, let from, let to):
            if let to { return "Move \(id) to \(to)" }
            return "Remove \(id) from \(from.map(\.rawValue) ?? "its parent")"
        case .create(let new):
            return "Create \(new.type) “\(new.title)”"
        }
    }

    static func subject(_ change: IssueChange, in snapshot: IssueSnapshot) -> String? {
        guard let id = change.issueID else { return nil }
        guard let issue = snapshot.issue(id) else { return id.rawValue }
        return "\(id) · \(issue.title)"
    }

    static func details(_ change: IssueChange, in snapshot: IssueSnapshot) -> [String] {
        func name(_ id: IssueID?) -> String {
            guard let id else { return "none" }
            guard let issue = snapshot.issue(id) else { return id.rawValue }
            return "\(id) “\(issue.title)”"
        }

        switch change {
        case .edit(let id, let edit):
            let issue = snapshot.issue(id)
            var lines: [String] = []
            if let title = edit.title {
                lines.append("Title: “\(issue?.title ?? "")” → “\(title)”")
            }
            if let priority = edit.priority {
                lines.append("Priority: \(DisplayText.priority(issue?.priority ?? 0)) → \(DisplayText.priority(priority))")
            }
            if let description = edit.description {
                lines.append(textChange("Description", from: issue?.description ?? "", to: description))
            }
            if let notes = edit.notes {
                lines.append(textChange("Notes", from: issue?.notes ?? "", to: notes))
            }
            return lines
        case .setStatus(_, let from, let to, _):
            return ["Status: \(DisplayText.status(from)) → \(DisplayText.status(to))"]
        case .setParent(_, let from, let to):
            return ["Parent: \(name(from)) → \(name(to))"]
        case .create(let new):
            var lines = ["Title: \(new.title)", "Type: \(new.type) · \(DisplayText.priority(new.priority))"]
            if let parent = new.parent {
                lines.append("Parent: \(name(parent))")
            }
            if !new.description.isEmpty {
                lines.append("Description: \(new.description.count) characters")
            }
            // bd copies the parent's labels onto a new child.
            if let labels = new.parent.flatMap({ snapshot.issue($0) })?.labels, !labels.isEmpty {
                lines.append("Labels: inherits \(labels.joined(separator: ", ")) from the parent")
            }
            return lines
        }
    }

    private static func textChange(_ field: String, from old: String, to new: String) -> String {
        if new.isEmpty { return "\(field): cleared (was \(old.count) characters)" }
        if old.isEmpty { return "\(field): added (\(new.count) characters)" }
        return "\(field): \(old.count) → \(new.count) characters"
    }
}
