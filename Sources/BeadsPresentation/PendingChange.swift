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
    /// How to take a change back. Only the writes Beady makes on its own behalf offer one:
    /// a bead's change is confirmed first and reversed by another change.
    public enum Undo: Equatable, Sendable {
        /// Writes these settings to the workspace's bd config.
        case journalSettings([ConfigSetting])
    }

    public let id = UUID()
    public let date: Date
    public let summary: String
    public let issueID: IssueID?
    public let succeeded: Bool
    public let message: String?
    /// Nil once used, or when there's nothing to take back.
    public internal(set) var undo: Undo? = nil
}

/// What a dragged bead carries. The private prefix means text dragged in from another app (an id
/// copied from a terminal, say) is never mistaken for a bead being moved.
public enum IssueDragPayload {
    private static let prefix = "beady-issue:"

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
            return String(localized: "Edit \(id.rawValue)", bundle: .module, comment: "Change summary; the value is a bead id")
        case .setStatus(let id, let from, let to, _):
            if to == "closed" { return String(localized: "Close \(id.rawValue)", bundle: .module, comment: "Change summary; the value is a bead id") }
            if from == "closed" { return String(localized: "Reopen \(id.rawValue)", bundle: .module, comment: "Change summary; the value is a bead id") }
            return String(localized: "Move \(id.rawValue) to \(DisplayText.status(to))", bundle: .module, comment: "Change summary: a bead id, then the new status")
        case .setParent(let id, let from, let to):
            if let to { return String(localized: "Move \(id.rawValue) to \(to.rawValue)", bundle: .module, comment: "Change summary: a bead id, then the new parent's id") }
            if let from { return String(localized: "Remove \(id.rawValue) from \(from.rawValue)", bundle: .module, comment: "Change summary: a bead id, then its old parent's id") }
            return String(localized: "Remove \(id.rawValue) from its parent", bundle: .module, comment: "Change summary; the value is a bead id")
        case .create(let new):
            return String(localized: "Create \(new.type) “\(new.title)”", bundle: .module, comment: "Change summary: bd's type name, then the title")
        case .setMark(let id, let mark, let on):
            switch (mark, on) {
            case (.pinned, true): return String(localized: "Pin \(id.rawValue)", bundle: .module, comment: "Change summary; the value is a bead id")
            case (.pinned, false): return String(localized: "Unpin \(id.rawValue)", bundle: .module, comment: "Change summary; the value is a bead id")
            case (.starred, true): return String(localized: "Star \(id.rawValue)", bundle: .module, comment: "Change summary; the value is a bead id")
            case (.starred, false): return String(localized: "Unstar \(id.rawValue)", bundle: .module, comment: "Change summary; the value is a bead id")
            }
        case .setBlocker(let id, let blocker, let on):
            return on
                ? String(localized: "Make \(id.rawValue) wait for \(blocker.rawValue)", bundle: .module, comment: "Change summary: two bead ids")
                : String(localized: "Stop \(id.rawValue) waiting for \(blocker.rawValue)", bundle: .module, comment: "Change summary: two bead ids")
        }
    }

    static func subject(_ change: IssueChange, in snapshot: IssueSnapshot) -> String? {
        guard let id = change.issueID else { return nil }
        guard let issue = snapshot.issue(id) else { return id.rawValue }
        return String(localized: "\(id.rawValue) · \(issue.title)", bundle: .module, comment: "A bead named by id and title")
    }

    static func details(_ change: IssueChange, in snapshot: IssueSnapshot) -> [String] {
        func name(_ id: IssueID?) -> String {
            guard let id else { return String(localized: "none", bundle: .module, comment: "Stands in for a parent or blocker when there is none") }
            guard let issue = snapshot.issue(id) else { return id.rawValue }
            return String(localized: "\(id.rawValue) “\(issue.title)”", bundle: .module, comment: "A bead named by id and quoted title")
        }

        switch change {
        case .edit(let id, let edit):
            let issue = snapshot.issue(id)
            var lines: [String] = []
            if let title = edit.title {
                lines.append(String(localized: "Title: “\(issue?.title ?? "")” → “\(title)”", bundle: .module, comment: "Change detail: old title, new title"))
            }
            if let priority = edit.priority {
                lines.append(String(localized: "Priority: \(DisplayText.priority(issue?.priority ?? 0)) → \(DisplayText.priority(priority))", bundle: .module, comment: "Change detail: old priority, new priority"))
            }
            if let description = edit.description {
                lines.append(textChange(String(localized: "Description", bundle: .module, comment: "Change detail: the field name"), from: issue?.description ?? "", to: description))
            }
            if let notes = edit.notes {
                lines.append(textChange(String(localized: "Notes", bundle: .module, comment: "Change detail: the field name"), from: issue?.notes ?? "", to: notes))
            }
            return lines
        case .setStatus(_, let from, let to, _):
            return [String(localized: "Status: \(DisplayText.status(from)) → \(DisplayText.status(to))", bundle: .module, comment: "Change detail: old status, new status")]
        case .setParent(_, let from, let to):
            return [String(localized: "Parent: \(name(from)) → \(name(to))", bundle: .module, comment: "Change detail: old parent, new parent")]
        case .create(let new):
            var lines = [
                String(localized: "Title: \(new.title)", bundle: .module, comment: "Change detail"),
                String(localized: "Type: \(new.type) · \(DisplayText.priority(new.priority))", bundle: .module, comment: "Change detail: bd's type name, then the priority"),
            ]
            if let parent = new.parent {
                lines.append(String(localized: "Parent: \(name(parent))", bundle: .module, comment: "Change detail"))
            }
            if !new.description.isEmpty {
                lines.append(String(localized: "Description: \(new.description.count) characters", bundle: .module, comment: "Change detail; plural on the number of characters"))
            }
            // bd copies the parent's labels onto a new child.
            if let labels = new.parent.flatMap({ snapshot.issue($0) })?.labels, !labels.isEmpty {
                lines.append(String(localized: "Labels: inherits \(labels.joined(separator: ", ")) from the parent", bundle: .module, comment: "Change detail; the value is a list of labels"))
            }
            return lines
        case .setMark(_, let mark, let on):
            return [on
                ? String(localized: "Label: add “\(mark.label)”", bundle: .module, comment: "Change detail; the value is a bd label")
                : String(localized: "Label: remove “\(mark.label)”", bundle: .module, comment: "Change detail; the value is a bd label")]
        case .setBlocker(_, let blocker, let on):
            return [on
                ? String(localized: "Blocked by: add \(name(blocker))", bundle: .module, comment: "Change detail; the value is a bead id and title")
                : String(localized: "Blocked by: remove \(name(blocker))", bundle: .module, comment: "Change detail; the value is a bead id and title")]
        }
    }

    private static func textChange(_ field: String, from old: String, to new: String) -> String {
        if new.isEmpty { return String(localized: "\(field): cleared (was \(old.count) characters)", bundle: .module, comment: "Change detail: a field name, then how long it was; plural on the number of characters") }
        if old.isEmpty { return String(localized: "\(field): added (\(new.count) characters)", bundle: .module, comment: "Change detail: a field name, then how long it is; plural on the number of characters") }
        return String(localized: "\(field): \(old.count) → \(new.count) characters", bundle: .module, comment: "Change detail: a field name, the old length, the new length; plural on the last number")
    }
}
