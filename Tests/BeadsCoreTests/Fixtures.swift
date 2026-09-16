import BeadsCore
import Foundation

let t0 = Date(timeIntervalSince1970: 1_800_000_000)

func hours(_ n: Double) -> TimeInterval { n * 3600 }
func days(_ n: Double) -> TimeInterval { n * 86_400 }

func makeIssue(
    _ id: IssueID,
    title: String? = nil,
    description: String = "",
    notes: String = "",
    status: String = "open",
    priority: Int = 2,
    type: String = "task",
    assignee: String? = nil,
    labels: [String] = [],
    parent: IssueID? = nil,
    blockedBy: [IssueID] = [],
    created: Date = t0,
    updated: Date = t0,
    closed: Date? = nil,
    deferUntil: Date? = nil
) -> Issue {
    Issue(
        id: id,
        title: title ?? "Issue \(id)",
        description: description,
        notes: notes,
        status: status,
        priority: priority,
        type: type,
        assignee: assignee,
        labels: labels,
        createdAt: created,
        updatedAt: updated,
        closedAt: closed,
        deferUntil: deferUntil,
        parentID: parent,
        dependencies: blockedBy.map { Dependency(issueID: id, dependsOnID: $0, kind: .blocks) }
    )
}
