import Foundation

/// Every `blocks` dependency in a database, laid out to be read left to right: what can start now
/// on the left, what waits on it further right — the same reading `bd graph` gives.
///
/// Dependency graphs in practice are small and sparse, so this favours being right and easy to
/// follow over being clever about scale.
public struct DependencyGraph: Sendable {
    /// `from` has to finish before `to` can start.
    public struct Edge: Hashable, Sendable {
        public let from: IssueID
        public let to: IssueID
    }

    /// A slot in the layout grid. Columns are layers; rows are assigned per group of work.
    public struct Position: Equatable, Sendable {
        public let column: Int
        public let row: Int
    }

    public let nodes: [Issue]
    public let edges: [Edge]
    /// Groups of beads connected by dependencies, largest first.
    public let components: [[IssueID]]

    private let blockers: [IssueID: Set<IssueID>]
    private let dependents: [IssueID: Set<IssueID>]
    private let layers: [IssueID: Int]

    public init(_ snapshot: IssueSnapshot, includeFinished: Bool = true) {
        var edges = Set<Edge>()
        for issue in snapshot.issues {
            for dependency in issue.dependencies where dependency.kind == .blocks {
                let blocker = dependency.dependsOnID
                guard blocker != issue.id, let blocking = snapshot.issue(blocker) else { continue }
                if !includeFinished, snapshot.isDone(issue) || snapshot.isDone(blocking) { continue }
                edges.insert(Edge(from: blocker, to: issue.id))
            }
        }
        let sortedEdges = edges.sorted { ($0.from, $0.to) < ($1.from, $1.to) }

        var blockers: [IssueID: Set<IssueID>] = [:]
        var dependents: [IssueID: Set<IssueID>] = [:]
        var ids = Set<IssueID>()
        for edge in sortedEdges {
            blockers[edge.to, default: []].insert(edge.from)
            dependents[edge.from, default: []].insert(edge.to)
            ids.insert(edge.from)
            ids.insert(edge.to)
        }

        self.edges = sortedEdges
        self.blockers = blockers
        self.dependents = dependents
        nodes = ids.compactMap(snapshot.issue).sorted { $0.id < $1.id }
        layers = Self.layers(ids: ids, blockers: blockers, dependents: dependents)
        components = Self.components(ids: ids, blockers: blockers, dependents: dependents)
    }

    public func layer(of id: IssueID) -> Int? {
        layers[id]
    }

    /// The beads this one waits on directly.
    public func directUpstream(of id: IssueID) -> Set<IssueID> {
        blockers[id] ?? []
    }

    /// Everything that has to finish, at any distance, before this bead can start.
    public func upstream(of id: IssueID) -> Set<IssueID> {
        reach(from: id, along: blockers)
    }

    /// Everything that is waiting, at any distance, on this bead.
    public func downstream(of id: IssueID) -> Set<IssueID> {
        reach(from: id, along: dependents)
    }

    /// A grid slot for every node: columns by layer, rows per group of work, groups stacked with a
    /// blank row between them.
    public func layout() -> [IssueID: Position] {
        var positions: [IssueID: Position] = [:]
        var rowOffset = 0
        for component in components {
            let columns = orderedColumns(of: component)
            let height = columns.values.map(\.count).max() ?? 0
            for (column, members) in columns {
                for (row, id) in members.enumerated() {
                    positions[id] = Position(column: column, row: rowOffset + row)
                }
            }
            rowOffset += height + 1
        }
        return positions
    }

    // MARK: Workings

    private func reach(from start: IssueID, along neighbours: [IssueID: Set<IssueID>]) -> Set<IssueID> {
        var seen = Set<IssueID>()
        var queue = Array(neighbours[start] ?? [])
        while let next = queue.popLast() {
            guard next != start, seen.insert(next).inserted else { continue }
            queue.append(contentsOf: neighbours[next] ?? [])
        }
        return seen
    }

    /// Nodes of one component grouped into columns, with rows ordered to keep lines from crossing:
    /// each bead sits near the average row of the beads it's connected to (the barycentre
    /// heuristic), swept left to right and back a few times.
    private func orderedColumns(of component: [IssueID]) -> [Int: [IssueID]] {
        var columns: [Int: [IssueID]] = [:]
        for id in component.sorted() {
            columns[layers[id] ?? 0, default: []].append(id)
        }
        let order = columns.keys.sorted()
        func rows() -> [IssueID: Double] {
            var result: [IssueID: Double] = [:]
            for members in columns.values {
                for (row, id) in members.enumerated() { result[id] = Double(row) }
            }
            return result
        }
        for _ in 0..<4 {
            for column in order.dropFirst() {
                let current = rows()
                columns[column]?.sort { barycentre($0, blockers, current) < barycentre($1, blockers, current) }
            }
            for column in order.reversed().dropFirst() {
                let current = rows()
                columns[column]?.sort { barycentre($0, dependents, current) < barycentre($1, dependents, current) }
            }
        }
        return columns
    }

    private func barycentre(_ id: IssueID, _ neighbours: [IssueID: Set<IssueID>], _ rows: [IssueID: Double]) -> Double {
        let values = (neighbours[id] ?? []).compactMap { rows[$0] }
        guard !values.isEmpty else { return rows[id] ?? 0 }
        // Ties fall back to the current row, so the sort is stable between sweeps.
        return values.reduce(0, +) / Double(values.count) + (rows[id] ?? 0) * 0.001
    }

    /// Longest path from a bead nothing blocks. Beads caught in a loop are placed after whatever
    /// of their blockers could be placed, so a loop is drawn rather than dropped.
    private static func layers(
        ids: Set<IssueID>,
        blockers: [IssueID: Set<IssueID>],
        dependents: [IssueID: Set<IssueID>]
    ) -> [IssueID: Int] {
        var remaining = Dictionary(uniqueKeysWithValues: ids.map { ($0, blockers[$0]?.count ?? 0) })
        var queue = ids.filter { remaining[$0] == 0 }.sorted()
        var layers: [IssueID: Int] = [:]
        while !queue.isEmpty {
            let id = queue.removeFirst()
            layers[id] = ((blockers[id] ?? []).compactMap { layers[$0] }.max() ?? -1) + 1
            for next in (dependents[id] ?? []).sorted() {
                remaining[next, default: 0] -= 1
                if remaining[next] == 0 { queue.append(next) }
            }
        }
        for id in ids.subtracting(layers.keys).sorted() {
            layers[id] = ((blockers[id] ?? []).compactMap { layers[$0] }.max() ?? -1) + 1
        }
        return layers
    }

    private static func components(
        ids: Set<IssueID>,
        blockers: [IssueID: Set<IssueID>],
        dependents: [IssueID: Set<IssueID>]
    ) -> [[IssueID]] {
        var seen = Set<IssueID>()
        var groups: [[IssueID]] = []
        for start in ids.sorted() where !seen.contains(start) {
            var group: [IssueID] = []
            var queue = [start]
            while let next = queue.popLast() {
                guard seen.insert(next).inserted else { continue }
                group.append(next)
                queue.append(contentsOf: blockers[next] ?? [])
                queue.append(contentsOf: dependents[next] ?? [])
            }
            groups.append(group.sorted())
        }
        return groups.sorted { $0.count != $1.count ? $0.count > $1.count : $0[0] < $1[0] }
    }
}
