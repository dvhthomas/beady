import BeadsCore

/// Every view has an icon, and it is never the List / Board / Tree glyph: the layout switcher in
/// the header owns those, and a sidebar row should say what the view answers. The built-ins ship
/// with theirs; a user view picks from a small set, with a default, when it is saved or later
/// from Change Icon…. The `symbol` in a `.beadyview` file is the SF Symbol name, so an imported
/// view that names a symbol outside the set still renders, and the picker shows it as current.
public enum ViewIcon {
    public static let builtIn: [IssueView.ID: String] = [
        .frontier: "play.circle",            // what can start now
        .inFlight: "circle.lefthalf.filled", // bd's own in-progress glyph
        .stuck: "hourglass",                 // waiting on something upstream; quiet, not an alarm
        .pipeline: "flowchart",              // work flowing through stages
        .recent: "clock",                    // what moved lately
        .landed: "checkmark.circle",         // done
        .deferred: "snowflake",              // bd's frozen category
        .everything: "tray.full",            // the whole database
        .starred: "star.fill",               // the star mark
    ]

    /// Fourteen is enough to tell views apart and few enough to pick from a grid. The first is
    /// the default.
    public static let userChoices: [String] = [
        "bookmark", "tag", "flag", "bolt", "target", "ladybug", "wrench.and.screwdriver",
        "person", "person.2", "shippingbox", "calendar", "folder", "lightbulb", "map",
    ]

    public static var defaultUserChoice: String { userChoices[0] }

    /// What the picker offers: the set, led by the current symbol when it comes from outside it.
    public static func choices(including current: String) -> [String] {
        current.isEmpty || userChoices.contains(current) ? userChoices : [current] + userChoices
    }
}
