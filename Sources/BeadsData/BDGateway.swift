import BeadsCore
import CoreServices
import Foundation

// The one way the app reaches a beads database. Every bd invocation is a `BDCommand` run by
// `BDGateway`, and every direct read of bd's files (the change token, workspace detection) lives
// here too. An architecture test holds other files to that.

public struct BeadsWorkspace: Hashable, Sendable {
    public let projectDirectory: URL

    public init(projectDirectory: URL) {
        self.projectDirectory = projectDirectory.standardizedFileURL
    }

    public var beadsDirectory: URL { projectDirectory.appendingPathComponent(".beads", isDirectory: true) }
    public var displayName: String { projectDirectory.lastPathComponent }

    /// Accepts either a project folder or the `.beads` folder inside it. The `.beads` folder must
    /// be one bd has initialised: bd would silently use a parent folder's database for an empty one.
    public static func resolve(_ url: URL) throws -> BeadsWorkspace {
        let standardized = url.standardizedFileURL
        let project = standardized.lastPathComponent == ".beads"
            ? standardized.deletingLastPathComponent()
            : standardized
        let beads = project.appendingPathComponent(".beads")
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: beads.path, isDirectory: &isDirectory), isDirectory.boolValue,
              isInitialised(beads) else {
            throw BeadsDataError.notAWorkspace(path: url.path)
        }
        return BeadsWorkspace(projectDirectory: project)
    }

    private static func isInitialised(_ beads: URL) -> Bool {
        let contents = (try? FileManager.default.contentsOfDirectory(atPath: beads.path)) ?? []
        return contents.contains { name in
            ["metadata.json", "config.yaml", "embeddeddolt", "dolt"].contains(name) || name.hasSuffix(".db")
        }
    }
}

/// Every bd invocation the app makes. Reads always carry `--readonly`; writes pass values as
/// `--flag=value` and put the issue id after `--`, so text that looks like a flag stays text.
public enum BDCommand: Equatable, Sendable {
    case list
    case listTitled(String)
    case statuses
    case show(IssueID)
    case ready
    case blocked
    case history(IssueID, limit: Int)
    case updateFields(IssueID, title: String?, description: String?, notes: String?, priority: Int?)
    case setStatus(IssueID, String)
    case setParent(IssueID, IssueID?)
    case addLabel(IssueID, String)
    case removeLabel(IssueID, String)
    case close(IssueID, reason: String?)
    case reopen(IssueID, reason: String?)
    case create(NewIssue, dryRun: Bool)

    public var isReadOnly: Bool {
        switch self {
        case .list, .listTitled, .statuses, .show, .ready, .blocked, .history: true
        case .updateFields, .setStatus, .setParent, .addLabel, .removeLabel, .close, .reopen, .create: false
        }
    }

    /// Arguments after `bd -C <project>`.
    public var arguments: [String] {
        switch self {
        case .list:
            return Self.readOnly(["list", "--json", "--all", "--limit", "0", "--flat"])
        case .listTitled(let title):
            return Self.readOnly(["list", "--json", "--all", "--limit", "0", "--flat", "--title-contains=\(title)"])
        case .statuses:
            return Self.readOnly(["statuses", "--json"])
        case .show(let id):
            return Self.readOnly(["show", "--id=\(id.rawValue)", "--json"])
        case .ready:
            return Self.readOnly(["ready", "--json", "--limit", "0"])
        case .blocked:
            return Self.readOnly(["blocked", "--json"])
        case .history(let id, let limit):
            return Self.readOnly(["history", id.rawValue, "--limit", String(limit), "--json"])
        case .updateFields(let id, let title, let description, let notes, let priority):
            var flags: [String] = []
            if let title { flags.append("--title=\(title)") }
            if let description { flags.append("--description=\(description)") }
            if let notes { flags.append("--notes=\(notes)") }
            if let priority { flags.append("--priority=\(priority)") }
            return ["update"] + flags + ["--json", "--", id.rawValue]
        case .setStatus(let id, let status):
            return ["update", "--status=\(status)", "--json", "--", id.rawValue]
        case .setParent(let id, let parent):
            return ["update", "--parent=\(parent?.rawValue ?? "")", "--json", "--", id.rawValue]
        case .addLabel(let id, let label):
            return ["update", "--add-label=\(label)", "--json", "--", id.rawValue]
        case .removeLabel(let id, let label):
            return ["update", "--remove-label=\(label)", "--json", "--", id.rawValue]
        case .close(let id, let reason):
            return ["close"] + Self.reasonFlag(reason) + ["--json", "--", id.rawValue]
        case .reopen(let id, let reason):
            return ["reopen"] + Self.reasonFlag(reason) + ["--json", "--", id.rawValue]
        case .create(let new, let dryRun):
            var arguments = ["create", "--title=\(new.title)", "--type=\(new.type)", "--priority=\(new.priority)"]
            if let parent = new.parent { arguments.append("--parent=\(parent.rawValue)") }
            if !new.description.isEmpty { arguments.append("--description=\(new.description)") }
            return arguments + (dryRun ? ["--dry-run", "--json"] : ["--json"])
        }
    }

    private static func readOnly(_ arguments: [String]) -> [String] {
        ["--readonly"] + arguments
    }

    private static func reasonFlag(_ reason: String?) -> [String] {
        guard let reason, !reason.isEmpty else { return [] }
        return ["--reason=\(reason)"]
    }
}

public struct BDGateway: Sendable {
    public let workspace: BeadsWorkspace
    private let executable: URL
    private let runner: any CommandRunning
    private let timeout: TimeInterval

    public init(
        workspace: BeadsWorkspace,
        executable: URL,
        runner: any CommandRunning = ProcessCommandRunner(),
        timeout: TimeInterval = 60
    ) {
        self.workspace = workspace
        self.executable = executable
        self.runner = runner
        self.timeout = timeout
    }

    /// Resolves a folder to a workspace and finds the bd executable.
    public static func open(_ url: URL, locator: BDExecutableLocator = BDExecutableLocator()) throws -> BDGateway {
        BDGateway(workspace: try BeadsWorkspace.resolve(url), executable: try locator.locate())
    }

    /// Runs a command and returns its output, throwing bd's own error message when it fails.
    public func run(_ command: BDCommand) async throws -> Data {
        let result = try await result(of: command)
        guard result.exitCode == 0 else { throw Self.failure(result) }
        return result.stdout
    }

    /// Runs a command and returns the raw result, for callers that interpret failures themselves.
    public func result(of command: BDCommand) async throws -> CommandResult {
        try await runner.run(executable, arguments: ["-C", workspace.projectDirectory.path] + command.arguments, timeout: timeout)
    }

    /// The exact command line, quoted the way a shell would need.
    public func preview(_ command: BDCommand) -> String {
        (["bd", "-C", workspace.projectDirectory.path] + command.arguments).map(Self.shellQuoted).joined(separator: " ")
    }

    /// A cheap summary of the files bd changes when it writes.
    ///
    /// Even `bd --readonly` bumps the modification time of Dolt's manifest and journal, so Dolt
    /// storage contributes file sizes only (its journal is append-only on writes); lock files and
    /// derived indexes are ignored. Otherwise every reload would look like a change.
    public func changeToken() -> String {
        let fileManager = FileManager.default
        let beads = workspace.beadsDirectory
        var parts = ["last-touched", "issues.jsonl"].map {
            Self.describe(beads.appendingPathComponent($0), includeModificationDate: true)
        }
        for store in ["embeddeddolt", "dolt"] {
            let storeRoot = beads.appendingPathComponent(store)
            let databases = (try? fileManager.contentsOfDirectory(atPath: storeRoot.path)) ?? []
            for database in databases.sorted() {
                let noms = storeRoot.appendingPathComponent(database).appendingPathComponent(".dolt/noms")
                let files = (try? fileManager.contentsOfDirectory(atPath: noms.path)) ?? []
                for file in files.sorted() where file != "LOCK" && !file.hasSuffix(".idx") {
                    parts.append(Self.describe(noms.appendingPathComponent(file), includeModificationDate: false))
                }
            }
        }
        return parts.joined(separator: "|")
    }

    /// bd appends every field change to `.beads/interactions.jsonl` (actor, time, field). Reading
    /// the tail of that file is far cheaper than asking bd, and touches nothing.
    public func recentActivity(since: Date) async throws -> ActivityLog {
        let url = workspace.beadsDirectory.appendingPathComponent("interactions.jsonl")
        guard let handle = try? FileHandle(forReadingFrom: url) else { return .empty }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        try? handle.seek(toOffset: size > Self.activityTailBytes ? size - Self.activityTailBytes : 0)
        let data = (try? handle.readToEnd()) ?? Data()

        // The whole tail is parsed rather than stopping at the first old record: the log is
        // append-only in practice, but a clock skew or an out-of-order write would then silently
        // hide another session's work, which is the one thing this is here to report. The
        // byte cap above is what bounds the cost.
        var entries: [ActivityEntry] = []
        for line in String(decoding: data, as: UTF8.self).split(separator: "\n").reversed() {
            guard let record = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  let date = BDJSON.parseDate(record["created_at"] as? String), date >= since,
                  let id = record["issue_id"] as? String else { continue }
            let extra = record["extra"] as? [String: Any]
            entries.append(ActivityEntry(
                issueID: IssueID(id),
                actor: (record["actor"] as? String) ?? "another session",
                date: date,
                field: extra?["field"] as? String
            ))
        }
        return ActivityLog(entries: entries.sorted { $0.date > $1.date })
    }

    /// Reports writes as they happen, by watching bd's folder with FSEvents. Purely passive: it
    /// opens nothing and writes nothing, so it can't disturb the agents using the same database.
    /// bd rewrites `issues.jsonl` (export.auto), appends to `interactions.jsonl` and grows Dolt's
    /// journal on every change, so every write shows up here.
    public func watchChanges(_ onChange: @escaping @Sendable () -> Void) -> BDChangeWatcher {
        BDChangeWatcher(path: workspace.beadsDirectory.path, onChange: onChange)
    }

    /// How much of the interaction log to read; enough for a busy hour, cheap to parse.
    private static let activityTailBytes: UInt64 = 256 * 1024

    static func failure(_ result: CommandResult) -> BeadsDataError {
        .commandFailed(exitCode: result.exitCode, message: result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    static func shellQuoted(_ argument: String) -> String {
        let safe = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_@%+=:,./-")
        if !argument.isEmpty, argument.allSatisfy(safe.contains) { return argument }
        return "'" + argument.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func describe(_ url: URL, includeModificationDate: Bool) -> String {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else {
            return "\(url.lastPathComponent):missing"
        }
        let size = (attributes[.size] as? NSNumber)?.int64Value ?? -1
        guard includeModificationDate else { return "\(url.lastPathComponent):\(size)" }
        let modified = (attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        return "\(url.lastPathComponent):\(size):\(modified)"
    }
}


/// An FSEvents subscription to bd's folder. Hold on to it; releasing or stopping it ends the watch.
///
/// Events are coalesced: one bd write touches several files (the Dolt journal, `issues.jsonl`,
/// the interaction log) and an agent often writes a batch, so the handler runs once the folder
/// has been quiet for `settle` seconds rather than once per file.
public final class BDChangeWatcher: @unchecked Sendable {
    /// The callback target, retained across the C boundary so a firing event can never reach a
    /// half-deallocated watcher.
    private final class Sink {
        let onChange: @Sendable () -> Void
        init(onChange: @escaping @Sendable () -> Void) { self.onChange = onChange }
    }

    private let queue = DispatchQueue(label: "me.bitsby.beady.change-watch")
    private let settle: TimeInterval
    private let sink: Unmanaged<Sink>
    private var stream: FSEventStreamRef?
    private var pending: DispatchWorkItem?

    init(path: String, settle: TimeInterval = 0.4, onChange: @escaping @Sendable () -> Void) {
        self.settle = settle
        let watcherBox = Sink(onChange: onChange)
        sink = Unmanaged.passRetained(watcherBox)

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            Unmanaged<BDChangeWatcher>.fromOpaque(info).takeUnretainedValue().schedule()
        }
        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            [path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            settle / 2,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer)
        ) else { return }
        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
    }

    /// Runs the handler once the writes stop coming. Called on `queue`, which is where the
    /// stream delivers events, so `pending` needs no further locking.
    private func schedule() {
        pending?.cancel()
        let sink = sink
        let work = DispatchWorkItem { sink.takeUnretainedValue().onChange() }
        pending = work
        queue.asyncAfter(deadline: .now() + settle, execute: work)
    }

    public func stop() {
        pending?.cancel()
        pending = nil
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
        // On the delivery queue, so any event already in flight has finished with the sink.
        let sink = sink
        queue.async { sink.release() }
    }

    deinit { stop() }
}
