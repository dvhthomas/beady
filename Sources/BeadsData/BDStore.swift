import BeadsCore
import Foundation

/// BeadsCore's `BeadsStore` port, implemented entirely through `BDGateway`. bd stays the authority
/// on its own storage (embedded or server Dolt, migrations), so nothing reads Dolt tables directly.
/// Only `ChangeRunner` should call `apply`; it wraps it in validation, conflict checks and verification.
public struct BDStore: BeadsStore {
    public let gateway: BDGateway

    public init(gateway: BDGateway) {
        self.gateway = gateway
    }

    public func loadSnapshot() async throws -> IssueSnapshot {
        // Sequential on purpose: embedded Dolt serialises access through a file lock.
        let decoded = try decodeIssueList(try await gateway.run(.list))
        let catalog = (try? await gateway.run(.statuses)).flatMap { try? BDJSON.decodeStatusCatalog($0) }
        return IssueSnapshot(
            issues: decoded.issues,
            catalog: catalog ?? .builtIn,
            unreadableRecordCount: decoded.unreadableCount
        )
    }

    public func currentIssue(_ id: IssueID) async throws -> Issue? {
        let result = try await gateway.result(of: .show(id))
        guard result.exitCode == 0 else {
            if result.stderr.contains("no issue found") { return nil }
            throw BDGateway.failure(result)
        }
        return try decodeIssueList(result.stdout).issues.first { $0.id == id }
    }

    public func issuesCreated(titled title: String, since: Date) async throws -> [Issue] {
        try decodeIssueList(try await gateway.run(.listTitled(title))).issues
            .filter { $0.title == title && $0.createdAt >= since }
            .sorted { $0.id < $1.id }
    }

    public func apply(_ change: IssueChange) async throws -> IssueID {
        if case .create(let new) = change {
            // bd's own preflight catches things like a parent that doesn't exist.
            _ = try await gateway.run(.create(new, dryRun: true))
            let output = try await gateway.run(.create(new, dryRun: false))
            guard let id = BDJSON.createdID(output) else {
                throw BeadsDataError.unreadableOutput(detail: "bd create didn't report the new issue's id")
            }
            return id
        }
        for command in Self.commands(for: change) {
            _ = try await gateway.run(command)
        }
        return change.issueID!
    }

    public func commandPreview(for change: IssueChange) -> [String] {
        Self.commands(for: change).map(gateway.preview)
    }

    public func changeToken() async -> String {
        gateway.changeToken()
    }

    public func recentActivity(since: Date) async throws -> ActivityLog {
        try await gateway.recentActivity(since: since)
    }

    public func versions(of id: IssueID, limit: Int) async throws -> [IssueVersion] {
        try BDJSON.decodeHistory(try await gateway.run(.history(id, limit: limit)))
    }

    public func backupStatus() async throws -> BackupStatus {
        try BDJSON.decodeBackupStatus(try await gateway.run(.backupStatus))
    }

    public func configureBackup(folder: String) async throws {
        _ = try await gateway.run(.backupInit(folder))
        _ = try await gateway.run(.backupSync)
    }

    public func syncBackup() async throws {
        _ = try await gateway.run(.backupSync)
    }

    /// The bd commands a change runs, in order.
    static func commands(for change: IssueChange) -> [BDCommand] {
        switch change {
        case .edit(let id, let edit):
            return [.updateFields(id, edit)]
        case .setStatus(let id, let from, let to, let reason):
            if to == "closed" { return [.close(id, reason: reason)] }
            if from == "closed" {
                return to == "open" ? [.reopen(id, reason: reason)] : [.reopen(id, reason: reason), .setStatus(id, to)]
            }
            return [.setStatus(id, to)]
        case .setParent(let id, _, let to):
            return [.setParent(id, to)]
        case .setMark(let id, let mark, let on):
            return [on ? .addLabel(id, mark.label) : .removeLabel(id, mark.label)]
        case .setBlocker(let id, let blocker, let on):
            return [on ? .addBlocker(id, blocker: blocker) : .removeBlocker(id, blocker: blocker)]
        case .create(let new):
            return [.create(new, dryRun: true), .create(new, dryRun: false)]
        }
    }

    private func decodeIssueList(_ data: Data) throws -> BDJSON.DecodedIssues {
        do {
            return try BDJSON.decodeIssueList(data)
        } catch let failure as BDJSON.DecodingFailure {
            throw BeadsDataError.unreadableOutput(detail: failure.detail)
        }
    }
}
