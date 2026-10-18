import BeadsCore
import Foundation

/// Whether Beady turns bd's change journal on when a workspace opens, and what it remembers
/// about having done so. The journal is on by default (plan 0003's amendment): the warnings and
/// the actor names are the point of Beady on a shared database. It stays the owner's workspace
/// setting, so there is a switch, and a workspace where they turned it off is left off.
public struct JournalPolicy: Sendable {
    /// The app setting: "Turn on bd's change journal in workspaces that don't have it".
    public var turnsOnAutomatically: Bool
    /// Someone turned this workspace's journal off after Beady turned it on. It's theirs to
    /// leave off; ⌘P is there for a change of mind.
    public var wasTurnedOffByHand: Bool
    /// Told whenever Beady has turned the journal on here, from the open or from ⌘P, so the
    /// app can remember the workspace.
    public var noteTurnedOn: @MainActor @Sendable () -> Void

    public init(
        turnsOnAutomatically: Bool,
        wasTurnedOffByHand: Bool = false,
        noteTurnedOn: @escaping @MainActor @Sendable () -> Void = {}
    ) {
        self.turnsOnAutomatically = turnsOnAutomatically
        self.wasTurnedOffByHand = wasTurnedOffByHand
        self.noteTurnedOn = noteTurnedOn
    }

    /// Nothing is written unless asked: tests, the offscreen snapshots, the setting off.
    public static let manual = JournalPolicy(turnsOnAutomatically: false)

    /// The one decision. Every reason not to stands alone: a bd older than 1.3 (or one that
    /// wouldn't say), a journal already on, a window that can't write, the setting off, or a
    /// workspace whose owner turned it off.
    public static func shouldTurnOn(
        journal: JournalStatus, canEdit: Bool, turnsOnAutomatically: Bool, wasTurnedOffByHand: Bool
    ) -> Bool {
        guard case .supported(let version, let settings) = journal,
              version >= BeadsVersion.eventsJournal, !settings.isEnabled else { return false }
        return canEdit && turnsOnAutomatically && !wasTurnedOffByHand
    }

    public func shouldTurnOn(journal: JournalStatus, canEdit: Bool) -> Bool {
        Self.shouldTurnOn(
            journal: journal, canEdit: canEdit,
            turnsOnAutomatically: turnsOnAutomatically, wasTurnedOffByHand: wasTurnedOffByHand
        )
    }
}
