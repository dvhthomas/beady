import Foundation

// Linear-style view filtering: a view draws issues from a source, then applies rules (one per
// field, ANDed) and search words. Everything here is pure.

// MARK: Rules

public enum FilterField: String, CaseIterable, Identifiable, Codable, Sendable {
    case status, priority, type, assignee, labels, blocked, parent, updated, closed

    public var id: String { rawValue }

    /// The operators that make sense for this field. The first is the default.
    public var operators: [FilterOperator] {
        switch self {
        case .status, .priority, .type, .assignee, .blocked, .parent: [.isAnyOf, .isNoneOf]
        case .labels: [.includesAll, .includesAny, .includesNone]
        case .updated, .closed: [.within]
        }
    }

    public var defaultOperator: FilterOperator { operators[0] }

    /// Choosing a value replaces the previous one instead of adding to it.
    public var isSingleChoice: Bool {
        switch self {
        case .blocked, .updated, .closed: true
        default: false
        }
    }
}

public enum FilterOperator: String, CaseIterable, Codable, Sendable {
    case isAnyOf, isNoneOf, includesAll, includesAny, includesNone, within
}

public struct FilterRule: Identifiable, Hashable, Codable, Sendable {
    /// The assignee value that means "no one".
    public static let unassigned = ""
    /// The only value of the blocked field.
    public static let blockedValue = "blocked"

    public var field: FilterField
    public var op: FilterOperator
    /// Raw values: status names, priorities as "0"…"4", types, assignee names, labels, parent ids,
    /// or a `TimeWindow` raw value.
    public var values: Set<String>

    public var id: FilterField { field }

    public init(field: FilterField, op: FilterOperator, values: Set<String>) {
        self.field = field
        self.op = op
        self.values = values
    }

    /// A rule with no values matches everything.
    public func matches(_ issue: Issue, in snapshot: IssueSnapshot, now: Date) -> Bool {
        guard !values.isEmpty else { return true }
        switch field {
        case .labels:
            let labels = Set(issue.labels)
            switch op {
            case .includesAny: return !labels.isDisjoint(with: values)
            case .includesNone: return labels.isDisjoint(with: values)
            default: return values.isSubset(of: labels)
            }
        case .updated:
            guard let window = values.first.flatMap(TimeWindow.init(rawValue:)) else { return true }
            return window.contains(issue.updatedAt, now: now)
        case .closed:
            guard let window = values.first.flatMap(TimeWindow.init(rawValue:)) else { return true }
            return snapshot.isDone(issue) && window.contains(issue.closedAt, now: now)
        case .parent:
            let under = values.contains { snapshot.isDescendant(issue, of: IssueID($0)) }
            return op == .isNoneOf ? !under : under
        case .status, .priority, .type, .assignee, .blocked:
            let hit = values.contains(Self.value(of: issue, for: field, in: snapshot))
            return op == .isNoneOf ? !hit : hit
        }
    }

    /// The one value an issue has for a single-valued field.
    static func value(of issue: Issue, for field: FilterField, in snapshot: IssueSnapshot) -> String {
        switch field {
        case .status: issue.status
        case .priority: String(issue.priority)
        case .type: issue.type
        case .assignee: issue.assignee ?? unassigned
        case .blocked: snapshot.isBlocked(issue) ? blockedValue : ""
        case .labels, .parent, .updated, .closed: ""
        }
    }
}

// MARK: A view's filter

public struct ViewFilter: Hashable, Codable, Sendable {
    private enum CodingKeys: String, CodingKey {
        case rules, searchText
    }

    /// Decoding goes through `init(rules:searchText:)` so saved state can't reintroduce two
    /// rules for one field.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            rules: try container.decodeIfPresent([FilterRule].self, forKey: .rules) ?? [],
            searchText: try container.decodeIfPresent(String.self, forKey: .searchText) ?? ""
        )
    }

    /// At most one rule per field, in the order they were added.
    public private(set) var rules: [FilterRule]
    public var searchText: String

    public init(rules: [FilterRule] = [], searchText: String = "") {
        var merged: [FilterRule] = []
        for rule in rules {
            if let index = merged.firstIndex(where: { $0.field == rule.field }) {
                merged[index] = rule
            } else {
                merged.append(rule)
            }
        }
        self.rules = merged
        self.searchText = searchText
    }

    public var searchWords: [String] {
        searchText.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    public var isEmpty: Bool { rules.isEmpty && searchWords.isEmpty }

    public func rule(for field: FilterField) -> FilterRule? {
        rules.first { $0.field == field }
    }

    /// Every rule, and every search word, must match.
    public func matches(_ issue: Issue, in snapshot: IssueSnapshot, now: Date) -> Bool {
        rules.allSatisfy { $0.matches(issue, in: snapshot, now: now) } && searchWords.allSatisfy(issue.mentions)
    }

    /// Ticks or unticks a value. The first value adds the rule with the field's default operator;
    /// unticking the last value removes the rule. Single-choice fields replace their value.
    public mutating func toggle(_ value: String, in field: FilterField) {
        guard let index = rules.firstIndex(where: { $0.field == field }) else {
            rules.append(FilterRule(field: field, op: field.defaultOperator, values: [value]))
            return
        }
        var rule = rules[index]
        if rule.values.contains(value) {
            rule.values.remove(value)
        } else if field.isSingleChoice {
            rule.values = [value]
        } else {
            rule.values.insert(value)
        }
        if rule.values.isEmpty {
            rules.remove(at: index)
        } else {
            rules[index] = rule
        }
    }

    /// Ignored unless the operator fits the field and the field has a rule.
    public mutating func setOperator(_ op: FilterOperator, for field: FilterField) {
        guard field.operators.contains(op), let index = rules.firstIndex(where: { $0.field == field }) else { return }
        rules[index].op = op
    }

    public mutating func remove(_ field: FilterField) {
        rules.removeAll { $0.field == field }
    }

    public mutating func removeAllRules() {
        rules = []
    }

    /// This filter without the rule for `field`: what counts for that field's options are based on.
    public func without(_ field: FilterField) -> ViewFilter {
        var copy = self
        copy.remove(field)
        return copy
    }
}

// MARK: Sources

/// Where a view draws its issues from, before any filter.
public enum ViewSource: Hashable, Codable, Sendable {
    case lifecycle(Scope)
    /// Everything under one bead, at any depth and in any status, not the bead itself.
    /// Any bead can hold work, so this isn't limited to epics.
    case focused(IssueID)
    /// Everything carrying one bd label, whatever its lifecycle. Starred is this.
    case label(String)

    public func includes(_ issue: Issue, in snapshot: IssueSnapshot, now: Date) -> Bool {
        switch self {
        case .lifecycle(let scope): scope.includes(issue, in: snapshot, now: now)
        case .focused(let id): snapshot.isDescendant(issue, of: id)
        case .label(let label): issue.labels.contains(label)
        }
    }

    /// The status categories that can appear in this view. Status filter options are limited to these.
    public var categories: Set<StatusCategory> {
        switch self {
        case .lifecycle(.open), .lifecycle(.ready): [.active]
        case .lifecycle(.inFlight): [.wip]
        case .lifecycle(.deferred): [.frozen]
        case .lifecycle(.closed): [.done]
        case .lifecycle(.blocked): [.active, .wip, .frozen]
        case .lifecycle(.all), .focused, .label: Set(StatusCategory.allCases)
        }
    }
}

// MARK: Options

public struct FilterValueOption: Identifiable, Hashable, Sendable {
    public let value: String
    /// Issues in the view, under every other rule, that have this value.
    public let count: Int
    public let isSelected: Bool

    public var id: String { value }

    public init(value: String, count: Int, isSelected: Bool) {
        self.value = value
        self.count = count
        self.isSelected = isSelected
    }
}

public enum FilterOptions {
    /// The values offered for a field in a view. Counts ignore the field's own rule, so choosing
    /// a second value is informed. Status, priority, blocked and date options are always listed;
    /// the longer lists (type, assignee, labels, parent) hide values with nothing to show unless ticked.
    public static func options(
        for field: FilterField,
        source: ViewSource,
        filter: ViewFilter,
        in snapshot: IssueSnapshot,
        now: Date
    ) -> [FilterValueOption] {
        let others = filter.without(field)
        let base = snapshot.issues.filter {
            source.includes($0, in: snapshot, now: now) && others.matches($0, in: snapshot, now: now)
        }
        let selected = filter.rule(for: field)?.values ?? []

        func tally(_ keys: (Issue) -> [String]) -> [String: Int] {
            var counts: [String: Int] = [:]
            for issue in base {
                for key in keys(issue) { counts[key, default: 0] += 1 }
            }
            return counts
        }
        func listed(_ values: [String], _ counts: [String: Int], hidingEmpty: Bool) -> [FilterValueOption] {
            values.compactMap { value in
                let count = counts[value] ?? 0
                let isSelected = selected.contains(value)
                if hidingEmpty, count == 0, !isSelected { return nil }
                return FilterValueOption(value: value, count: count, isSelected: isSelected)
            }
        }

        switch field {
        case .status:
            let order = { (status: String) in StatusCategory.allCases.firstIndex(of: snapshot.catalog.category(of: status)) ?? 0 }
            let statuses = snapshot.statuses
                .filter { source.categories.contains(snapshot.catalog.category(of: $0)) }
                .sorted { (order($0), $0) < (order($1), $1) }
            return listed(statuses, tally { [$0.status] }, hidingEmpty: false)
        case .priority:
            return listed((0...4).map(String.init), tally { [String($0.priority)] }, hidingEmpty: false)
        case .type:
            return listed(snapshot.types, tally { [$0.type] }, hidingEmpty: true)
        case .assignee:
            return listed([FilterRule.unassigned] + snapshot.assignees, tally { [$0.assignee ?? FilterRule.unassigned] }, hidingEmpty: true)
        case .labels:
            return listed(snapshot.labels, tally(\.labels), hidingEmpty: true)
        case .blocked:
            let count = base.filter { snapshot.isBlocked($0) }.count
            return [FilterValueOption(value: FilterRule.blockedValue, count: count, isSelected: selected.contains(FilterRule.blockedValue))]
        case .parent:
            // Anything that holds work, not only epics: bd's parent/child graph doesn't care
            // about types, and neither should the filter.
            let parents = snapshot.issues
                .filter { !snapshot.isDone($0) && !snapshot.children(of: $0.id).isEmpty }
                .map(\.id)
            var counts: [String: Int] = [:]
            for parent in parents {
                counts[parent.rawValue] = base.filter { snapshot.isDescendant($0, of: parent) }.count
            }
            return listed(parents.map(\.rawValue), counts, hidingEmpty: true)
        case .updated, .closed:
            return TimeWindow.allCases.map { window in
                let count = base.filter { issue in
                    field == .updated
                        ? window.contains(issue.updatedAt, now: now)
                        : snapshot.isDone(issue) && window.contains(issue.closedAt, now: now)
                }.count
                return FilterValueOption(value: window.rawValue, count: count, isSelected: selected.contains(window.rawValue))
            }
        }
    }
}

// MARK: Grouping

public struct IssueGroup: Identifiable, Hashable, Sendable {
    /// Raw value: category or status name, priority "0"…"4", type, assignee, parent id; "" for
    /// Unassigned, No parent, or the single group when not grouping.
    public let key: String
    public let issues: [Issue]

    public var id: String { key }

    public init(key: String, issues: [Issue]) {
        self.key = key
        self.issues = issues
    }
}

public enum IssueGrouping: String, CaseIterable, Identifiable, Codable, Sendable {
    case none, category, status, priority, type, assignee, parent

    public var id: String { rawValue }

    public func key(for issue: Issue, in snapshot: IssueSnapshot) -> String {
        switch self {
        case .none: ""
        case .category: snapshot.category(of: issue).rawValue
        case .status: issue.status
        case .priority: String(issue.priority)
        case .type: issue.type
        case .assignee: issue.assignee ?? FilterRule.unassigned
        case .parent: issue.parentID?.rawValue ?? ""
        }
    }

    /// Groups in a stable order: lifecycle for category and status, numeric for priority,
    /// alphabetical otherwise, with Unassigned and No parent last. Each group keeps the order of
    /// `issues`. `extraKeys` are included even when empty, such as board columns to drop into.
    public func groups(_ issues: [Issue], in snapshot: IssueSnapshot, including extraKeys: [String] = []) -> [IssueGroup] {
        if self == .none {
            return issues.isEmpty ? [] : [IssueGroup(key: "", issues: issues)]
        }
        var buckets: [String: [Issue]] = [:]
        var keys: [String] = []
        for issue in issues {
            let key = key(for: issue, in: snapshot)
            if buckets[key] == nil { keys.append(key) }
            buckets[key, default: []].append(issue)
        }
        for key in extraKeys where buckets[key] == nil {
            buckets[key] = []
            keys.append(key)
        }
        return keys
            .sorted { isOrdered($0, before: $1, in: snapshot) }
            .map { IssueGroup(key: $0, issues: buckets[$0] ?? []) }
    }

    private func isOrdered(_ a: String, before b: String, in snapshot: IssueSnapshot) -> Bool {
        func lifecycleIndex(_ category: StatusCategory?) -> Int {
            category.flatMap { StatusCategory.allCases.firstIndex(of: $0) } ?? StatusCategory.allCases.count
        }
        switch self {
        case .none:
            return false
        case .category:
            return lifecycleIndex(StatusCategory(rawValue: a)) < lifecycleIndex(StatusCategory(rawValue: b))
        case .status:
            let (left, right) = (lifecycleIndex(snapshot.catalog.category(of: a)), lifecycleIndex(snapshot.catalog.category(of: b)))
            return left != right ? left < right : a < b
        case .priority:
            return (Int(a) ?? .max) < (Int(b) ?? .max)
        case .type:
            return a < b
        case .assignee, .parent:
            if a.isEmpty != b.isEmpty { return b.isEmpty }
            return IssueID(a) < IssueID(b)
        }
    }
}
