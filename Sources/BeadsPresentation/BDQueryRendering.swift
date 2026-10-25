import BeadsCore
import Foundation

/// A view, as the `bd query` line that comes closest to it. Copy as bd Command puts this on the
/// pasteboard, in the same spirit as pinned being a real bd label: what Beady shows should be
/// sayable in bd's own words wherever bd has them.
public struct BDQuery: Equatable, Sendable {
    /// The `bd query` expression; empty when the view has no rule bd can express.
    public let expression: String
    /// The `--sort` field.
    public let sort: String
    /// Whether `--all` is needed: bd query leaves closed beads out unless asked.
    public let includesClosed: Bool
    /// What the view does that the query can't, one sentence each, for a trailing comment.
    public let notes: [String]

    public init(expression: String, sort: String, includesClosed: Bool, notes: [String]) {
        self.expression = expression
        self.sort = sort
        self.includesClosed = includesClosed
        self.notes = notes
    }

    /// The line to paste into a terminal: `bd query "…" --sort priority --all  # …`.
    public var commandLine: String {
        var parts = ["bd query"]
        if !expression.isEmpty { parts.append("\"\(expression.replacingOccurrences(of: "\"", with: "\\\""))\"") }
        parts.append("--sort \(sort)")
        if includesClosed { parts.append("--all") }
        let command = parts.joined(separator: " ")
        return notes.isEmpty ? command : "\(command)  # \(notes.joined(separator: " "))"
    }
}

public enum BDQueryRendering {
    /// The query for a view as saved: its rules, its search words and its ordering.
    public static func query(for view: IssueView, catalog: StatusCatalog = .builtIn) -> BDQuery {
        query(filter: view.filter, ordering: view.presentation.ordering, catalog: catalog)
    }

    public static func query(filter: ViewFilter, ordering: IssueSort, catalog: StatusCatalog = .builtIn) -> BDQuery {
        var terms: [String] = []
        var notes: [String] = []
        for rule in filter.rules where !rule.values.isEmpty {
            switch render(rule, catalog: catalog) {
            case .term(let term): terms.append(term)
            case .note(let note): notes.append(note)
            case .nothing: break
            }
        }
        let words = filter.searchText.split(whereSeparator: \.isWhitespace).map(String.init)
        terms += words.map { "title=\(quoted($0))" }
        if !words.isEmpty {
            notes.append("Beady's search also reads descriptions, notes, labels and close reasons; bd's title= reads titles.")
        }
        return BDQuery(
            expression: terms.joined(separator: " AND "),
            sort: sortField(ordering),
            includesClosed: !excludesDone(filter, catalog: catalog),
            notes: notes
        )
    }

    private enum Rendered {
        case term(String)
        case note(String)
        case nothing
    }

    private static func render(_ rule: FilterRule, catalog: StatusCatalog) -> Rendered {
        let values = rule.values.sorted()
        switch rule.field {
        case .lifecycle:
            // A category is a set of statuses, which is what bd stores.
            let statuses = values.compactMap(StatusCategory.init(rawValue:)).flatMap { category in
                catalog.names.filter { catalog.category(of: $0) == category }
            }.sorted()
            guard !statuses.isEmpty else { return .nothing }
            return .term(anyOf("status", statuses, negated: rule.op == .isNoneOf))
        case .status:
            return .term(anyOf("status", values, negated: rule.op == .isNoneOf))
        case .type:
            return .term(anyOf("type", values, negated: rule.op == .isNoneOf))
        case .assignee:
            return .term(anyOf("assignee", values.map { $0 == FilterRule.unassigned ? "none" : $0 }, negated: rule.op == .isNoneOf))
        case .priority:
            return .term(priorities(values, negated: rule.op == .isNoneOf))
        case .labels:
            let labels = values.map { "label=\(quoted($0))" }
            switch rule.op {
            case .includesAny: return .term(group(labels.joined(separator: " OR "), single: labels.count == 1))
            case .includesNone: return .term(labels.map { "NOT \($0)" }.joined(separator: " AND "))
            default: return .term(labels.joined(separator: " AND "))
            }
        case .parent:
            let parents = values.map { "parent=\($0)" }
            let term = rule.op == .isNoneOf
                ? parents.map { "NOT \($0)" }.joined(separator: " AND ")
                : group(parents.joined(separator: " OR "), single: parents.count == 1)
            // bd's parent= is one level; Beady's focus takes the whole subtree.
            return .term(term)
        case .updated:
            guard let window = values.first.flatMap(TimeWindow.init(rawValue:)) else { return .nothing }
            return .term("updated>\(duration(window))")
        case .closed:
            // Beady keeps every live bead and hides done beads older than the window.
            guard let window = values.first.flatMap(TimeWindow.init(rawValue:)) else { return .nothing }
            let done = catalog.names.filter { catalog.category(of: $0) == .done }.sorted()
            let live = done.map { "status!=\($0)" }.joined(separator: " AND ")
            return .term("(\(live) OR closed>\(duration(window)))")
        case .ready:
            return .note("Ready is computed from the dependency graph: bd ready lists it.")
        case .blocked:
            return .note(rule.op == .isNoneOf
                ? "Blocked is computed from the dependency graph: bd blocked lists what to leave out."
                : "Blocked is computed from the dependency graph: bd blocked lists it.")
        }
    }

    /// `field=a`, `(field=a OR field=b)`, or the negation as `!=` terms ANDed together.
    private static func anyOf(_ field: String, _ values: [String], negated: Bool) -> String {
        if negated {
            return values.map { "\(field)!=\(quoted($0))" }.joined(separator: " AND ")
        }
        let terms = values.map { "\(field)=\(quoted($0))" }
        return group(terms.joined(separator: " OR "), single: terms.count == 1)
    }

    /// A run from P0 reads as `priority<=N`, a run to P4 as `priority>=N`; anything else lists.
    private static func priorities(_ values: [String], negated: Bool) -> String {
        let levels = values.compactMap(Int.init).sorted()
        let contiguous = levels.enumerated().allSatisfy { $0.element == levels[0] + $0.offset }
        if negated {
            return levels.map { "priority!=\($0)" }.joined(separator: " AND ")
        }
        if contiguous, levels.count > 1, levels.first == 0 { return "priority<=\(levels.last!)" }
        if contiguous, levels.count > 1, levels.last == 4 { return "priority>=\(levels.first!)" }
        let terms = levels.map { "priority=\($0)" }
        return group(terms.joined(separator: " OR "), single: terms.count == 1)
    }

    private static func group(_ expression: String, single: Bool) -> String {
        single ? expression : "(\(expression))"
    }

    /// A value with a space or a character the parser reads as an operator is quoted.
    static func quoted(_ value: String) -> String {
        let plain = value.allSatisfy { $0.isLetter || $0.isNumber || "-_.:/@+".contains($0) }
        return plain && !value.isEmpty ? value : "\"\(value.replacingOccurrences(of: "\"", with: "\\\""))\""
    }

    private static func duration(_ window: TimeWindow) -> String {
        switch window {
        case .day: "24h"
        case .week: "7d"
        case .month: "30d"
        case .quarter: "90d"
        }
    }

    /// bd's own sort fields; bd lists newest first for dates and P0 first for priority, as
    /// Beady does, so no `--reverse` is needed.
    static func sortField(_ ordering: IssueSort) -> String {
        switch ordering {
        case .priority: "priority"
        case .recentlyUpdated: "updated"
        case .recentlyCreated: "created"
        case .recentlyClosed: "closed"
        case .issueID: "id"
        }
    }

    /// Whether the rules leave no done bead through, in which case `--all` would change nothing.
    private static func excludesDone(_ filter: ViewFilter, catalog: StatusCatalog) -> Bool {
        let done = Set(catalog.names.filter { catalog.category(of: $0) == .done })
        for rule in filter.rules where !rule.values.isEmpty {
            switch (rule.field, rule.op) {
            case (.lifecycle, .isAnyOf) where !rule.values.contains(StatusCategory.done.rawValue): return true
            case (.lifecycle, .isNoneOf) where rule.values.contains(StatusCategory.done.rawValue): return true
            case (.status, .isAnyOf) where rule.values.isDisjoint(with: done): return true
            case (.status, .isNoneOf) where done.isSubset(of: rule.values): return true
            default: continue
            }
        }
        return false
    }
}
