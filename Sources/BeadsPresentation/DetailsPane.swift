import BeadsCore

/// Whether the details pane is on screen, and who put it there.
///
/// The pane opens two ways. Asked for — ⌘I, the toolbar button — it is `pinned`: docked beside
/// the beads, which make room for it, and staying through an empty selection. Opened by
/// selecting a bead while it was hidden, it is only `peeking`: it floats over the beads without
/// moving them, came with the bead and leaves with it, so Escape, a click away or its own close
/// button put the window back exactly as the user had arranged it.
public enum DetailsPane: Equatable, Sendable {
    case closed
    case peeking
    case pinned

    public var isOpen: Bool { self != .closed }

    /// True while the pane sits over the beads rather than beside them.
    public var floats: Bool { self == .peeking }

    /// The Details command: pin the pane open — which docks a peeking one, the way to keep what
    /// a click brought up — or hide a pinned one.
    public func toggled() -> DetailsPane {
        self == .pinned ? .closed : .pinned
    }

    /// Something asked for the pane by name (the pinned graph needs it): a hidden one is pinned
    /// open, an open one keeps the reason it had.
    public func shown() -> DetailsPane {
        isOpen ? self : .pinned
    }

    /// The pane once the selection has changed to `selection`.
    public func following(selection: IssueID?) -> DetailsPane {
        switch (self, selection) {
        case (.closed, .some): .peeking
        case (.peeking, .none): .closed
        default: self
        }
    }

    /// True when Escape or a click elsewhere in the window should let go of the selected bead,
    /// which closes the pane with it. A pinned pane is furniture: clicking around it changes
    /// nothing.
    public var letsGoOnClickAway: Bool { self == .peeking }
}
