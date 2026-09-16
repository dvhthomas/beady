import BeadsData
import Foundation

/// Records invocations and replays canned results, so loader tests never touch a real bd.
final class FakeRunner: CommandRunning, @unchecked Sendable {
    struct Invocation: Equatable {
        let executable: URL
        let arguments: [String]
    }

    private let lock = NSLock()
    private var _invocations: [Invocation] = []
    private let respond: @Sendable ([String]) throws -> CommandResult

    init(respond: @escaping @Sendable ([String]) throws -> CommandResult) {
        self.respond = respond
    }

    var invocations: [Invocation] { lock.withLock { _invocations } }

    func run(_ executable: URL, arguments: [String], timeout: TimeInterval) async throws -> CommandResult {
        lock.withLock { _invocations.append(Invocation(executable: executable, arguments: arguments)) }
        return try respond(arguments)
    }
}

func ok(_ stdout: String, stderr: String = "") -> CommandResult {
    CommandResult(exitCode: 0, stdout: Data(stdout.utf8), stderr: stderr)
}

func waitUntil(seconds: TimeInterval, _ condition: () -> Bool) async -> Bool {
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(50))
    }
    return condition()
}

/// A pid written by a shell script as `echo $$ > file`, once the line is complete.
func readPID(_ file: URL) -> Int32? {
    guard let text = try? String(contentsOf: file, encoding: .utf8), text.hasSuffix("\n") else { return nil }
    return Int32(text.trimmingCharacters(in: .whitespacesAndNewlines))
}

func makeTempDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("beads-viewer-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

let sampleListJSON = """
[
  {
    "id": "demo-ep1",
    "title": "Lane: looks",
    "description": "Epic description",
    "status": "open",
    "priority": 2,
    "issue_type": "epic",
    "owner": "someone@example.com",
    "created_at": "2026-09-13T19:07:37Z",
    "created_by": "Someone",
    "updated_at": "2026-09-13T19:07:37Z",
    "labels": ["lane", "plan-023"],
    "dependency_count": 0,
    "dependent_count": 2,
    "comment_count": 0
  },
  {
    "id": "demo-ep1.1",
    "title": "Globe midpoint",
    "description": "Found by task 3.4",
    "notes": "PR opened",
    "status": "in_progress",
    "priority": 1,
    "issue_type": "bug",
    "assignee": "Dana",
    "created_at": "2026-09-14T01:21:14.123Z",
    "updated_at": "2026-09-14T01:50:31Z",
    "started_at": "2026-09-14T01:22:05Z",
    "labels": ["projections"],
    "dependencies": [
      {"issue_id": "demo-ep1.1", "depends_on_id": "demo-ep1", "type": "parent-child", "created_at": "2026-09-13T18:21:14Z", "metadata": "{}"},
      {"issue_id": "demo-ep1.1", "depends_on_id": "demo-xyz", "type": "blocks", "created_at": "2026-09-13T18:21:14Z", "metadata": "{}"}
    ],
    "comment_count": 3,
    "parent": "demo-ep1"
  },
  {
    "id": "demo-xyz",
    "title": "Landing hero warp",
    "status": "closed",
    "priority": 1,
    "issue_type": "bug",
    "assignee": "",
    "created_at": "2026-09-14T02:33:07Z",
    "updated_at": "2026-09-14T14:47:02Z",
    "closed_at": "2026-09-14T14:47:02Z",
    "close_reason": "merged in PR #292",
    "external_ref": "gh-154",
    "labels": [],
    "comment_count": 1
  },
  {
    "id": "demo-ep1.2",
    "title": "Child without parent field",
    "status": "open",
    "created_at": "2026-09-14T02:33:07Z",
    "updated_at": "2026-09-14T02:33:07Z",
    "dependencies": [
      {"issue_id": "demo-ep1.2", "depends_on_id": "demo-ep1", "type": "parent-child"}
    ]
  }
]
"""

let sampleStatusesJSON = """
{
  "built_in_statuses": [
    {"category": "active", "description": "Available", "icon": "○", "name": "open"},
    {"category": "wip", "icon": "◐", "name": "in_progress"},
    {"category": "done", "icon": "✓", "name": "closed"}
  ],
  "custom_statuses": [
    {"category": "wip", "name": "review"},
    {"category": "someday", "name": "weird"}
  ],
  "schema_version": 1
}
"""

final class Mutable<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: Value
    init(_ value: Value) { _value = value }
    var value: Value {
        get { lock.withLock { _value } }
        set { lock.withLock { _value = newValue } }
    }
}
