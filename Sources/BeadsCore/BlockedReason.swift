import Foundation

/// Why a bead can't proceed, in the terms bd actually records.
///
/// bd uses one word, "blocked", for three different situations, and stores no free text about
/// any of them: `bd update` has no `--reason`, and a dependency carries a type but no note. So
/// the honest answer is the blocking bead itself, the other project, or the plain fact that
/// somebody set the status.
public struct BlockedReason: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        /// Unfinished beads have to land first. The actionable case.
        case waitingOnBeads
        /// An `external:<project>:<capability>` dependency: another project has to ship.
        case waitingOnAnotherProject
        /// Someone set the status to `blocked` and bd recorded no more than that.
        case declared
    }

    public let kind: Kind
    /// Unfinished beads in the way, nearest first.
    public let blockers: [Issue]
    /// `project:capability` for anything waiting on another project.
    public let externalCapabilities: [String]
    /// True when the status itself says blocked, whatever else is true.
    public let isDeclared: Bool

    /// Nothing upstream is recorded — so the app should say who marked it and when, and no more.
    public var isDeclaredOnly: Bool { kind == .declared }

    /// The shortest useful answer, for a row or a chip.
    public var summary: String {
        switch kind {
        case .waitingOnBeads:
            let names = blockers.prefix(2).map(\.id.rawValue).joined(separator: ", ")
            let extra = blockers.count > 2 ? " +\(blockers.count - 2)" : ""
            return "Waiting on \(names)\(extra)"
        case .waitingOnAnotherProject:
            return "Waiting on \(externalCapabilities.joined(separator: ", "))"
        case .declared:
            return "Marked blocked"
        }
    }

    /// Nil when the bead isn't waiting for anything — which includes a bead whose blockers have
    /// all been closed.
    public static func of(_ id: IssueID, in snapshot: IssueSnapshot) -> BlockedReason? {
        guard let issue = snapshot.issue(id), !snapshot.isDone(issue) else { return nil }
        let blockers = snapshot.openBlockers(of: issue)
        let external = snapshot.externalBlockers(of: issue).map {
            String($0.rawValue.dropFirst("external:".count))
        }
        let declared = issue.status == "blocked"
        guard !blockers.isEmpty || !external.isEmpty || declared else { return nil }

        let kind: Kind = if !blockers.isEmpty {
            .waitingOnBeads
        } else if !external.isEmpty {
            .waitingOnAnotherProject
        } else {
            .declared
        }
        return BlockedReason(
            kind: kind,
            blockers: blockers.sorted { $0.id < $1.id },
            externalCapabilities: external.sorted(),
            isDeclared: declared
        )
    }
}
