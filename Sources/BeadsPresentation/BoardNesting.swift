import BeadsCore
import Foundation

/// One direct child folded into a parent's board card.
public struct BoardChildRow: Identifiable, Equatable, Sendable {
    public let issue: Issue
    /// The child's own subtree progress, when it has children of its own.
    public let completion: Completion?

    public var id: IssueID { issue.id }
}

/// One board card: a bead, plus the direct children folded into it. No children means the card
/// is just the bead, as every card is with nesting off.
public struct BoardCardModel: Identifiable, Equatable, Sendable {
    public let issue: Issue
    public let children: [BoardChildRow]

    public var id: IssueID { issue.id }
}

/// One board column of cards: an IssueGroupModel with nesting applied.
public struct BoardColumnModel: Identifiable, Equatable, Sendable {
    public let key: String
    public let title: String
    public let cards: [BoardCardModel]

    public var id: String { key }
}

/// Folds sub-tasks into their parents' board cards.
///
/// A bead folds exactly when its direct parent keeps a card of its own on the board — so one
/// level ever nests (the child of a folded bead keeps its card), nothing disappears, and a bead
/// whose parent the filter left out stays a card. Folding is board-wide, not per-column: a child
/// in another column still folds into its parent's card — that is the declutter, and the child
/// row's own status glyph keeps the information the column gave.
public enum BoardNesting {
    public static func columns(from groups: [IssueGroupModel], in snapshot: IssueSnapshot, nesting: Bool) -> [BoardColumnModel] {
        guard nesting else {
            return groups.map { group in
                BoardColumnModel(key: group.key, title: group.title, cards: group.issues.map { BoardCardModel(issue: $0, children: []) })
            }
        }
        let visible = Set(groups.flatMap { $0.issues.map(\.id) })
        var folds: [IssueID: Bool] = [:]
        // Whether a bead folds away into its parent's card, walking up the chain; a parent
        // cycle breaks the walk and the bead keeps its card.
        func foldsAway(_ id: IssueID, seen: inout Set<IssueID>) -> Bool {
            if let known = folds[id] { return known }
            guard seen.insert(id).inserted else { return false }
            guard let parent = snapshot.issue(id)?.parentID, visible.contains(parent) else {
                folds[id] = false
                return false
            }
            let parentKeepsCard = !foldsAway(parent, seen: &seen)
            folds[id] = parentKeepsCard
            return parentKeepsCard
        }
        for id in visible.sorted() {
            var seen = Set<IssueID>()
            _ = foldsAway(id, seen: &seen)
        }
        // Children keep the view's own ordering: the order the groups listed them in.
        var childrenOf: [IssueID: [BoardChildRow]] = [:]
        for group in groups {
            for issue in group.issues where folds[issue.id] == true {
                guard let parent = issue.parentID else { continue }
                childrenOf[parent, default: []].append(BoardChildRow(issue: issue, completion: snapshot.progress(of: issue.id)))
            }
        }
        return groups.map { group in
            BoardColumnModel(
                key: group.key,
                title: group.title,
                cards: group.issues.filter { folds[$0.id] != true }.map {
                    BoardCardModel(issue: $0, children: childrenOf[$0.id] ?? [])
                }
            )
        }
    }

    /// The selectable ids of one column, top to bottom: each card, then its children while the
    /// card is expanded. What you can't see, you can't land on.
    public static func selectableIDs(in column: BoardColumnModel, expanded: Set<IssueID>) -> [IssueID] {
        column.cards.flatMap { card in
            [card.id] + (expanded.contains(card.id) ? card.children.map(\.id) : [])
        }
    }
}
