import Foundation

/// How a view lays its issues out.
public enum ViewLayout: String, CaseIterable, Identifiable, Codable, Sendable {
    case list, board, tree

    public var id: String { rawValue }
}

/// How a view shows what its filter lets through.
public struct ViewPresentation: Hashable, Codable, Sendable {
    public var layout: ViewLayout
    public var grouping: IssueGrouping
    public var ordering: IssueSort
    /// The list columns to show, by id; nil for the layout's own defaults.
    public var columns: [String]?
    /// Board only: fold a sub-task into its parent's card when the parent is also on the board.
    /// Nil means off — every bead its own card — and, being optional, keeps old files decoding
    /// and this field out of files that never set it.
    public var nestsSubtasks: Bool?

    public init(layout: ViewLayout = .list, grouping: IssueGrouping = .none, ordering: IssueSort = .priority, columns: [String]? = nil, nestsSubtasks: Bool? = nil) {
        self.layout = layout
        self.grouping = grouping
        self.ordering = ordering
        self.columns = columns
        self.nestsSubtasks = nestsSubtasks
    }
}

/// A view is a saved filter with a saved presentation: that is the whole system. Everything in
/// the sidebar is one of these over all beads — the built-ins shipped with Beady and, later, the
/// user's own. One JSON document per view, with a `beadyView` version header, is the file format.
public struct IssueView: Identifiable, Hashable, Codable, Sendable {
    public struct ID: RawRepresentable, Hashable, Codable, Sendable, ExpressibleByStringLiteral, CustomStringConvertible {
        public let rawValue: String

        public init(rawValue: String) { self.rawValue = rawValue }
        public init(_ rawValue: String) { self.rawValue = rawValue }
        public init(stringLiteral value: String) { self.rawValue = value }

        public init(from decoder: Decoder) throws {
            rawValue = try decoder.singleValueContainer().decode(String.self)
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode(rawValue)
        }

        public var description: String { rawValue }
    }

    /// The `beadyView` header this Beady writes and reads. A newer document is refused whole
    /// rather than half-read.
    public static let formatVersion = 1

    public var id: ID
    public var name: String
    /// An SF Symbol name, for the sidebar and the Go menu.
    public var symbol: String
    public var filter: ViewFilter
    public var presentation: ViewPresentation
    /// Shipped with Beady: the filter is the view's definition, so it can't be saved over.
    public var isBuiltIn: Bool

    public init(id: ID, name: String, symbol: String, filter: ViewFilter = ViewFilter(), presentation: ViewPresentation = ViewPresentation(), isBuiltIn: Bool = false) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.filter = filter
        self.presentation = presentation
        self.isBuiltIn = isBuiltIn
    }

    private enum CodingKeys: String, CodingKey {
        case version = "beadyView"
        case id, name, symbol, filter, presentation, isBuiltIn
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = try container.decode(Int.self, forKey: .version)
        guard version == Self.formatVersion else {
            throw DecodingError.dataCorruptedError(
                forKey: .version, in: container,
                debugDescription: "beadyView \(version) is newer than this Beady reads (\(Self.formatVersion))"
            )
        }
        id = try container.decode(ID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        symbol = try container.decode(String.self, forKey: .symbol)
        filter = try container.decode(ViewFilter.self, forKey: .filter)
        presentation = try container.decode(ViewPresentation.self, forKey: .presentation)
        isBuiltIn = try container.decodeIfPresent(Bool.self, forKey: .isBuiltIn) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.formatVersion, forKey: .version)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(symbol, forKey: .symbol)
        try container.encode(filter, forKey: .filter)
        try container.encode(presentation, forKey: .presentation)
        // Only user views travel as files, so the flag is written only when it says something.
        if isBuiltIn { try container.encode(true, forKey: .isBuiltIn) }
    }
}
