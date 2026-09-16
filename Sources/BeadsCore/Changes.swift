import Foundation

// MARK: Change model

/// Fields to change on an existing issue. `nil` leaves a field alone.
public struct IssueEdit: Equatable, Sendable {
    public var title: String?
    public var description: String?
    public var notes: String?
    public var priority: Int?

    public init(title: String? = nil, description: String? = nil, notes: String? = nil, priority: Int? = nil) {
        self.title = title
        self.description = description
        self.notes = notes
        self.priority = priority
    }

    public var isEmpty: Bool { title == nil && description == nil && notes == nil && priority == nil }
}

public struct NewIssue: Equatable, Sendable {
    public var title: String
    public var type: String
    public var priority: Int
    public var description: String
    public var parent: IssueID?

    public init(title: String, type: String = "task", priority: Int = 2, description: String = "", parent: IssueID? = nil) {
        self.title = title
        self.type = type
        self.priority = priority
        self.description = description
        self.parent = parent
    }
}

/// Every write the app can make. `from` values record what the change was based on.
public enum IssueChange: Equatable, Sendable {
    case edit(IssueID, IssueEdit)
    case setStatus(IssueID, from: String, to: String, reason: String?)
    case setParent(IssueID, from: IssueID?, to: IssueID?)
    case create(NewIssue)
    /// Pin or star: a bd label, on or off.
    case setMark(IssueID, IssueMark, on: Bool)

    /// The existing issue this change targets; nil for a create.
    public var issueID: IssueID? {
        switch self {
        case .edit(let id, _), .setStatus(let id, _, _, _), .setParent(let id, _, _), .setMark(let id, _, _): id
        case .create: nil
        }
    }

    /// Marks are reversible metadata, so they're applied straight away rather than through the
    /// confirmation sheet that guards content and graph edits.
    public var needsConfirmation: Bool {
        if case .setMark = self { return false }
        return true
    }

    /// Titles, types and reasons are trimmed. Descriptions and notes are kept exactly as typed
    /// (indentation matters in Markdown), except that whitespace-only text becomes empty.
    public func normalized() -> IssueChange {
        switch self {
        case .edit(let id, var edit):
            edit.title = edit.title.map(trimmed)
            edit.description = edit.description.map(blankAsEmpty)
            edit.notes = edit.notes.map(blankAsEmpty)
            return .edit(id, edit)
        case .setStatus(let id, let from, let to, let reason):
            let reason = reason.map(trimmed).flatMap { $0.isEmpty ? nil : $0 }
            return .setStatus(id, from: from, to: trimmed(to), reason: reason)
        case .setParent, .setMark:
            return self
        case .create(var new):
            new.title = trimmed(new.title)
            new.type = trimmed(new.type)
            new.description = blankAsEmpty(new.description)
            return .create(new)
        }
    }
}

func trimmed(_ text: String) -> String {
    text.trimmingCharacters(in: .whitespacesAndNewlines)
}

private func blankAsEmpty(_ text: String) -> String {
    trimmed(text).isEmpty ? "" : text
}

// MARK: Validation

public struct ChangeProblem: Equatable, Sendable {
    public enum Severity: Sendable {
        /// The change can't be made.
        case error
        /// Allowed, but worth a second look before confirming.
        case warning
    }

    public enum Code: Equatable, Sendable {
        case unknownIssue, noChange
        case emptyTitle, titleTooLong, titleHasLineBreaks, invalidPriority, invalidType
        case unknownStatus, missingCloseReason, closesPinned, closesWithOpenChildren
        case unknownParent, parentIsSelf, parentIsDescendant, closedParent
        case clearsDescription, clearsNotes
        case recentlyChangedElsewhere
    }

    public let code: Code
    public let severity: Severity
    public let message: String

    public init(code: Code, severity: Severity, message: String) {
        self.code = code
        self.severity = severity
        self.message = message
    }
}

public enum ChangeValidator {
    public static let maxTitleLength = 500
    /// bd's built-in types; custom types also count once the database uses them.
    public static let coreTypes: Set<String> = ["task", "bug", "feature", "chore", "epic", "decision", "spike"]

    /// Checks a change against the loaded data. Errors block the change; warnings don't.
    public static func problems(for change: IssueChange, in snapshot: IssueSnapshot) -> [ChangeProblem] {
        var problems: [ChangeProblem] = []
        func error(_ code: ChangeProblem.Code, _ message: String) {
            problems.append(ChangeProblem(code: code, severity: .error, message: message))
        }
        func warning(_ code: ChangeProblem.Code, _ message: String) {
            problems.append(ChangeProblem(code: code, severity: .warning, message: message))
        }
        func checkTitle(_ title: String) {
            if title.isEmpty { error(.emptyTitle, "The title can't be empty.") }
            if title.count > maxTitleLength { error(.titleTooLong, "Titles are limited to \(maxTitleLength) characters.") }
            let control = CharacterSet.controlCharacters.union(.newlines)
            if title.unicodeScalars.contains(where: control.contains) {
                error(.titleHasLineBreaks, "Titles must be a single line, without tabs or line breaks.")
            }
        }
        func checkPriority(_ priority: Int) {
            if !(0...4).contains(priority) { error(.invalidPriority, "Priority must be between P0 and P4.") }
        }

        switch change.normalized() {
        case .edit(let id, let edit):
            guard let issue = snapshot.issue(id) else {
                error(.unknownIssue, "\(id) isn't in this database.")
                break
            }
            if let title = edit.title { checkTitle(title) }
            if let priority = edit.priority { checkPriority(priority) }
            let changesSomething = [
                edit.title.map { $0 != trimmed(issue.title) },
                edit.description.map { trimmed($0) != trimmed(issue.description) },
                edit.notes.map { trimmed($0) != trimmed(issue.notes) },
                edit.priority.map { $0 != issue.priority },
            ].contains(true)
            if !changesSomething { error(.noChange, "Nothing would change.") }
            if edit.description == "", !trimmed(issue.description).isEmpty {
                warning(.clearsDescription, "This removes the whole description.")
            }
            if edit.notes == "", !trimmed(issue.notes).isEmpty {
                warning(.clearsNotes, "This removes all the notes.")
            }

        case .setStatus(let id, _, let to, let reason):
            guard let issue = snapshot.issue(id) else {
                error(.unknownIssue, "\(id) isn't in this database.")
                break
            }
            guard snapshot.catalog.knows(to) else {
                error(.unknownStatus, "“\(to)” isn't a status this database knows.")
                break
            }
            guard to != issue.status else {
                error(.noChange, "\(id) is already \(to).")
                break
            }
            if to == "closed" {
                if reason == nil {
                    error(.missingCloseReason, "Say why it's being closed. The reason is stored with the bead, and lets the app confirm the close was yours.")
                }
                if issue.status == "pinned" {
                    error(.closesPinned, "bd won't close a pinned bead.")
                }
            }
            if snapshot.catalog.category(of: to) == .done {
                let unfinished = snapshot.descendants(of: id).filter { !snapshot.isDone($0) }
                if !unfinished.isEmpty {
                    let count = "\(unfinished.count) issue\(unfinished.count == 1 ? "" : "s") under \(id) \(unfinished.count == 1 ? "isn't" : "aren't") finished."
                    if issue.type == "epic" {
                        error(.closesWithOpenChildren, "\(count) bd won't close an epic until they are.")
                    } else {
                        warning(.closesWithOpenChildren, count)
                    }
                }
            }

        case .setParent(let id, _, let to):
            guard let issue = snapshot.issue(id) else {
                error(.unknownIssue, "\(id) isn't in this database.")
                break
            }
            if to == issue.parentID {
                error(.noChange, to.map { "\(id) is already under \($0)." } ?? "\(id) has no parent already.")
                break
            }
            guard let to else { break }
            if to == id {
                error(.parentIsSelf, "An issue can't be its own parent.")
                break
            }
            guard let parent = snapshot.issue(to) else {
                error(.unknownParent, "\(to) isn't in this database.")
                break
            }
            if snapshot.isDescendant(parent, of: id) {
                error(.parentIsDescendant, "\(to) is inside \(id), so this would create a loop.")
                break
            }
            if snapshot.isDone(parent) { warning(.closedParent, "\(to) is closed.") }

        case .setMark(let id, let mark, let on):
            guard let issue = snapshot.issue(id) else {
                error(.unknownIssue, "\(id) isn't in this database.")
                break
            }
            if issue.has(mark) == on {
                error(.noChange, on ? "\(id) is already \(mark.title.lowercased())." : "\(id) isn't \(mark.title.lowercased()).")
            }

        case .create(let new):
            checkTitle(new.title)
            checkPriority(new.priority)
            if !(coreTypes.contains(new.type) || snapshot.types.contains(new.type)) {
                error(.invalidType, "“\(new.type)” isn't a known issue type.")
            }
            if let parentID = new.parent {
                if let parent = snapshot.issue(parentID) {
                    if snapshot.isDone(parent) { warning(.closedParent, "\(parentID) is closed.") }
                } else {
                    error(.unknownParent, "\(parentID) isn't in this database.")
                }
            }
        }
        return problems
    }
}

// MARK: Conflicts and verification

/// A field whose value isn't what it should be: changed by someone else before a write, or not
/// what was intended after one.
public struct ChangeConflict: Equatable, Sendable {
    public let field: String
    public let expected: String
    public let actual: String

    public init(field: String, expected: String, actual: String) {
        self.field = field
        self.expected = expected
        self.actual = actual
    }
}

public enum ChangeGuard {
    /// Fields this change touches whose live value differs from the version it was based on.
    /// Changes to other fields don't conflict: bd only writes the fields it is given.
    public static func conflicts(for change: IssueChange, seen: Issue, current: Issue) -> [ChangeConflict] {
        compare(touchedFields(change), before: seen, after: current)
    }

    /// Fields this change does *not* touch that differ between two reads: a sign that someone
    /// else wrote in between.
    public static func untouchedDifferences(for change: IssueChange, before: Issue, after: Issue) -> [ChangeConflict] {
        let touched = touchedFields(change)
        return compare(Field.tracked.filter { !touched.contains($0) }, before: before, after: after)
    }

    /// Intended values that aren't in the issue as read back after the write.
    public static func mismatches(for change: IssueChange, after: Issue) -> [ChangeConflict] {
        var result: [ChangeConflict] = []
        func expect(_ field: String, _ intended: String, _ actual: String) {
            if actual != intended { result.append(ChangeConflict(field: field, expected: intended, actual: actual)) }
        }
        switch change.normalized() {
        case .edit(_, let edit):
            if let title = edit.title { expect("title", title, trimmed(after.title)) }
            if let description = edit.description { expect("description", description, after.description) }
            if let notes = edit.notes { expect("notes", notes, after.notes) }
            if let priority = edit.priority { expect("priority", "P\(priority)", "P\(after.priority)") }
        case .setStatus(_, let from, let to, let reason):
            expect("status", to, after.status)
            if to == "closed", let reason {
                // bd close on something already closed exits 0 and keeps the old reason.
                expect("close reason", reason, after.closeReason ?? "none")
            }
            if from == "closed", to != "closed", let closedAt = after.closedAt {
                expect("closed at", "none", closedAt.formatted(.iso8601))
            }
        case .setParent(_, _, let to):
            expect("parent", to?.rawValue ?? "none", after.parentID?.rawValue ?? "none")
        case .setMark(_, let mark, let on):
            expect(mark.label, on ? "present" : "absent", after.has(mark) ? "present" : "absent")
        case .create(let new):
            expect("title", new.title, trimmed(after.title))
            expect("type", new.type, after.type)
            expect("priority", "P\(new.priority)", "P\(after.priority)")
            expect("description", new.description, after.description)
            expect("parent", new.parent?.rawValue ?? "none", after.parentID?.rawValue ?? "none")
        }
        return result
    }

    private static func touchedFields(_ change: IssueChange) -> [Field] {
        switch change {
        case .edit(_, let edit):
            return [
                edit.title.map { _ in Field.title },
                edit.description.map { _ in Field.description },
                edit.notes.map { _ in Field.notes },
                edit.priority.map { _ in Field.priority },
            ].compactMap { $0 }
        case .setStatus: return [.status]
        case .setParent: return [.parent]
        // A mark touches only its own label, and two sessions marking the same bead don't
        // conflict in any way worth stopping for.
        case .setMark, .create: return []
        }
    }

    private static func compare(_ fields: [Field], before: Issue, after: Issue) -> [ChangeConflict] {
        fields.compactMap { field in
            let old = field.read(before)
            let new = field.read(after)
            return old == new ? nil : ChangeConflict(field: field.rawValue, expected: old, actual: new)
        }
    }

    private enum Field: String {
        case title, description, notes, priority, status, parent

        static let tracked: [Field] = [.title, .description, .notes, .priority, .status, .parent]

        /// Surrounding whitespace is ignored when comparing two reads.
        func read(_ issue: Issue) -> String {
            switch self {
            case .title: trimmed(issue.title)
            case .description: trimmed(issue.description)
            case .notes: trimmed(issue.notes)
            case .priority: "P\(issue.priority)"
            case .status: issue.status
            case .parent: issue.parentID?.rawValue ?? "none"
            }
        }
    }
}

// MARK: Running a change

/// Port for writing. Implementations must not cache: reads have to reflect the source now.
public protocol IssueWriting: Sendable {
    /// A fresh read straight from the source. nil when the issue doesn't exist.
    func currentIssue(_ id: IssueID) async throws -> Issue?
    /// Issues with exactly this title created at or after `since`, used to find out whether a
    /// create that reported an error actually happened.
    func issuesCreated(titled title: String, since: Date) async throws -> [Issue]
    /// Performs the change, returning the affected issue's id (the new id for a create).
    func apply(_ change: IssueChange) async throws -> IssueID
    /// The exact commands `apply` would run, to show before confirming.
    func commandPreview(for change: IssueChange) -> [String]
}

public enum ChangeFailure: Error, Equatable, Sendable, LocalizedError {
    /// Validation failed; nothing was written.
    case rejected([ChangeProblem])
    /// The bead changed since it was seen; nothing was written.
    case conflict([ChangeConflict])
    /// The bead no longer exists; nothing was written.
    case issueDisappeared(IssueID)
    /// The write failed and the bead is as it was, so trying again is safe.
    case writeFailed(String)
    /// The write reported success but reading back doesn't show the change.
    case unverified(IssueID, [ChangeConflict])
    /// The write reported an error and the data is no longer as it was, but not as intended either.
    case uncertain(IssueID?, String)

    public var errorDescription: String? {
        switch self {
        case .rejected(let problems):
            return problems.map(\.message).joined(separator: " ")
        case .conflict(let conflicts):
            let fields = conflicts.map { "\($0.field) was “\($0.expected)”, now “\($0.actual)”" }.joined(separator: "; ")
            return "Nothing was written: this bead changed since you started (\(fields)). Review the current version and try again."
        case .issueDisappeared(let id):
            return "Nothing was written: \(id) no longer exists."
        case .writeFailed(let message):
            return message
        case .unverified(let id, let mismatches):
            let fields = mismatches.map { "\($0.field) is “\($0.actual)”, expected “\($0.expected)”" }.joined(separator: "; ")
            return "bd accepted the change, but reading \(id) back doesn't match\(fields.isEmpty ? "" : ": \(fields)"). Check it before retrying."
        case .uncertain(_, let detail):
            return detail
        }
    }
}

/// The only way changes are written: validate, check the live parent chain, compare with the live
/// issue, write, then read back and verify. A failed write is resolved by re-reading, so the result
/// says whether the change landed, didn't, or only partly did.
public struct ChangeRunner: Sendable {
    /// Parent chains longer than this are treated as broken rather than walked forever.
    private static let maxAncestry = 1_000
    /// bd timestamps have one-second resolution.
    private static let clockSlack: TimeInterval = 2

    private let writer: any IssueWriting
    private let settleDelay: Duration
    private let rereads: Int
    private let now: @Sendable () -> Date

    /// - Parameters:
    ///   - settleDelay: pause between re-reads after a failed write, while bd may still be committing.
    ///   - rereads: how many times to re-read after a failed write before deciding.
    public init(
        writer: any IssueWriting,
        settleDelay: Duration = .milliseconds(500),
        rereads: Int = 3,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.writer = writer
        self.settleDelay = settleDelay
        self.rereads = max(1, rereads)
        self.now = now
    }

    /// - Parameters:
    ///   - snapshot: the data the change was made against.
    ///   - base: the version of the issue the user started from, when that's older than `snapshot`
    ///     (for example an edit begun before an auto-refresh).
    @discardableResult
    public func run(_ proposed: IssueChange, seenIn snapshot: IssueSnapshot, base: Issue? = nil) async throws -> IssueID {
        let change = proposed.normalized()
        let errors = ChangeValidator.problems(for: change, in: snapshot).filter { $0.severity == .error }
        guard errors.isEmpty else { throw ChangeFailure.rejected(errors) }

        // One bd call per ancestor, so do this before the conflict read, keeping that read as
        // close to the write as possible.
        try await checkLiveParentChain(for: change)

        var before: Issue?
        if let id = change.issueID {
            let seen = base.flatMap { $0.id == id ? $0 : nil } ?? snapshot.issue(id)
            guard let seen else { throw ChangeFailure.issueDisappeared(id) }
            guard let current = try await writer.currentIssue(id) else { throw ChangeFailure.issueDisappeared(id) }
            let conflicts = ChangeGuard.conflicts(for: change, seen: seen, current: current)
            guard conflicts.isEmpty else { throw ChangeFailure.conflict(conflicts) }
            before = current
        }

        let started = now()
        let id: IssueID
        do {
            id = try await writer.apply(change)
        } catch {
            return try await resolveFailedWrite(change, before: before, started: started, error: error)
        }

        guard let after = try await writer.currentIssue(id) else { throw ChangeFailure.unverified(id, []) }
        let mismatches = ChangeGuard.mismatches(for: change, after: after)
        guard mismatches.isEmpty else { throw ChangeFailure.unverified(id, mismatches) }
        return id
    }

    /// bd can fail after committing (a timeout, or an error in a second step), so look at what's
    /// actually there before saying what happened.
    private func resolveFailedWrite(_ change: IssueChange, before: Issue?, started: Date, error: Error) async throws -> IssueID {
        let message = error.localizedDescription

        if case .create(let new) = change {
            for attempt in 0..<rereads {
                if attempt > 0 { try? await Task.sleep(for: settleDelay) }
                let found = (try? await writer.issuesCreated(titled: new.title, since: started.addingTimeInterval(-Self.clockSlack))) ?? []
                if found.isEmpty { continue }
                if found.count == 1, ChangeGuard.mismatches(for: change, after: found[0]).isEmpty {
                    return found[0].id
                }
                let ids = found.map(\.id.rawValue).joined(separator: ", ")
                throw ChangeFailure.uncertain(nil, "bd reported “\(message)”, but \(found.count == 1 ? "a bead" : "\(found.count) beads") titled “\(new.title)” now exist\(found.count == 1 ? "s" : "") (\(ids)) that don't all match what was asked for. Check before trying again.")
            }
            throw ChangeFailure.writeFailed(message)
        }

        guard let id = change.issueID, let before else { throw ChangeFailure.writeFailed(message) }
        var latest: Issue?
        for attempt in 0..<rereads {
            if attempt > 0 { try? await Task.sleep(for: settleDelay) }
            guard let after = try? await writer.currentIssue(id) else { continue }
            latest = after
            let others = ChangeGuard.untouchedDifferences(for: change, before: before, after: after)
            if others.isEmpty, ChangeGuard.mismatches(for: change, after: after).isEmpty {
                return id
            }
        }

        guard let after = latest else {
            throw ChangeFailure.uncertain(id, "bd reported “\(message)”, and \(id) couldn't be read back. Check it before trying again.")
        }
        let others = ChangeGuard.untouchedDifferences(for: change, before: before, after: after)
        if others.isEmpty, ChangeGuard.conflicts(for: change, seen: before, current: after).isEmpty {
            throw ChangeFailure.writeFailed(message)
        }
        let state = ChangeGuard.mismatches(for: change, after: after).map { "\($0.field) is “\($0.actual)” (wanted “\($0.expected)”)" }
            + others.map { "\($0.field) changed to “\($0.actual)” (was “\($0.expected)”)" }
        throw ChangeFailure.uncertain(
            id,
            "bd reported “\(message)”, and \(id) is no longer as it was: \(state.joined(separator: "; ")). Part of the change may have landed, or another session wrote at the same moment. Check it before trying again."
        )
    }

    /// bd doesn't prevent parent cycles, and the snapshot may be stale, so walk the new parent's
    /// ancestry as it is right now.
    private func checkLiveParentChain(for change: IssueChange) async throws {
        let child: IssueID?
        let parent: IssueID
        switch change {
        case .setParent(let id, _, let to?):
            child = id
            parent = to
        case .create(let new):
            guard let to = new.parent else { return }
            child = nil
            parent = to
        default:
            return
        }

        var visited: Set<IssueID> = []
        var next: IssueID? = parent
        while let id = next, visited.insert(id).inserted, visited.count <= Self.maxAncestry {
            if id == child {
                throw ChangeFailure.rejected([ChangeProblem(
                    code: .parentIsDescendant, severity: .error,
                    message: "\(parent) is now inside \(id), so this would create a loop."
                )])
            }
            guard let issue = try await writer.currentIssue(id) else {
                if id == parent {
                    throw ChangeFailure.rejected([ChangeProblem(
                        code: .unknownParent, severity: .error, message: "\(parent) no longer exists."
                    )])
                }
                return
            }
            next = issue.parentID
        }
    }
}
