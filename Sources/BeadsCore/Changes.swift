import Foundation

// MARK: Change model

/// Fields to change on an existing issue. `nil` leaves a field alone; labels are a pair of sets
/// because bd adds and removes them rather than replacing the lot, which keeps two people
/// labelling the same bead from clobbering each other.
public struct IssueEdit: Equatable, Sendable {
    public var title: String?
    public var description: String?
    public var notes: String?
    public var priority: Int?
    public var type: String?
    /// Empty string clears the assignee.
    public var assignee: String?
    public var addedLabels: Set<String>
    public var removedLabels: Set<String>

    public init(
        title: String? = nil,
        description: String? = nil,
        notes: String? = nil,
        priority: Int? = nil,
        type: String? = nil,
        assignee: String? = nil,
        addedLabels: Set<String> = [],
        removedLabels: Set<String> = []
    ) {
        self.title = title
        self.description = description
        self.notes = notes
        self.priority = priority
        self.type = type
        self.assignee = assignee
        self.addedLabels = addedLabels
        self.removedLabels = removedLabels
    }

    public var isEmpty: Bool {
        title == nil && description == nil && notes == nil && priority == nil
            && type == nil && assignee == nil && addedLabels.isEmpty && removedLabels.isEmpty
    }
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
    /// Whether one bead has to finish before another can start — bd's `blocks` dependency.
    case setBlocker(IssueID, blocker: IssueID, on: Bool)

    /// The existing issue this change targets; nil for a create.
    public var issueID: IssueID? {
        switch self {
        case .edit(let id, _), .setStatus(let id, _, _, _), .setParent(let id, _, _),
             .setMark(let id, _, _), .setBlocker(let id, _, _): id
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
            edit.type = edit.type.map(trimmed)
            edit.assignee = edit.assignee.map(trimmed)
            edit.addedLabels = normalizedLabels(edit.addedLabels)
            edit.removedLabels = normalizedLabels(edit.removedLabels)
            return .edit(id, edit)
        case .setStatus(let id, let from, let to, let reason):
            let reason = reason.map(trimmed).flatMap { $0.isEmpty ? nil : $0 }
            return .setStatus(id, from: from, to: trimmed(to), reason: reason)
        case .setParent, .setMark, .setBlocker:
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

/// Labels are trimmed, and blank ones are dropped rather than sent to bd as empty.
private func normalizedLabels(_ labels: Set<String>) -> Set<String> {
    Set(labels.map(trimmed).filter { !$0.isEmpty })
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
        case assigneeHasLineBreaks, contradictoryLabels, unusableLabel
        case blockerIsSelf, blockerLoops, blockerIsDone
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

/// True when `issue` already waits for `target`, however many beads deep.
private func waits(_ issue: Issue, on target: IssueID, in snapshot: IssueSnapshot, depth: Int = 0) -> Bool {
    guard depth < 100 else { return true }
    for blocker in snapshot.blockers(of: issue) {
        if blocker.id == target { return true }
        if waits(blocker, on: target, in: snapshot, depth: depth + 1) { return true }
    }
    return false
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
            if title.isEmpty { error(.emptyTitle, String(localized: "The title can't be empty.", bundle: .module)) }
            if title.count > maxTitleLength { error(.titleTooLong, String(localized: "Titles are limited to \(maxTitleLength) characters.", bundle: .module)) }
            let control = CharacterSet.controlCharacters.union(.newlines)
            if title.unicodeScalars.contains(where: control.contains) {
                error(.titleHasLineBreaks, String(localized: "Titles must be a single line, without tabs or line breaks.", bundle: .module))
            }
        }
        func checkPriority(_ priority: Int) {
            if !(0...4).contains(priority) { error(.invalidPriority, String(localized: "Priority must be between P0 and P4.", bundle: .module)) }
        }

        switch change.normalized() {
        case .edit(let id, let edit):
            guard let issue = snapshot.issue(id) else {
                error(.unknownIssue, Self.notInDatabase(id))
                break
            }
            if let title = edit.title { checkTitle(title) }
            if let priority = edit.priority { checkPriority(priority) }
            if let type = edit.type, !(coreTypes.contains(type) || snapshot.types.contains(type)) {
                error(.invalidType, String(localized: "“\(type)” isn't a type this database uses.", bundle: .module))
            }
            if let assignee = edit.assignee {
                let control = CharacterSet.controlCharacters.union(.newlines)
                if assignee.unicodeScalars.contains(where: control.contains) {
                    error(.assigneeHasLineBreaks, String(localized: "An assignee is a single line of text.", bundle: .module))
                }
            }
            for label in edit.addedLabels.union(edit.removedLabels) where label.contains(",") {
                error(.unusableLabel, String(localized: "bd splits label lists on commas, so “\(label)” can't be a label.", bundle: .module))
            }
            for label in edit.addedLabels.intersection(edit.removedLabels) {
                error(.contradictoryLabels, String(localized: "“\(label)” is being added and removed at the same time.", bundle: .module))
            }
            let existing = Set(issue.labels)
            let changesSomething = [
                edit.title.map { $0 != trimmed(issue.title) },
                edit.description.map { trimmed($0) != trimmed(issue.description) },
                edit.notes.map { trimmed($0) != trimmed(issue.notes) },
                edit.priority.map { $0 != issue.priority },
                edit.type.map { $0 != issue.type },
                edit.assignee.map { $0 != (issue.assignee ?? "") },
                edit.addedLabels.isEmpty ? nil : !edit.addedLabels.subtracting(existing).isEmpty,
                edit.removedLabels.isEmpty ? nil : !edit.removedLabels.intersection(existing).isEmpty,
            ].contains(true)
            if !changesSomething { error(.noChange, String(localized: "Nothing would change.", bundle: .module)) }
            if edit.description == "", !trimmed(issue.description).isEmpty {
                warning(.clearsDescription, String(localized: "This removes the whole description.", bundle: .module))
            }
            if edit.notes == "", !trimmed(issue.notes).isEmpty {
                warning(.clearsNotes, String(localized: "This removes all the notes.", bundle: .module))
            }

        case .setStatus(let id, _, let to, let reason):
            guard let issue = snapshot.issue(id) else {
                error(.unknownIssue, Self.notInDatabase(id))
                break
            }
            guard snapshot.catalog.knows(to) else {
                error(.unknownStatus, String(localized: "“\(to)” isn't a status this database knows.", bundle: .module))
                break
            }
            guard to != issue.status else {
                error(.noChange, String(localized: "\(id.rawValue) is already \(to).", bundle: .module, comment: "A bead already has the status being set; the second value is bd's status name"))
                break
            }
            if to == "closed" {
                if reason == nil {
                    error(.missingCloseReason, String(localized: "Say why it's being closed. The reason is stored with the bead, and lets the app confirm the close was yours.", bundle: .module))
                }
                if issue.status == "pinned" {
                    error(.closesPinned, String(localized: "bd won't close a pinned bead.", bundle: .module))
                }
            }
            if snapshot.catalog.category(of: to) == .done {
                let unfinished = snapshot.descendants(of: id).filter { !snapshot.isDone($0) }
                if !unfinished.isEmpty {
                    let count = String(localized: "\(unfinished.count) issues under \(id.rawValue) aren't finished.", bundle: .module, comment: "Plural: how many issues under the bead are unfinished")
                    if issue.type == "epic" {
                        error(.closesWithOpenChildren, String(localized: "\(count) bd won't close an epic until they are.", bundle: .module, comment: "The first value is the sentence saying how many issues are unfinished"))
                    } else {
                        warning(.closesWithOpenChildren, count)
                    }
                }
            }

        case .setParent(let id, _, let to):
            guard let issue = snapshot.issue(id) else {
                error(.unknownIssue, Self.notInDatabase(id))
                break
            }
            if to == issue.parentID {
                error(.noChange, to.map { String(localized: "\(id.rawValue) is already under \($0.rawValue).", bundle: .module) } ?? String(localized: "\(id.rawValue) has no parent already.", bundle: .module))
                break
            }
            guard let to else { break }
            if to == id {
                error(.parentIsSelf, String(localized: "An issue can't be its own parent.", bundle: .module))
                break
            }
            guard let parent = snapshot.issue(to) else {
                error(.unknownParent, Self.notInDatabase(to))
                break
            }
            if snapshot.isDescendant(parent, of: id) {
                error(.parentIsDescendant, String(localized: "\(to.rawValue) is inside \(id.rawValue), so this would create a loop.", bundle: .module))
                break
            }
            if snapshot.isDone(parent) { warning(.closedParent, Self.isClosed(to)) }

        case .setBlocker(let id, let blocker, let on):
            guard let issue = snapshot.issue(id) else {
                error(.unknownIssue, Self.notInDatabase(id))
                break
            }
            guard let blocking = snapshot.issue(blocker) else {
                error(.unknownIssue, Self.notInDatabase(blocker))
                break
            }
            guard id != blocker else {
                error(.blockerIsSelf, String(localized: "A bead can't wait for itself.", bundle: .module))
                break
            }
            let already = snapshot.blockers(of: issue).contains { $0.id == blocker }
            guard already != on else {
                error(.noChange, on
                    ? String(localized: "\(id.rawValue) already waits for \(blocker.rawValue).", bundle: .module)
                    : String(localized: "\(id.rawValue) doesn't wait for \(blocker.rawValue).", bundle: .module))
                break
            }
            if on {
                // bd checks for cycles itself, but refusing here costs nothing and explains why.
                if waits(blocking, on: id, in: snapshot) {
                    error(.blockerLoops, String(localized: "\(blocker.rawValue) already waits for \(id.rawValue), so this would leave both stuck.", bundle: .module))
                } else if snapshot.isDone(blocking) {
                    warning(.blockerIsDone, String(localized: "\(blocker.rawValue) is already finished, so this won't hold anything up.", bundle: .module))
                }
            }

        case .setMark(let id, let mark, let on):
            guard let issue = snapshot.issue(id) else {
                error(.unknownIssue, Self.notInDatabase(id))
                break
            }
            if issue.has(mark) == on {
                let message: String = switch (mark, on) {
                case (.pinned, true): String(localized: "\(id.rawValue) is already pinned.", bundle: .module)
                case (.pinned, false): String(localized: "\(id.rawValue) isn't pinned.", bundle: .module)
                case (.starred, true): String(localized: "\(id.rawValue) is already starred.", bundle: .module)
                case (.starred, false): String(localized: "\(id.rawValue) isn't starred.", bundle: .module)
                }
                error(.noChange, message)
            }

        case .create(let new):
            checkTitle(new.title)
            checkPriority(new.priority)
            if !(coreTypes.contains(new.type) || snapshot.types.contains(new.type)) {
                error(.invalidType, String(localized: "“\(new.type)” isn't a known issue type.", bundle: .module))
            }
            if let parentID = new.parent {
                if let parent = snapshot.issue(parentID) {
                    if snapshot.isDone(parent) { warning(.closedParent, Self.isClosed(parentID)) }
                } else {
                    error(.unknownParent, Self.notInDatabase(parentID))
                }
            }
        }
        return problems
    }

    private static func notInDatabase(_ id: IssueID) -> String {
        String(localized: "\(id.rawValue) isn't in this database.", bundle: .module)
    }

    private static func isClosed(_ id: IssueID) -> String {
        String(localized: "\(id.rawValue) is closed.", bundle: .module)
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
            if let type = edit.type { expect("type", type, after.type) }
            if let assignee = edit.assignee { expect("assignee", assignee, after.assignee ?? "") }
            let landed = Set(after.labels)
            for label in edit.addedLabels where !landed.contains(label) {
                expect(Word.label(label), Word.present, Word.absent)
            }
            for label in edit.removedLabels where landed.contains(label) {
                expect(Word.label(label), Word.absent, Word.present)
            }
        case .setStatus(_, let from, let to, let reason):
            expect("status", to, after.status)
            if to == "closed", let reason {
                // bd close on something already closed exits 0 and keeps the old reason.
                expect(Word.closeReason, reason, after.closeReason ?? Word.none)
            }
            if from == "closed", to != "closed", let closedAt = after.closedAt {
                expect(Word.closedAt, Word.none, closedAt.formatted(.iso8601))
            }
        case .setParent(_, _, let to):
            expect("parent", to?.rawValue ?? Word.none, after.parentID?.rawValue ?? Word.none)
        case .setMark(_, let mark, let on):
            expect(mark.label, on ? Word.present : Word.absent, after.has(mark) ? Word.present : Word.absent)
        case .setBlocker(_, let blocker, let on):
            let waits = after.dependencies.contains { $0.kind == .blocks && $0.dependsOnID == blocker }
            expect(Word.blockedBy(blocker), on ? Word.yes : Word.no, waits ? Word.yes : Word.no)
        case .create(let new):
            expect("title", new.title, trimmed(after.title))
            expect("type", new.type, after.type)
            expect("priority", "P\(new.priority)", "P\(after.priority)")
            expect("description", new.description, after.description)
            expect("parent", new.parent?.rawValue ?? Word.none, after.parentID?.rawValue ?? Word.none)
        }
        return result
    }

    /// The words a conflict report uses for what a field held, beside bd's own field names,
    /// which stay as bd spells them (title, status, parent…).
    enum Word {
        static var present: String { String(localized: "present", bundle: .module, comment: "A label's state in a conflict report") }
        static var absent: String { String(localized: "absent", bundle: .module, comment: "A label's state in a conflict report") }
        static var none: String { String(localized: "none", bundle: .module, comment: "An empty parent or close reason in a conflict report") }
        static var yes: String { String(localized: "yes", bundle: .module, comment: "Whether a bead waits for another, in a conflict report") }
        static var no: String { String(localized: "no", bundle: .module, comment: "Whether a bead waits for another, in a conflict report") }
        static var closeReason: String { String(localized: "close reason", bundle: .module, comment: "A field name in a conflict report") }
        static var closedAt: String { String(localized: "closed at", bundle: .module, comment: "A field name in a conflict report") }
        static func label(_ label: String) -> String { String(localized: "label \(label)", bundle: .module, comment: "A field name in a conflict report; the value is a bd label") }
        static func blockedBy(_ id: IssueID) -> String { String(localized: "blocked by \(id.rawValue)", bundle: .module, comment: "A field name in a conflict report; the value is a bead id") }
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
        // A mark or a blocker touches only its own edge, and two sessions changing different
        // edges of the same bead don't conflict in any way worth stopping for.
        case .setMark, .setBlocker, .create: return []
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
            case .parent: issue.parentID?.rawValue ?? Word.none
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
            let fields = conflicts.map { String(localized: "\($0.field) was “\($0.expected)”, now “\($0.actual)”", bundle: .module, comment: "One field of a bead that changed underneath an edit: bd's field name, the value seen, the value now") }.joined(separator: "; ")
            return String(localized: "Nothing was written: this bead changed since you started (\(fields)). Review the current version and try again.", bundle: .module)
        case .issueDisappeared(let id):
            return String(localized: "Nothing was written: \(id.rawValue) no longer exists.", bundle: .module)
        case .writeFailed(let message):
            return message
        case .unverified(let id, let mismatches):
            let fields = mismatches.map { String(localized: "\($0.field) is “\($0.actual)”, expected “\($0.expected)”", bundle: .module, comment: "One field that didn't read back as written: bd's field name, the value read, the value expected") }.joined(separator: "; ")
            return fields.isEmpty
                ? String(localized: "bd accepted the change, but reading \(id.rawValue) back doesn't match. Check it before retrying.", bundle: .module)
                : String(localized: "bd accepted the change, but reading \(id.rawValue) back doesn't match: \(fields). Check it before retrying.", bundle: .module)
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
                throw ChangeFailure.uncertain(nil, String(localized: "bd reported “\(message)”, but \(found.count) beads titled “\(new.title)” now exist (\(ids)) that don't all match what was asked for. Check before trying again.", bundle: .module, comment: "Plural on the number of beads found: bd's error, how many, the title, their ids"))
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
            throw ChangeFailure.uncertain(id, String(localized: "bd reported “\(message)”, and \(id.rawValue) couldn't be read back. Check it before trying again.", bundle: .module))
        }
        let others = ChangeGuard.untouchedDifferences(for: change, before: before, after: after)
        if others.isEmpty, ChangeGuard.conflicts(for: change, seen: before, current: after).isEmpty {
            throw ChangeFailure.writeFailed(message)
        }
        let state = ChangeGuard.mismatches(for: change, after: after).map { String(localized: "\($0.field) is “\($0.actual)” (wanted “\($0.expected)”)", bundle: .module, comment: "One field that isn't as the change asked: bd's field name, the value now, the value wanted") }
            + others.map { String(localized: "\($0.field) changed to “\($0.actual)” (was “\($0.expected)”)", bundle: .module, comment: "One field the change didn't touch but that moved anyway: bd's field name, the value now, the value before") }
        throw ChangeFailure.uncertain(
            id,
            String(localized: "bd reported “\(message)”, and \(id.rawValue) is no longer as it was: \(state.joined(separator: "; ")). Part of the change may have landed, or another session wrote at the same moment. Check it before trying again.", bundle: .module)
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
                    message: String(localized: "\(parent.rawValue) is now inside \(id.rawValue), so this would create a loop.", bundle: .module)
                )])
            }
            guard let issue = try await writer.currentIssue(id) else {
                if id == parent {
                    throw ChangeFailure.rejected([ChangeProblem(
                        code: .unknownParent, severity: .error, message: String(localized: "\(parent.rawValue) no longer exists.", bundle: .module)
                    )])
                }
                return
            }
            next = issue.parentID
        }
    }
}
