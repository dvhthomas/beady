import BeadsCore

/// A column in the issue list, in the order the row shows them.
///
/// The view builds both the table and its "show these columns" menu from this, so there is one
/// place that knows what a column is called and how wide it starts out. Widths and visibility
/// themselves belong to the table, which persists whatever the user drags them to.
public enum ListColumn: String, CaseIterable, Identifiable, Sendable {
    case priority
    case id
    case status
    case type
    case title
    case labels
    case assignee
    /// done/total for a bead with children; empty for a leaf.
    case progress
    /// Updated, or closed when the view is ordered by what was closed last.
    case date

    /// Stored with the user's saved layout, so these strings are part of the app's contract.
    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .priority: "P"
        case .id: "ID"
        case .status: "Status"
        case .type: "Type"
        case .title: "Title"
        case .labels: "Labels"
        case .assignee: "Assignee"
        case .progress: "Progress"
        case .date: "Updated"
        }
    }

    /// The header, which for the date column names the date being shown.
    public func title(for sort: IssueSort) -> String {
        self == .date && sort == .recentlyClosed ? "Closed" : title
    }

    /// The title carries the row; hiding it would leave nothing to read.
    public var isAlwaysVisible: Bool { self == .title }

    public var isVisibleByDefault: Bool { self != .labels && self != .progress }

    public var idealWidth: Double {
        switch self {
        case .priority: 34
        case .id: 112
        case .status, .type: 40
        // Deliberately modest: the title takes whatever is left over, and an ideal wide enough
        // to overflow a narrow window pushes the last columns off the edge.
        case .title: 240
        case .labels: 140
        case .assignee: 100
        case .progress: 90
        case .date: 80
        }
    }

    public var minimumWidth: Double {
        switch self {
        case .priority, .status, .type: 32
        case .title: 160
        default: 48
        }
    }

    /// Whether the column shows, given what the table has stored for it: `true`/`false` when the
    /// user has chosen, `nil` when they never touched it. The default has to be consulted, or the
    /// Display menu ticks a column the table is hiding.
    public func isVisible(customized: Bool?) -> Bool {
        if isAlwaysVisible { return true }
        return customized ?? isVisibleByDefault
    }

    /// `nil` lets the column take the space left over; only the title should.
    public var maximumWidth: Double? {
        switch self {
        case .title: nil
        case .priority, .status, .type: 60
        case .id: 240
        case .labels, .assignee: 320
        case .progress: 160
        case .date: 140
        }
    }
}
