import BeadsCore

/// One visible row of the tree layout. The tree is flattened here, with expansion state
/// applied, so the view is a plain list rather than nested disclosure groups.
public struct OutlineRow: Identifiable, Hashable, Sendable {
    public let node: IssueTreeNode
    public let depth: Int
    public let isExpanded: Bool

    public var id: IssueID { node.id }
    public var hasChildren: Bool { !node.children.isEmpty }

    /// Depth first. Branches are expanded unless their id is in `collapsed`.
    public static func flatten(_ nodes: [IssueTreeNode], collapsed: Set<IssueID>) -> [OutlineRow] {
        var rows: [OutlineRow] = []
        func visit(_ node: IssueTreeNode, depth: Int) {
            let expanded = !collapsed.contains(node.id)
            rows.append(OutlineRow(node: node, depth: depth, isExpanded: expanded))
            guard expanded else { return }
            for child in node.children {
                visit(child, depth: depth + 1)
            }
        }
        for node in nodes {
            visit(node, depth: 0)
        }
        return rows
    }
}
