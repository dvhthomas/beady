import BeadsCore
import Foundation

/// What someone has typed into the edit form, next to what the bead said when they started.
///
/// The form edits values; bd takes a change. This turns one into the other, and sends only what
/// actually differs — so two people editing different fields of the same bead don't overwrite
/// each other's work, and an accidental click on a field changes nothing.
public struct EditDraft: Equatable, Sendable {
    public let id: IssueID
    /// The bead as it was when editing began; the conflict check uses it too.
    public let original: Issue

    public var title: String
    public var type: String
    public var priority: Int
    /// Empty means unassigned.
    public var assignee: String
    public var labels: [String]
    public var description: String
    public var notes: String

    public init(issue: Issue) {
        id = issue.id
        original = issue
        title = issue.title
        type = issue.type
        priority = issue.priority
        assignee = issue.assignee ?? ""
        labels = issue.labels.sorted()
        description = issue.description
        notes = issue.notes
    }

    public var hasChanges: Bool { change != nil }

    /// The smallest change that would make the bead match this draft, or nil if it already does.
    public var change: IssueChange? {
        var edit = IssueEdit()
        if title.trimmingCharacters(in: .whitespacesAndNewlines) != original.title.trimmingCharacters(in: .whitespacesAndNewlines) {
            edit.title = title
        }
        if type != original.type { edit.type = type }
        if priority != original.priority { edit.priority = priority }
        if assignee != (original.assignee ?? "") { edit.assignee = assignee }
        if description != original.description { edit.description = description }
        if notes != original.notes { edit.notes = notes }

        // bd adds and removes labels rather than replacing the set, so that's what it's told.
        let wanted = Set(labels.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
        let had = Set(original.labels)
        edit.addedLabels = wanted.subtracting(had)
        edit.removedLabels = had.subtracting(wanted)

        return edit.isEmpty ? nil : .edit(id, edit)
    }

    /// Labels not on this bead yet, for offering the ones the database already uses.
    public func labelsToOffer(from known: [String]) -> [String] {
        let mine = Set(labels)
        return known.filter { !mine.contains($0) }
    }

    public mutating func addLabel(_ label: String) {
        let trimmed = label.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !labels.contains(trimmed) else { return }
        labels.append(trimmed)
        labels.sort()
    }

    public mutating func removeLabel(_ label: String) {
        labels.removeAll { $0 == label }
    }
}
