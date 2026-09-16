import BeadsCore
import Foundation

/// Translates bd's `--json` output into domain values. Unknown fields are ignored, missing
/// optional fields get defaults, and a record that can't be read at all is skipped and
/// counted, so one odd row never hides the whole database.
public enum BDJSON {
    /// `bd history <id> --json`: one entry per Dolt commit, each with a snapshot of the issue.
    /// The commit date is used rather than the issue's `updated_at`, which several commits share.
    public static func decodeHistory(_ data: Data) throws -> [IssueVersion] {
        guard let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw DecodingFailure(detail: "bd history didn't return a list of commits")
        }
        return rows.compactMap { row in
            guard let date = parseDate(row["CommitDate"] as? String),
                  let issueObject = row["Issue"],
                  let issueData = try? JSONSerialization.data(withJSONObject: [issueObject]),
                  let issue = try? decodeIssueList(issueData).issues.first
            else { return nil }
            return IssueVersion(date: date, issue: issue)
        }
    }

    public struct DecodingFailure: Error, Equatable {
        public let detail: String
    }

    public struct DecodedIssues: Sendable {
        public let issues: [Issue]
        public let unreadableCount: Int
    }

    public static func decodeIssues(_ data: Data) throws -> [Issue] {
        try decodeIssueList(data).issues
    }

    public static func decodeIssueList(_ data: Data) throws -> DecodedIssues {
        if String(decoding: data, as: UTF8.self).allSatisfy(\.isWhitespace) {
            return DecodedIssues(issues: [], unreadableCount: 0)
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        do {
            let records = try decoder.decode([LenientIssueRecord].self, from: data)
            let issues = records.compactMap { $0.record?.toDomain() }
            return DecodedIssues(issues: issues, unreadableCount: records.count - issues.count)
        } catch {
            throw DecodingFailure(detail: String(describing: error))
        }
    }

    public static func decodeStatusCatalog(_ data: Data) throws -> StatusCatalog {
        do {
            // bd groups statuses under keys like built_in_statuses / custom_statuses.
            let groups = try JSONDecoder().decode([String: LenientStatusList].self, from: data)
            var categories: [String: StatusCategory] = [:]
            for status in groups.values.flatMap(\.statuses) {
                if let category = StatusCategory(rawValue: status.category) {
                    categories[status.name] = category
                }
            }
            return StatusCatalog(categories)
        } catch {
            throw DecodingFailure(detail: String(describing: error))
        }
    }

    /// The id from `bd create --json`, which prints a single issue object.
    public static func createdID(_ data: Data) -> IssueID? {
        let object = try? JSONSerialization.jsonObject(with: data)
        let record = (object as? [String: Any]) ?? (object as? [[String: Any]])?.first
        guard let id = record?["id"] as? String, !id.isEmpty else { return nil }
        return IssueID(id)
    }

    static func parseDate(_ text: String?) -> Date? {
        guard let text, !text.isEmpty else { return nil }
        if let date = try? Date(text, strategy: .iso8601) { return date }
        return try? Date(text, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true))
    }
}

/// An array element that is `nil` when it isn't a readable issue record.
private struct LenientIssueRecord: Decodable {
    let record: IssueRecord?

    init(from decoder: Decoder) throws {
        record = try? IssueRecord(from: decoder)
    }
}

private struct IssueRecord: Decodable {
    let id: String
    let title: String?
    let description: String?
    let notes: String?
    let status: String?
    let priority: Int?
    let issueType: String?
    let assignee: String?
    let owner: String?
    let labels: [String]?
    let createdAt: String?
    let updatedAt: String?
    let startedAt: String?
    let closedAt: String?
    let closeReason: String?
    let deferUntil: String?
    let externalRef: String?
    let commentCount: Int?
    let parent: String?
    let dependencies: [DependencyRecord]?

    func toDomain() -> Issue {
        let id = IssueID(id)
        // A dependency without a target or a type can't be interpreted, so it is dropped.
        let dependencies = (dependencies ?? []).compactMap { record -> Dependency? in
            // `bd list` uses depends_on_id/type; `bd show` nests the target issue with id/dependency_type.
            guard let target = record.dependsOnId ?? record.id, let type = record.type ?? record.dependencyType else {
                return nil
            }
            return Dependency(
                issueID: IssueID(record.issueId ?? id.rawValue),
                dependsOnID: IssueID(target),
                kind: DependencyKind(rawValue: type)
            )
        }
        let parentID = parent.map { IssueID($0) }
            ?? dependencies.first { $0.kind == .parentChild && $0.issueID == id }?.dependsOnID
        let created = BDJSON.parseDate(createdAt) ?? BDJSON.parseDate(updatedAt) ?? .distantPast
        return Issue(
            id: id,
            title: title ?? "(untitled)",
            description: description ?? "",
            notes: notes ?? "",
            status: status ?? "open",
            priority: priority ?? 2,
            type: issueType ?? "task",
            assignee: nonEmpty(assignee),
            owner: nonEmpty(owner),
            labels: labels ?? [],
            createdAt: created,
            updatedAt: BDJSON.parseDate(updatedAt) ?? created,
            startedAt: BDJSON.parseDate(startedAt),
            closedAt: BDJSON.parseDate(closedAt),
            closeReason: nonEmpty(closeReason),
            deferUntil: BDJSON.parseDate(deferUntil),
            parentID: parentID,
            dependencies: dependencies,
            externalRef: nonEmpty(externalRef),
            commentCount: commentCount ?? 0
        )
    }

    private func nonEmpty(_ text: String?) -> String? {
        text.flatMap { $0.isEmpty ? nil : $0 }
    }
}

private struct DependencyRecord: Decodable {
    let issueId: String?
    let dependsOnId: String?
    let type: String?
    let id: String?
    let dependencyType: String?
}

private struct StatusRecord: Decodable {
    let name: String
    let category: String
}

/// Decodes a status array, or nothing for non-array values such as `schema_version`.
private struct LenientStatusList: Decodable {
    let statuses: [StatusRecord]

    init(from decoder: Decoder) throws {
        statuses = (try? [StatusRecord](from: decoder)) ?? []
    }
}
