import Foundation

public struct Completion: Equatable, Sendable {
    public let closed: Int
    public let total: Int

    public init(closed: Int, total: Int) {
        self.closed = closed
        self.total = total
    }

    public var fraction: Double { total == 0 ? 0 : Double(closed) / Double(total) }
}

/// Everything loaded from one beads database at one moment, indexed for the queries the views need.
public struct IssueSnapshot: Sendable {
    /// Sorted by natural id order.
    public let issues: [Issue]
    public let catalog: StatusCatalog
    public let labels: [String]
    public let assignees: [String]
    public let types: [String]
    public let statuses: [String]
    public let priorities: [Int]
    /// Records the data source couldn't turn into issues; they are not in `issues`.
    public let unreadableRecordCount: Int

    private let byID: [IssueID: Issue]
    private let childIDs: [IssueID: [IssueID]]
    private let dependentIDs: [IssueID: [IssueID]]
    private let completionByID: [IssueID: Completion]

    public init(issues: [Issue], catalog: StatusCatalog = .builtIn, unreadableRecordCount: Int = 0) {
        let sorted = issues.sorted { $0.id < $1.id }
        let index = Dictionary(sorted.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })

        var children: [IssueID: [IssueID]] = [:]
        var dependents: [IssueID: [IssueID]] = [:]
        for issue in sorted {
            if let parent = issue.parentID, parent != issue.id {
                children[parent, default: []].append(issue.id)
            }
            for dependency in issue.dependencies where dependency.kind == .blocks {
                dependents[dependency.dependsOnID, default: []].append(issue.id)
            }
        }

        // Computed once per load: views ask for progress on many rows on every render.
        var completion: [IssueID: Completion] = [:]
        for parent in children.keys {
            let all = Self.descendants(of: parent, childIDs: children, byID: index)
            guard !all.isEmpty else { continue }
            let closed = all.filter { catalog.category(of: $0.status) == .done }.count
            completion[parent] = Completion(closed: closed, total: all.count)
        }

        self.issues = sorted
        self.catalog = catalog
        self.unreadableRecordCount = unreadableRecordCount
        byID = index
        childIDs = children
        dependentIDs = dependents
        completionByID = completion
        labels = Set(sorted.flatMap(\.labels)).sorted()
        assignees = Set(sorted.compactMap(\.assignee)).sorted()
        types = Set(sorted.map(\.type)).sorted()
        statuses = Set(sorted.map(\.status)).sorted()
        priorities = Set(sorted.map(\.priority)).sorted()
    }

    public func issue(_ id: IssueID) -> Issue? { byID[id] }

    public func category(of issue: Issue) -> StatusCategory { catalog.category(of: issue.status) }

    public func isDone(_ issue: Issue) -> Bool { category(of: issue) == .done }

    public func children(of id: IssueID) -> [Issue] {
        (childIDs[id] ?? []).compactMap { byID[$0] }
    }

    /// Issues that list `id` as a blocker.
    public func dependents(of id: IssueID) -> [Issue] {
        (dependentIDs[id] ?? []).compactMap { byID[$0] }
    }

    /// Nearest parent first. Stops at missing parents and at cycles.
    public func ancestors(of issue: Issue) -> [Issue] {
        var result: [Issue] = []
        var seen: Set<IssueID> = [issue.id]
        var next = issue.parentID
        while let id = next, seen.insert(id).inserted, let parent = byID[id] {
            result.append(parent)
            next = parent.parentID
        }
        return result
    }

    public func isDescendant(_ issue: Issue, of ancestorID: IssueID) -> Bool {
        ancestors(of: issue).contains { $0.id == ancestorID }
    }

    /// All descendants, breadth first, cycle safe.
    public func descendants(of id: IssueID) -> [Issue] {
        Self.descendants(of: id, childIDs: childIDs, byID: byID)
    }

    private static func descendants(
        of id: IssueID,
        childIDs: [IssueID: [IssueID]],
        byID: [IssueID: Issue]
    ) -> [Issue] {
        var result: [Issue] = []
        var seen: Set<IssueID> = [id]
        var queue = childIDs[id] ?? []
        var position = 0
        while position < queue.count {
            let next = queue[position]
            position += 1
            guard seen.insert(next).inserted, let issue = byID[next] else { continue }
            result.append(issue)
            queue.append(contentsOf: childIDs[next] ?? [])
        }
        return result
    }

    /// Blockers present in this snapshot, finished or not.
    public func blockers(of issue: Issue) -> [Issue] {
        issue.dependencies
            .filter { $0.kind == .blocks && $0.dependsOnID != issue.id }
            .compactMap { byID[$0.dependsOnID] }
    }

    /// Blockers that have not reached the done category. Unknown local ids don't block.
    public func openBlockers(of issue: Issue) -> [Issue] {
        blockers(of: issue).filter { !isDone($0) }
    }

    /// Cross-project dependencies (`external:<project>:<capability>`). bd treats them as
    /// blocking until the other project ships, which this snapshot can't see.
    public func externalBlockers(of issue: Issue) -> [IssueID] {
        issue.dependencies
            .filter { $0.kind == .blocks && $0.dependsOnID.rawValue.hasPrefix("external:") }
            .map(\.dependsOnID)
    }

    public func isBlocked(_ issue: Issue) -> Bool {
        guard !isDone(issue) else { return false }
        return issue.status == "blocked"
            || !openBlockers(of: issue).isEmpty
            || !externalBlockers(of: issue).isEmpty
    }

    /// Closed vs total across all descendants; nil for leaves.
    public func progress(of id: IssueID) -> Completion? {
        completionByID[id]
    }
}
