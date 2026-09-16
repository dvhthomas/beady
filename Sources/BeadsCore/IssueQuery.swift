import Foundation

/// A lifecycle slice of the database: the built-in views in the sidebar.
public enum Scope: String, CaseIterable, Identifiable, Sendable {
    case all
    case open
    case ready
    case inFlight
    case blocked
    case deferred
    case closed

    public var id: String { rawValue }

    public func includes(_ issue: Issue, in snapshot: IssueSnapshot, now: Date) -> Bool {
        let category = snapshot.category(of: issue)
        switch self {
        case .all: return true
        case .open: return category == .active
        case .ready:
            let deferred = issue.deferUntil.map { $0 > now } ?? false
            return category == .active && !deferred && !snapshot.isBlocked(issue)
        case .inFlight: return category == .wip
        case .blocked: return snapshot.isBlocked(issue)
        case .deferred: return category == .frozen
        case .closed: return category == .done
        }
    }
}

public enum TimeWindow: String, CaseIterable, Identifiable, Sendable {
    case day
    case week
    case month
    case quarter

    public var id: String { rawValue }

    public var duration: TimeInterval {
        switch self {
        case .day: 86_400
        case .week: 7 * 86_400
        case .month: 30 * 86_400
        case .quarter: 90 * 86_400
        }
    }

    func contains(_ date: Date?, now: Date) -> Bool {
        guard let date else { return false }
        return date >= now.addingTimeInterval(-duration)
    }
}

public enum IssueSort: String, CaseIterable, Identifiable, Sendable {
    case priority
    case recentlyUpdated
    case recentlyCreated
    case recentlyClosed
    case issueID

    public var id: String { rawValue }

    public func sorted(_ issues: [Issue]) -> [Issue] {
        issues.sorted(by: areInIncreasingOrder)
    }

    /// Every ordering falls back to natural id order so results are stable.
    public func areInIncreasingOrder(_ a: Issue, _ b: Issue) -> Bool {
        switch self {
        case .priority:
            if a.priority != b.priority { return a.priority < b.priority }
            if a.updatedAt != b.updatedAt { return a.updatedAt > b.updatedAt }
        case .recentlyUpdated:
            if a.updatedAt != b.updatedAt { return a.updatedAt > b.updatedAt }
        case .recentlyCreated:
            if a.createdAt != b.createdAt { return a.createdAt > b.createdAt }
        case .recentlyClosed:
            switch (a.closedAt, b.closedAt) {
            case let (x?, y?) where x != y: return x > y
            case (.some, .none): return true
            case (.none, .some): return false
            default: break
            }
        case .issueID:
            break
        }
        return a.id < b.id
    }
}
