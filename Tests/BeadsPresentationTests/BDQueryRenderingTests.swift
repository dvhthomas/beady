import BeadsCore
import BeadsPresentation
import Foundation
import Testing

/// Copy as bd Command: a view's rules and ordering as the `bd query` line that says the same,
/// with a comment for what bd query can't express.
@Suite("Copy as bd command")
struct BDQueryRenderingTests {
    func render(_ rules: [FilterRule], search: String = "", ordering: IssueSort = .priority, catalog: StatusCatalog = .builtIn) -> BDQuery {
        BDQueryRendering.query(filter: ViewFilter(rules: rules, searchText: search), ordering: ordering, catalog: catalog)
    }

    @Test("a lifecycle category expands to the statuses this database files under it")
    func lifecycle() {
        let query = render([FilterRule(field: .lifecycle, op: .isAnyOf, values: [StatusCategory.wip.rawValue])])
        #expect(query.expression == "(status=blocked OR status=hooked OR status=in_progress)")
        #expect(!query.includesClosed, "a view of live work needs no --all")
        let custom = render([FilterRule(field: .lifecycle, op: .isAnyOf, values: [StatusCategory.active.rawValue])], catalog: StatusCatalog(["open": .active, "triage": .active, "closed": .done]))
        #expect(custom.expression == "(status=open OR status=triage)")
        let not = render([FilterRule(field: .lifecycle, op: .isNoneOf, values: [StatusCategory.done.rawValue])])
        #expect(not.expression == "status!=closed")
    }

    @Test("status, type and assignee map to = and != terms, with none for unassigned")
    func singleValued() {
        #expect(render([FilterRule(field: .status, op: .isAnyOf, values: ["open"])]).expression == "status=open")
        #expect(render([FilterRule(field: .type, op: .isNoneOf, values: ["bug", "epic"])]).expression == "type!=bug AND type!=epic")
        #expect(render([FilterRule(field: .assignee, op: .isAnyOf, values: ["ann", FilterRule.unassigned])]).expression == "(assignee=none OR assignee=ann)")
        #expect(render([FilterRule(field: .assignee, op: .isAnyOf, values: ["Ann Lee"])]).expression == "assignee=\"Ann Lee\"", "a space needs quotes")
    }

    @Test("priorities read as a range when they are one, otherwise as a list")
    func priorities() {
        #expect(render([FilterRule(field: .priority, op: .isAnyOf, values: ["0", "1"])]).expression == "priority<=1")
        #expect(render([FilterRule(field: .priority, op: .isAnyOf, values: ["3", "4"])]).expression == "priority>=3")
        #expect(render([FilterRule(field: .priority, op: .isAnyOf, values: ["1", "3"])]).expression == "(priority=1 OR priority=3)")
        #expect(render([FilterRule(field: .priority, op: .isAnyOf, values: ["2"])]).expression == "priority=2")
        #expect(render([FilterRule(field: .priority, op: .isNoneOf, values: ["4"])]).expression == "priority!=4")
    }

    @Test("label operators map to label= joined with AND, OR and NOT")
    func labels() {
        #expect(render([FilterRule(field: .labels, op: .includesAll, values: ["ui", "api"])]).expression == "label=api AND label=ui")
        #expect(render([FilterRule(field: .labels, op: .includesAny, values: ["ui", "api"])]).expression == "(label=api OR label=ui)")
        #expect(render([FilterRule(field: .labels, op: .includesNone, values: ["ui", "api"])]).expression == "NOT label=api AND NOT label=ui")
        #expect(render([FilterRule(field: .labels, op: .includesAny, values: ["ui"])]).expression == "label=ui")
    }

    @Test("time windows become bd's relative durations; closed-within keeps every live bead")
    func windows() {
        #expect(render([FilterRule(field: .updated, op: .within, values: [TimeWindow.day.rawValue])]).expression == "updated>24h")
        let closed = render([FilterRule(field: .closed, op: .within, values: [TimeWindow.week.rawValue])])
        #expect(closed.expression == "(status!=closed OR closed>7d)")
        #expect(closed.includesClosed, "last week's done beads are part of the view")
    }

    @Test("a focus is parent=, and ready and blocked become comments that point at bd's own commands")
    func computed() {
        #expect(render([FilterRule(field: .parent, op: .isAnyOf, values: ["epic-1"])]).expression == "parent=epic-1")
        let ready = render([FilterRule(field: .ready, op: .isAnyOf, values: [FilterRule.readyValue])])
        #expect(ready.expression.isEmpty)
        #expect(ready.notes == ["Ready is computed from the dependency graph: bd ready lists it."])
        #expect(ready.commandLine == "bd query --sort priority --all  # Ready is computed from the dependency graph: bd ready lists it.")
        let blocked = render([FilterRule(field: .blocked, op: .isAnyOf, values: [FilterRule.blockedValue])])
        #expect(blocked.notes.first?.contains("bd blocked") == true)
    }

    @Test("search words become title= terms, with a note that Beady searches more than titles")
    func search() {
        let query = render([FilterRule(field: .status, op: .isAnyOf, values: ["open"])], search: "sidebar  views")
        #expect(query.expression == "status=open AND title=sidebar AND title=views")
        #expect(query.notes.count == 1)
    }

    @Test("ordering maps to --sort, and --all appears only where closed beads could show")
    func ordering() {
        #expect(render([], ordering: .recentlyUpdated).commandLine == "bd query --sort updated --all")
        #expect(render([], ordering: .recentlyCreated).sort == "created")
        #expect(render([], ordering: .recentlyClosed).sort == "closed")
        #expect(render([], ordering: .issueID).sort == "id")
        let open = render([FilterRule(field: .status, op: .isAnyOf, values: ["open", "in_progress"])], ordering: .priority)
        #expect(open.commandLine == "bd query \"(status=in_progress OR status=open)\" --sort priority")
    }

    @Test("every built-in view renders to a line bd can be given")
    func builtIns() {
        for view in IssueView.builtIns {
            let query = BDQueryRendering.query(for: view)
            #expect(query.commandLine.hasPrefix("bd query"), Comment(rawValue: view.name))
        }
        #expect(BDQueryRendering.query(for: IssueView.builtIn(.pipeline)!).expression == "(status!=closed OR closed>7d)")
        #expect(BDQueryRendering.query(for: IssueView.builtIn(.landed)!).expression == "status=closed AND (status!=closed OR closed>7d)")
        #expect(BDQueryRendering.query(for: IssueView.builtIn(.starred)!).expression == "label=starred")
        #expect(BDQueryRendering.query(for: IssueView.builtIn(.frontier)!).expression.isEmpty)
    }

    /// bd's own parser is the judge, when bd is on PATH: every built-in's expression parses.
    @Test("bd parses every built-in view's expression", .enabled(if: BDQueryRenderingTests.bdPath != nil))
    func bdParses() throws {
        let bd = try #require(Self.bdPath)
        for view in IssueView.builtIns {
            let query = BDQueryRendering.query(for: view)
            guard !query.expression.isEmpty else { continue }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: bd)
            process.arguments = ["query", "--readonly", query.expression, "--parse-only"]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            try process.run()
            process.waitUntilExit()
            let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            #expect(process.terminationStatus == 0 && output.contains("Parsed query"), "\(view.name): \(query.expression) → \(output)")
        }
    }

    static let bdPath: String? = {
        let candidates = ["/opt/homebrew/bin/bd", "/usr/local/bin/bd"] + (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":").map { "\($0)/bd" }
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }()
}
