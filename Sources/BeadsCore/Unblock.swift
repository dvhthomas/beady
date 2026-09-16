import Foundation

/// The work that has to finish before a bead can start, in the order it can be done.
///
/// bd computes the same thing for the terminal (`bd graph` lays issues out in layers, layer 0
/// being what can start immediately). This works from the loaded snapshot so the answer is
/// instant and testable; an opt-in integration test checks it against bd itself.
public struct UnblockPath: Equatable, Sendable {
    /// Layer 0 can be started now; each later layer waits on the one before it.
    public let layers: [[Issue]]
    /// True when the blockers form a loop — bd allows creating one, so this has to be survivable.
    public let hasCycle: Bool

    public var isBlocked: Bool { !layers.isEmpty }

    /// Everything still in the way, nearest first.
    public var work: [Issue] { layers.flatMap { $0 } }

    public static func to(_ id: IssueID, in snapshot: IssueSnapshot) -> UnblockPath {
        var depth: [IssueID: Int] = [:]
        var issues: [IssueID: Issue] = [:]
        var seen: Set<IssueID> = [id]
        var hasCycle = false
        var frontier: [(IssueID, Int)] = [(id, -1)]

        while let (current, level) = frontier.popLast() {
            guard let issue = snapshot.issue(current) else { continue }
            for blocker in snapshot.openBlockers(of: issue) {
                if blocker.id == id {
                    hasCycle = true
                    continue
                }
                if let existing = depth[blocker.id] {
                    // Reached again by a longer route: it has to wait for that one too.
                    if existing >= level + 1 { continue }
                    hasCycle = hasCycle || seen.contains(blocker.id) && existing > level + 1
                }
                if !seen.insert(blocker.id).inserted, depth[blocker.id] == nil {
                    hasCycle = true
                    continue
                }
                depth[blocker.id] = max(depth[blocker.id] ?? 0, level + 1)
                issues[blocker.id] = blocker
                frontier.append((blocker.id, level + 1))
            }
        }

        guard !depth.isEmpty else { return UnblockPath(layers: [], hasCycle: hasCycle) }

        // A bead can only start once everything it waits on is done, so its layer is one past its
        // deepest blocker; counting from the far end puts "start now" first.
        let deepest = depth.values.max() ?? 0
        var layers: [[Issue]] = Array(repeating: [], count: deepest + 1)
        for (blocker, level) in depth {
            guard let issue = issues[blocker] else { continue }
            layers[deepest - level].append(issue)
        }
        return UnblockPath(
            layers: layers.map { $0.sorted { $0.id < $1.id } }.filter { !$0.isEmpty },
            hasCycle: hasCycle
        )
    }
}

/// One bead and what sits immediately around it, which is as much graph as a person can read.
public struct IssueNeighbourhood: Equatable, Sendable {
    public let subject: Issue
    /// Unfinished beads this one waits on.
    public let blockers: [Issue]
    /// Beads waiting on this one.
    public let dependents: [Issue]
    public let parent: Issue?
    public let children: [Issue]

    public static func around(_ id: IssueID, in snapshot: IssueSnapshot) -> IssueNeighbourhood? {
        guard let subject = snapshot.issue(id) else { return nil }
        return IssueNeighbourhood(
            subject: subject,
            blockers: snapshot.openBlockers(of: subject).sorted { $0.id < $1.id },
            dependents: snapshot.issues.filter { issue in
                snapshot.blockers(of: issue).contains { $0.id == id }
            }.sorted { $0.id < $1.id },
            parent: subject.parentID.flatMap { snapshot.issue($0) },
            children: snapshot.children(of: id)
        )
    }
}
