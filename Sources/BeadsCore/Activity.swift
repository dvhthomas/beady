import Foundation

/// One change another session (or this one) made to a bead, as recorded by bd.
public struct ActivityEntry: Equatable, Sendable {
    public let issueID: IssueID
    public let actor: String
    public let date: Date
    /// The field that changed, when bd recorded one.
    public let field: String?

    public init(issueID: IssueID, actor: String, date: Date, field: String?) {
        self.issueID = issueID
        self.actor = actor
        self.date = date
        self.field = field
    }
}

/// What has been happening in the database lately. bd has no lease or lock to ask about, so this
/// is how the app can tell that someone else is working on a bead.
public struct ActivityLog: Equatable, Sendable {
    public static let empty = ActivityLog(entries: [])

    /// Newest first.
    public let entries: [ActivityEntry]

    public init(entries: [ActivityEntry]) {
        self.entries = entries
    }

    /// The most recent change to `id` within the window, unless we made it.
    ///
    /// Every session writes under the same bd actor by default (git user.name), so our own writes
    /// are recognised by when they happened rather than by who made them. If the newest change is
    /// ours, nobody else is working here, however old the changes behind it are.
    public func latestChange(
        to id: IssueID,
        since: Date,
        excluding ourWrites: [Date] = [],
        tolerance: TimeInterval = 3
    ) -> ActivityEntry? {
        guard let latest = entries.first(where: { $0.issueID == id && $0.date >= since }) else { return nil }
        let isOurs = ourWrites.contains { abs($0.timeIntervalSince(latest.date)) <= tolerance }
        return isOurs ? nil : latest
    }

    /// Everything touched since a moment, for deciding what to reload.
    public func issuesChanged(since: Date) -> Set<IssueID> {
        Set(entries.filter { $0.date >= since }.map(\.issueID))
    }
}
