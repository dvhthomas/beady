import Foundation

/// One version of a bead, as bd's history reports it: a snapshot per commit.
public struct IssueVersion: Equatable, Sendable {
    public let date: Date
    public let issue: Issue

    public init(date: Date, issue: Issue) {
        self.date = date
        self.issue = issue
    }
}

/// Something that changed, ready to read: "status · open → in_progress, 5 minutes ago, agent-tiles".
public struct HistoryEvent: Equatable, Sendable, Identifiable {
    public let date: Date
    public let field: String
    public let from: String
    public let to: String
    /// nil when nothing in the interaction log matches; bd's own history calls every committer root.
    public let actor: String?

    public var id: String { "\(date.timeIntervalSince1970)-\(field)" }

    public init(date: Date, field: String, from: String, to: String, actor: String?) {
        self.date = date
        self.field = field
        self.from = from
        self.to = to
        self.actor = actor
    }
}

public enum History {
    /// Turns bd's snapshots into field-level changes, newest first, naming who made each one
    /// where the interaction log agrees.
    /// `tolerance` is generous because bd's Dolt commit lands a little after the interaction is
    /// logged; the field has to match as well, so a wider window can't mislabel a change.
    public static func events(from versions: [IssueVersion], activity: ActivityLog, tolerance: TimeInterval = 90) -> [HistoryEvent] {
        let ordered = versions.sorted { $0.date < $1.date }
        guard let first = ordered.first else { return [] }

        var events: [HistoryEvent] = [
            HistoryEvent(
                date: first.date,
                field: "created",
                from: "",
                to: first.issue.title,
                actor: actor(for: "created", at: first.date, in: activity, issue: first.issue.id, tolerance: tolerance)
            ),
        ]

        for (previous, current) in zip(ordered, ordered.dropFirst()) {
            for (field, before, after) in differences(previous.issue, current.issue) {
                events.append(HistoryEvent(
                    date: current.date,
                    field: field,
                    from: before,
                    to: after,
                    actor: actor(for: field, at: current.date, in: activity, issue: current.issue.id, tolerance: tolerance)
                ))
            }
        }
        // Newest first. Within one commit the fields keep the order `differences` lists them in
        // — status and priority before the smaller details — so a sort that isn't stable can't
        // shuffle them.
        return events.enumerated()
            .sorted { left, right in
                left.element.date == right.element.date
                    ? left.offset < right.offset
                    : left.element.date > right.element.date
            }
            .map(\.element)
    }

    /// The fields worth reporting, in a fixed order.
    private static func differences(_ old: Issue, _ new: Issue) -> [(String, String, String)] {
        var changes: [(String, String, String)] = []
        func compare(_ field: String, _ before: String, _ after: String) {
            if before != after { changes.append((field, before, after)) }
        }
        compare("title", old.title, new.title)
        compare("status", old.status, new.status)
        compare("priority", "P\(old.priority)", "P\(new.priority)")
        compare("type", old.type, new.type)
        compare("assignee", old.assignee ?? "", new.assignee ?? "")
        compare("labels", old.labels.joined(separator: ", "), new.labels.joined(separator: ", "))
        compare("parent", old.parentID?.rawValue ?? "", new.parentID?.rawValue ?? "")
        compare("description", summarize(old.description), summarize(new.description))
        compare("notes", summarize(old.notes), summarize(new.notes))
        compare("close reason", old.closeReason ?? "", new.closeReason ?? "")
        return changes
    }

    /// Long text is reported as changed rather than quoted in full.
    private static func summarize(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "" }
        return trimmed.count <= 60 ? trimmed : String(trimmed.prefix(60)) + "…"
    }

    private static func actor(
        for field: String,
        at date: Date,
        in activity: ActivityLog,
        issue: IssueID,
        tolerance: TimeInterval
    ) -> String? {
        activity.entries.first {
            $0.issueID == issue
                && abs($0.date.timeIntervalSince(date)) <= tolerance
                && $0.field == field
        }?.actor
    }
}
