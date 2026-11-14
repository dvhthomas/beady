import BeadsCore
import Foundation
import Testing

@Suite("A view is a saved filter with a saved presentation")
struct IssueViewTests {
    let view = IssueView(
        id: "agent-tiles",
        name: "Agent tiles",
        symbol: "square.grid.3x3",
        filter: ViewFilter(rules: [FilterRule(field: .labels, op: .includesAny, values: ["agent-tiles"])]),
        presentation: ViewPresentation(layout: .board, grouping: .status, ordering: .priority, columns: ["priority", "id", "title"])
    )

    @Test("a view round-trips through JSON")
    func roundTrip() throws {
        let data = try JSONEncoder().encode(view)
        let decoded = try JSONDecoder().decode(IssueView.self, from: data)
        #expect(decoded == view)
        #expect(!decoded.isBuiltIn)
    }

    @Test("the document carries a beadyView version header, and ids are plain strings")
    func format() throws {
        let data = try JSONEncoder().encode(view)
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["beadyView"] as? Int == IssueView.formatVersion)
        #expect(json["id"] as? String == "agent-tiles")
        #expect(json["name"] as? String == "Agent tiles")
        #expect((json["presentation"] as? [String: Any])?["layout"] as? String == "board")
        #expect(json["isBuiltIn"] == nil, "only user views are written out, so the flag is left off")
    }

    @Test("a document from a newer Beady is refused rather than half-read")
    func newerVersion() throws {
        var data = try JSONEncoder().encode(view)
        var json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        json["beadyView"] = IssueView.formatVersion + 1
        data = try JSONSerialization.data(withJSONObject: json)
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(IssueView.self, from: data) }
    }

    @Test("columns are optional: nil means the layout's own defaults")
    func columns() throws {
        var plain = view
        plain.presentation.columns = nil
        let data = try JSONEncoder().encode(plain)
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect((json["presentation"] as? [String: Any])?["columns"] == nil)
        let decoded = try JSONDecoder().decode(IssueView.self, from: data)
        #expect(decoded.presentation.columns == nil)
    }

    @Test("nesting sub-tasks is optional: set it round-trips, unset writes no key, old files read as off")
    func nestsSubtasks() throws {
        var nested = view
        nested.presentation.nestsSubtasks = true
        let decoded = try JSONDecoder().decode(IssueView.self, from: JSONEncoder().encode(nested))
        #expect(decoded.presentation.nestsSubtasks == true)

        let data = try JSONEncoder().encode(view)
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect((json["presentation"] as? [String: Any])?["nestsSubtasks"] == nil, "a view that never set it writes no key")
        #expect(try JSONDecoder().decode(IssueView.self, from: data).presentation.nestsSubtasks == nil, "and a file without the key reads as off")
    }
}
