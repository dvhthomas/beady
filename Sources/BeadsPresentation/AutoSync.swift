import BeadsCore
import Foundation

/// How often a workspace syncs by itself (plan 0007). bd's guide runs `bd sync` from a timer and
/// calls a minute comfortable; five minutes is bd's own spacing for automatic pushes.
public enum SyncCadence: Int, CaseIterable, Identifiable, Sendable {
    case manual = 0
    case everyMinute = 60
    case everyFiveMinutes = 300
    case everyFifteenMinutes = 900

    public var id: Int { rawValue }

    /// The saved number of seconds; anything unrecognised is the safe choice.
    public init(seconds: Int) {
        self = SyncCadence(rawValue: seconds) ?? .manual
    }

    /// Nil when nothing is automatic.
    public var interval: TimeInterval? {
        self == .manual ? nil : TimeInterval(rawValue)
    }

    public var title: String {
        switch self {
        case .manual: String(localized: "When I ask", bundle: .module, comment: "How often to sync: only on Sync Now")
        case .everyMinute: String(localized: "Every minute", bundle: .module, comment: "How often to sync")
        case .everyFiveMinutes: String(localized: "Every 5 minutes", bundle: .module, comment: "How often to sync")
        case .everyFifteenMinutes: String(localized: "Every 15 minutes", bundle: .module, comment: "How often to sync")
        }
    }
}

/// The sync timer's rules, as pure functions of the time, the sharing state and what the last
/// sync said. They are bd's table for a timer that runs `bd sync`: 0 and 3 need nobody, 1 is
/// shown when it repeats, 2 and 4 wait for a person.
public struct AutoSync: Equatable, Sendable {
    /// Why no tick will run until a person has done something.
    public enum Hold: Equatable, Sendable {
        case conflict
        case unrelated
        case stuck
        /// The person stopped a sync.
        case stopped
    }

    /// Whether an outcome is worth showing in the popover.
    public enum Report: Equatable, Sendable {
        case quiet
        case show
    }

    /// How many automatic failures in a row before one is shown ("alert if it repeats").
    public static let failuresBeforeShowing = 3

    public private(set) var cadence: SyncCadence
    public private(set) var hold: Hold?
    public private(set) var lastAttempt: Date?
    public private(set) var failuresInARow = 0

    public init(cadence: SyncCadence = .manual) {
        self.cadence = cadence
    }

    /// Choosing again is a person's word: it lifts a pause they caused by stopping.
    public mutating func choose(_ cadence: SyncCadence) {
        self.cadence = cadence
        failuresInARow = 0
        if hold == .stopped { hold = nil }
    }

    /// True when the timer should run one `bd sync` now.
    /// - Parameters:
    ///   - isBusy: a sync, a share, a settlement or a write is running.
    public func isDue(at now: Date, state: SharingState?, isBusy: Bool, canWrite: Bool) -> Bool {
        guard let interval = cadence.interval, hold == nil, canWrite, !isBusy else { return false }
        switch state {
        case .inSync, .pending, .unknown, .unreachable:
            break
        case .notShared, .keptLocal, .neverPublished, .conflict, .unrelated, nil:
            // Nothing to sync with, or a first publish or a decision that is a person's to make.
            return false
        }
        guard let lastAttempt else { return true }
        return now.timeIntervalSince(lastAttempt) >= interval
    }

    /// Takes in what a sync said. Returns whether to show it.
    @discardableResult
    public mutating func record(_ outcome: SyncOutcome, at date: Date, automatic: Bool) -> Report {
        lastAttempt = date
        switch outcome {
        case .synced:
            failuresInARow = 0
            if !automatic { hold = nil }
            return .quiet
        case .noRemote, .localOnly:
            return automatic ? .quiet : .show
        case .busy:
            // Exit 3: transient, nothing pushed, the next tick retries.
            return automatic ? .quiet : .show
        case .failed:
            guard automatic else { return .show }
            failuresInARow += 1
            return failuresInARow >= Self.failuresBeforeShowing ? .show : .quiet
        case .conflict:
            hold = .conflict
            return .show
        case .unrelated:
            hold = .unrelated
            return .show
        case .stuck:
            hold = .stuck
            return .show
        case .stopped:
            hold = .stopped
            return .show
        }
    }

    /// The line under the choice in the popover.
    public func caption(remote: DoltRemote?) -> String {
        guard cadence != .manual else {
            return String(localized: "Beady syncs when you press Sync Now.", bundle: .module, comment: "Under the sync cadence choice, when it is manual")
        }
        switch hold {
        case .stopped:
            return String(localized: "Paused, because you stopped a sync. Sync Now starts it again.", bundle: .module, comment: "Under the sync cadence choice")
        case .conflict, .unrelated, .stuck:
            return String(localized: "Paused until this is settled.", bundle: .module, comment: "Under the sync cadence choice, when a conflict or a stuck sync holds the timer")
        case nil:
            let runs = String(localized: "Syncs by itself while this workspace is open.", bundle: .module, comment: "Under the sync cadence choice")
            guard remote?.isGitHosted == true else { return runs }
            let caution = String(localized: "bd advises care when several writers push to a git-hosted remote; a lost race is retried.", bundle: .module, comment: "Under the sync cadence choice, for a git-hosted remote")
            return "\(runs) \(caution)"
        }
    }
}
