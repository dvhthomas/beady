/// bd groups every status (built-in or custom) into one of these lifecycle categories.
public enum StatusCategory: String, CaseIterable, Hashable, Sendable {
    case active
    case wip
    case frozen
    case done

    /// The status an issue gets when dropped into this category's board column.
    public var defaultStatus: String {
        switch self {
        case .active: "open"
        case .wip: "in_progress"
        case .frozen: "deferred"
        case .done: "closed"
        }
    }
}

public struct StatusCatalog: Equatable, Sendable {
    private let categories: [String: StatusCategory]

    public init(_ categories: [String: StatusCategory]) {
        self.categories = categories
    }

    public static let builtIn = StatusCatalog(builtInCategories)

    private static let builtInCategories: [String: StatusCategory] = [
        "open": .active,
        "in_progress": .wip,
        "blocked": .wip,
        "hooked": .wip,
        "deferred": .frozen,
        "pinned": .frozen,
        "closed": .done,
    ]

    /// Whether this is a built-in status or one the database defines.
    /// Every status this database uses, built-in and custom, in a stable order.
    public var names: [String] {
        categories.keys.sorted()
    }

    public func knows(_ status: String) -> Bool {
        categories[status] != nil || Self.builtInCategories[status] != nil
    }

    /// Unknown statuses count as active so they stay visible rather than vanishing as done.
    public func category(of status: String) -> StatusCategory {
        categories[status] ?? Self.builtInCategories[status] ?? .active
    }
}
