import Foundation

/// A mark a person puts on a bead, carried by a bd label so every bd client sees it — nothing
/// about a pin or a star lives in this app's preferences.
///
/// Note that bd also has a built-in `pinned` *status* (category frozen, "stays open
/// indefinitely"). This is a label, separate from that, and the names live here so changing one
/// is a single edit.
public enum IssueMark: String, CaseIterable, Sendable {
    /// Floats the bead to the top of every list, tree and board column it appears in.
    case pinned
    /// Collects the bead into the Starred view.
    case starred

    /// The bd label that carries it.
    public var label: String { rawValue }

    public var title: String {
        switch self {
        case .pinned: "Pinned"
        case .starred: "Starred"
        }
    }
}

public extension Issue {
    func has(_ mark: IssueMark) -> Bool {
        labels.contains(mark.label)
    }
}
