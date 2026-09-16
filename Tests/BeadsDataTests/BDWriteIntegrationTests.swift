import BeadsCore
import BeadsData
import Foundation
import Testing

private let writableWorkspace: String? = {
    guard let path = ProcessInfo.processInfo.environment["BEADY_IT_WRITABLE_WORKSPACE"] else { return nil }
    // Refuse any database that hasn't been explicitly marked as a throwaway.
    let marker = URL(fileURLWithPath: path).appendingPathComponent(".beady-scratch")
    return FileManager.default.fileExists(atPath: marker.path) ? path : nil
}()

/// Opt-in and destructive to its target, so it only runs against a workspace containing a
/// `.beady-scratch` marker file:
///     BEADY_IT_WRITABLE_WORKSPACE=/path/to/scratch scripts/test.sh
@Suite("bd write integration", .enabled(if: writableWorkspace != nil), .serialized)
struct BDWriteIntegrationTests {
    @Test("create, edit, move between epics and change status through the real bd, verified each time")
    func fullRoundTrip() async throws {
        let path = try #require(writableWorkspace)
        let store = BDStore(gateway: try BDGateway.open(URL(fileURLWithPath: path)))
        let runner = ChangeRunner(writer: store)
        let stamp = UUID().uuidString.prefix(6)

        var snapshot = try await store.loadSnapshot()
        let epicA = try await runner.run(.create(NewIssue(title: "IT epic A \(stamp)", type: "epic")), seenIn: snapshot)
        snapshot = try await store.loadSnapshot()
        let epicB = try await runner.run(.create(NewIssue(title: "IT epic B \(stamp)", type: "epic")), seenIn: snapshot)
        snapshot = try await store.loadSnapshot()
        let child = try await runner.run(
            .create(NewIssue(title: "-p 0 flag-like \(stamp)", description: "line one\nline two", parent: epicA)),
            seenIn: snapshot
        )

        snapshot = try await store.loadSnapshot()
        try await runner.run(.edit(child, IssueEdit(title: "Edited \(stamp)", notes: "note", priority: 1)), seenIn: snapshot)

        snapshot = try await store.loadSnapshot()
        try await runner.run(.setParent(child, from: epicA, to: epicB), seenIn: snapshot)

        snapshot = try await store.loadSnapshot()
        await #expect(throws: ChangeFailure.self, "moving an epic under its own child must be refused") {
            try await runner.run(.setParent(epicB, from: nil, to: child), seenIn: snapshot)
        }

        snapshot = try await store.loadSnapshot()
        try await runner.run(.setStatus(child, from: "open", to: "closed", reason: "integration test"), seenIn: snapshot)
        snapshot = try await store.loadSnapshot()
        try await runner.run(.setStatus(child, from: "closed", to: "in_progress", reason: "reopened by test"), seenIn: snapshot)

        let final = try await store.loadSnapshot()
        let issue = try #require(final.issue(child))
        #expect(issue.title == "Edited \(stamp)")
        #expect(issue.notes == "note")
        #expect(issue.priority == 1)
        #expect(issue.parentID == epicB)
        #expect(issue.status == "in_progress")
        #expect(final.issue(epicB)?.parentID == nil, "the refused cycle left no trace")
    }

    @Test("pinning and starring go through bd and come back on the bead")
    func marksThroughRealBD() async throws {
        let path = try #require(writableWorkspace)
        let store = BDStore(gateway: try BDGateway.open(URL(fileURLWithPath: path)))
        let runner = ChangeRunner(writer: store)
        let stamp = UUID().uuidString.prefix(6)

        var snapshot = try await store.loadSnapshot()
        let id = try await runner.run(.create(NewIssue(title: "IT mark \(stamp)")), seenIn: snapshot)

        for mark in IssueMark.allCases {
            snapshot = try await store.loadSnapshot()
            _ = try await runner.run(.setMark(id, mark, on: true), seenIn: snapshot)
            let marked = try #require(try await store.currentIssue(id))
            #expect(marked.has(mark), "bd should have the \(mark.label) label")

            snapshot = try await store.loadSnapshot()
            _ = try await runner.run(.setMark(id, mark, on: false), seenIn: snapshot)
            let cleared = try #require(try await store.currentIssue(id))
            #expect(!cleared.has(mark))

            // Straight back on again: the case the owner found slow, proved to work.
            snapshot = try await store.loadSnapshot()
            _ = try await runner.run(.setMark(id, mark, on: true), seenIn: snapshot)
            #expect(try #require(try await store.currentIssue(id)).has(mark))
        }

        snapshot = try await store.loadSnapshot()
        _ = try await runner.run(.setStatus(id, from: "open", to: "closed", reason: "integration test tidy-up"), seenIn: snapshot)
    }
}
