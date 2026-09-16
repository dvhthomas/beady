import Foundation

/// A bead identifier such as `mapshop-ajo.2`.
public struct IssueID: RawRepresentable, Hashable, Comparable, Sendable, CustomStringConvertible,
    ExpressibleByStringLiteral
{
    public let rawValue: String

    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.rawValue = value }

    public var description: String { rawValue }

    /// Natural ordering, so `x.2` sorts before `x.10`.
    public static func < (lhs: IssueID, rhs: IssueID) -> Bool {
        lhs.rawValue.compare(rhs.rawValue, options: [.numeric, .caseInsensitive]) == .orderedAscending
    }
}

public enum DependencyKind: Hashable, Sendable {
    case blocks
    case parentChild
    case other(String)

    public init(rawValue: String) {
        switch rawValue {
        case "blocks": self = .blocks
        case "parent-child": self = .parentChild
        default: self = .other(rawValue)
        }
    }

    public var rawValue: String {
        switch self {
        case .blocks: "blocks"
        case .parentChild: "parent-child"
        case .other(let raw): raw
        }
    }
}

/// `issueID` depends on `dependsOnID`. For `.blocks`, `dependsOnID` has to finish first.
public struct Dependency: Hashable, Sendable {
    public let issueID: IssueID
    public let dependsOnID: IssueID
    public let kind: DependencyKind

    public init(issueID: IssueID, dependsOnID: IssueID, kind: DependencyKind) {
        self.issueID = issueID
        self.dependsOnID = dependsOnID
        self.kind = kind
    }
}

public struct Issue: Identifiable, Hashable, Sendable {
    public let id: IssueID
    public var title: String
    public var description: String
    public var notes: String
    public var status: String
    /// 0 is the highest priority, 4 the lowest.
    public var priority: Int
    public var type: String
    public var assignee: String?
    public var owner: String?
    public var labels: [String]
    public var createdAt: Date
    public var updatedAt: Date
    public var startedAt: Date?
    public var closedAt: Date?
    public var closeReason: String?
    /// While in the future, bd keeps the issue out of `bd ready`.
    public var deferUntil: Date?
    public var parentID: IssueID?
    public var dependencies: [Dependency]
    public var externalRef: String?
    public var commentCount: Int

    public init(
        id: IssueID,
        title: String,
        description: String = "",
        notes: String = "",
        status: String,
        priority: Int,
        type: String,
        assignee: String? = nil,
        owner: String? = nil,
        labels: [String] = [],
        createdAt: Date,
        updatedAt: Date,
        startedAt: Date? = nil,
        closedAt: Date? = nil,
        closeReason: String? = nil,
        deferUntil: Date? = nil,
        parentID: IssueID? = nil,
        dependencies: [Dependency] = [],
        externalRef: String? = nil,
        commentCount: Int = 0
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.notes = notes
        self.status = status
        self.priority = priority
        self.type = type
        self.assignee = assignee
        self.owner = owner
        self.labels = labels
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.startedAt = startedAt
        self.closedAt = closedAt
        self.closeReason = closeReason
        self.deferUntil = deferUntil
        self.parentID = parentID
        self.dependencies = dependencies
        self.externalRef = externalRef
        self.commentCount = commentCount
    }

    func mentions(_ word: String) -> Bool {
        let fields = [id.rawValue, title, description, notes, closeReason ?? "", externalRef ?? ""] + labels
        return fields.contains { $0.range(of: word, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
    }
}
