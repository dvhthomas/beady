import BeadsCore
import Foundation

/// A workspace Beady has opened before, as the switcher at the top of the sidebar lists it:
/// the folder's name, its path (two checkouts of one project differ only there), and the issue
/// prefix bd uses in it, once Beady has seen its beads.
public struct RecentWorkspace: Equatable, Identifiable, Sendable {
    public let path: String
    public let prefix: String?

    public init(path: String, prefix: String? = nil) {
        self.path = path
        self.prefix = prefix
    }

    public var id: String { path }
    public var name: String { URL(fileURLWithPath: path).lastPathComponent }
}

public enum WorkspaceSwitching {
    /// Recents as the switcher and the palette list them: the order of File › Open Recent, with
    /// the prefix Beady remembers for each.
    public static func recents(paths: [String], prefixes: [String: String]) -> [RecentWorkspace] {
        paths.map { RecentWorkspace(path: $0, prefix: prefixes[$0]) }
    }

    /// Where ⌃⌘O goes: the recent after the current one, round again at the end. Nil when there
    /// is nothing else to go to.
    public static func next(after current: String?, in paths: [String]) -> String? {
        let others = paths.filter { $0 != current }
        guard !others.isEmpty else { return nil }
        guard let current, let index = paths.firstIndex(of: current) else { return paths.first }
        return paths[(index + 1) % paths.count]
    }

    /// The issue prefix bd uses in a database, read off its ids: `bdv-jlx.10` and `bdv-2ka` share
    /// `bdv`. The longest prefix every id shares, cut at a dash; failing that, the first segment
    /// most ids start with. Nil for an empty database.
    public static func prefix(of ids: [IssueID]) -> String? {
        let raw = ids.map(\.rawValue).filter { !$0.isEmpty }
        guard let first = raw.first else { return nil }
        var common = first
        for id in raw.dropFirst() {
            common = String(zip(common, id).prefix { $0 == $1 }.map(\.0))
            if common.isEmpty { break }
        }
        if let dash = common.lastIndex(of: "-"), dash > common.startIndex {
            return String(common[..<dash])
        }
        let segments = raw.compactMap { $0.split(separator: "-", maxSplits: 1).first.map(String.init) }
        let counts = Dictionary(segments.map { ($0, 1) }, uniquingKeysWith: +)
        return counts.max { ($0.value, $1.key) < ($1.value, $0.key) }?.key
    }
}
