import BeadsCore
import BeadsData
import Foundation
import Testing

@Suite("bd JSON decoding")
struct BDJSONDecodingTests {
    @Test("maps a full bd list record onto the domain")
    func fullRecord() throws {
        let issues = try BDJSON.decodeIssues(Data(sampleListJSON.utf8))
        let child = try #require(issues.first { $0.id == "demo-ep1.1" })
        #expect(child.title == "Globe midpoint")
        #expect(child.notes == "PR opened")
        #expect(child.status == "in_progress")
        #expect(child.priority == 1)
        #expect(child.type == "bug")
        #expect(child.assignee == "Dana")
        #expect(child.labels == ["projections"])
        #expect(child.parentID == "demo-ep1")
        #expect(child.commentCount == 3)
        #expect(child.dependencies.contains(Dependency(issueID: "demo-ep1.1", dependsOnID: "demo-xyz", kind: .blocks)))
        #expect(child.startedAt == ISO8601DateFormatter().date(from: "2026-09-14T01:22:05Z"))
    }

    @Test("accepts fractional-second timestamps")
    func fractionalSeconds() throws {
        let issues = try BDJSON.decodeIssues(Data(sampleListJSON.utf8))
        let child = try #require(issues.first { $0.id == "demo-ep1.1" })
        let whole = try #require(ISO8601DateFormatter().date(from: "2026-09-14T01:21:14Z"))
        #expect(abs(child.createdAt.timeIntervalSince(whole) - 0.123) < 0.001)
    }

    @Test("closed record keeps close reason and external ref; empty assignee means unassigned")
    func closedRecord() throws {
        let issues = try BDJSON.decodeIssues(Data(sampleListJSON.utf8))
        let closed = try #require(issues.first { $0.id == "demo-xyz" })
        #expect(closed.closeReason == "merged in PR #292")
        #expect(closed.externalRef == "gh-154")
        #expect(closed.closedAt != nil)
        #expect(closed.assignee == nil)
    }

    @Test("derives the parent from a parent-child dependency and defaults missing fields")
    func sparseRecord() throws {
        let issues = try BDJSON.decodeIssues(Data(sampleListJSON.utf8))
        let sparse = try #require(issues.first { $0.id == "demo-ep1.2" })
        #expect(sparse.parentID == "demo-ep1")
        #expect(sparse.priority == 2)
        #expect(sparse.type == "task")
        #expect(sparse.labels.isEmpty)
        #expect(sparse.description.isEmpty)
    }

    @Test("blank output means an empty database")
    func blankOutput() throws {
        #expect(try BDJSON.decodeIssues(Data("  \n".utf8)).isEmpty)
    }

    @Test("garbage output is reported, not swallowed")
    func garbage() {
        #expect(throws: BDJSON.DecodingFailure.self) {
            try BDJSON.decodeIssues(Data("No issues found.".utf8))
        }
    }

    @Test("status catalog merges built-in and custom statuses, skipping unknown categories")
    func statusCatalog() throws {
        let catalog = try BDJSON.decodeStatusCatalog(Data(sampleStatusesJSON.utf8))
        #expect(catalog.category(of: "review") == .wip)
        #expect(catalog.category(of: "in_progress") == .wip)
        #expect(catalog.category(of: "weird") == .active)
    }

    @Test("a malformed record is skipped and counted instead of failing the whole load")
    func malformedRecords() throws {
        let json = """
        [
          {"id": "ok-1", "title": "Fine", "status": "open"},
          {"title": "no id"},
          42,
          {"id": "sparse-1", "dependencies": [{"depends_on_id": "ok-1"}, {"type": "blocks"}]}
        ]
        """
        let decoded = try BDJSON.decodeIssueList(Data(json.utf8))
        #expect(decoded.issues.map(\.id) == ["ok-1", "sparse-1"])
        #expect(decoded.unreadableCount == 2)
        let sparse = try #require(decoded.issues.last)
        #expect(sparse.title == "(untitled)")
        #expect(sparse.status == "open")
        #expect(sparse.dependencies.isEmpty, "dependencies missing a type or target are dropped")
    }

    @Test("defer_until is decoded")
    func deferUntil() throws {
        let json = #"[{"id": "d-1", "title": "Later", "status": "open", "defer_until": "2026-10-01T00:00:00Z"}]"#
        let issue = try #require(try BDJSON.decodeIssues(Data(json.utf8)).first)
        #expect(issue.deferUntil == ISO8601DateFormatter().date(from: "2026-10-01T00:00:00Z"))
    }
}
