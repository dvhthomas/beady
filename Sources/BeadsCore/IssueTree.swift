public struct IssueTreeNode: Identifiable, Hashable, Sendable {
    public let issue: Issue
    /// False when the node is shown only as context for a matching descendant.
    public let isMatch: Bool
    public let children: [IssueTreeNode]

    public var id: IssueID { issue.id }

    /// `nil` for leaves, which is the shape SwiftUI's outline views expect.
    public var childrenOrNil: [IssueTreeNode]? { children.isEmpty ? nil : children }
}

public enum IssueTree {
    /// Builds the parent-child forest for `matches`. Unmatched ancestors are kept as
    /// context so a match is never shown orphaned. Siblings keep the order of `matches`.
    public static func build(matches: [Issue], in snapshot: IssueSnapshot) -> [IssueTreeNode] {
        let matchIDs = Set(matches.map(\.id))
        var members: [IssueID: Issue] = [:]
        var rank: [IssueID: Int] = [:]
        for (index, issue) in matches.enumerated() {
            for member in [issue] + snapshot.ancestors(of: issue) {
                members[member.id] = member
                rank[member.id] = min(rank[member.id] ?? index, index)
            }
        }

        var childIDs: [IssueID: [IssueID]] = [:]
        var rootIDs: [IssueID] = []
        for (id, issue) in members {
            if let parent = issue.parentID, parent != id, members[parent] != nil {
                childIDs[parent, default: []].append(id)
            } else {
                rootIDs.append(id)
            }
        }

        let inOrder: (IssueID, IssueID) -> Bool = { (rank[$0] ?? 0, $0) < (rank[$1] ?? 0, $1) }
        var visited: Set<IssueID> = []
        func node(_ id: IssueID) -> IssueTreeNode? {
            guard visited.insert(id).inserted, let issue = members[id] else { return nil }
            let children = (childIDs[id] ?? []).sorted(by: inOrder).compactMap(node)
            return IssueTreeNode(issue: issue, isMatch: matchIDs.contains(id), children: children)
        }

        var forest = rootIDs.sorted(by: inOrder).compactMap(node)
        // Members of a parent cycle are unreachable from any root; surface them as roots.
        for id in members.keys.sorted(by: inOrder) where !visited.contains(id) {
            if let orphan = node(id) { forest.append(orphan) }
        }
        return forest
    }
}

public struct BoardColumn: Identifiable, Hashable, Sendable {
    public let category: StatusCategory
    public let issues: [Issue]

    public init(category: StatusCategory, issues: [Issue]) {
        self.category = category
        self.issues = issues
    }

    public var id: StatusCategory { category }
}

public enum IssueBoard {
    /// One column per lifecycle category, in lifecycle order. Frozen only appears when non-empty.
    public static func columns(for issues: [Issue], in snapshot: IssueSnapshot) -> [BoardColumn] {
        let grouped = Dictionary(grouping: issues) { snapshot.category(of: $0) }
        return StatusCategory.allCases.compactMap { category in
            let members = grouped[category] ?? []
            if category == .frozen, members.isEmpty { return nil }
            return BoardColumn(category: category, issues: members)
        }
    }
}
