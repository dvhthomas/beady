import BeadsCore
import BeadsPresentation
import Foundation
import Testing

/// Ready, Blocked, Deferred, Pinned, Hooked and the four lifecycle categories mean something exact
/// in bd. Every word the UI shows for them has a one-sentence definition, and a new word can't ship
/// without one.
@Suite("Hover help glossary")
struct HelpTextTests {
    /// Non-empty, ends in a full stop, and has no second sentence inside it.
    func isOneSentence(_ text: String) -> Bool {
        !text.isEmpty && text.hasSuffix(".") && !text.dropLast().contains(". ")
    }

    @Test("every filter field has a one-sentence definition")
    func fields() {
        for field in FilterField.allCases {
            #expect(isOneSentence(DisplayText.help(for: field)), "\(field)")
        }
    }

    @Test("every fixed filter value has a one-sentence definition")
    func fixedValues() {
        for window in TimeWindow.allCases {
            for field in [FilterField.updated, .closed] {
                let text = DisplayText.help(forValue: window.rawValue, in: field)
                #expect(text.map(isOneSentence) == true, "\(window) in \(field)")
            }
        }
        let blocked = DisplayText.help(forValue: FilterRule.blockedValue, in: .blocked)
        #expect(blocked.map(isOneSentence) == true)
        for status in StatusCatalog.builtIn.names {
            #expect(DisplayText.help(forValue: status, in: .status).map(isOneSentence) == true, Comment(rawValue: status))
        }
        for category in StatusCategory.allCases {
            #expect(isOneSentence(DisplayText.help(for: category)), "\(category)")
        }
    }

    @Test("free-form filter values have no definition to show")
    func freeFormValues() {
        #expect(DisplayText.help(forValue: "ann", in: .assignee) == nil)
        #expect(DisplayText.help(forValue: "ui", in: .labels) == nil)
        #expect(DisplayText.help(forValue: "epic", in: .parent) == nil)
        #expect(DisplayText.help(forValue: "bug", in: .type) == nil)
    }

    @Test("every status category has a one-sentence definition that names bd's word for it")
    func categories() {
        for category in StatusCategory.allCases {
            let text = DisplayText.help(for: category)
            #expect(isOneSentence(text), "\(category)")
            #expect(text.contains(category.rawValue), "\(category) should name bd's category")
        }
    }

    @Test("every built-in status has a one-sentence definition")
    func builtInStatuses() {
        let catalog = StatusCatalog.builtIn
        #expect(catalog.names.count == 7)
        for status in catalog.names {
            let text = DisplayText.help(forStatus: status, category: catalog.category(of: status))
            #expect(isOneSentence(text), Comment(rawValue: status))
        }
    }

    @Test("a custom status is explained through its category")
    func customStatus() {
        let text = DisplayText.help(forStatus: "in_review", category: .wip)
        #expect(isOneSentence(text))
        #expect(text.contains("custom"))
        #expect(text.contains("wip"))
    }

    @Test("every scope has a one-sentence definition")
    func scopes() {
        for scope in Scope.allCases {
            #expect(isOneSentence(DisplayText.help(for: scope)), "\(scope)")
        }
    }

    @Test("every grouping has a one-sentence definition")
    func groupings() {
        for grouping in IssueGrouping.allCases {
            #expect(isOneSentence(DisplayText.help(for: grouping)), "\(grouping)")
        }
    }

    @Test("Ready and Blocked say they are computed from the dependency graph, not stored")
    func computedNotStored() {
        for text in [
            DisplayText.help(for: Scope.ready),
            DisplayText.help(for: Scope.blocked),
            DisplayText.help(for: FilterField.blocked),
            DisplayText.help(forValue: FilterRule.blockedValue, in: .blocked) ?? "",
        ] {
            #expect(text.contains("dependency graph"), Comment(rawValue: text))
            #expect(text.contains("stored"), Comment(rawValue: text))
        }
    }

    @Test("Ready follows bd ready: active, nothing blocking, not deferred, not hooked")
    func readyFollowsBD() {
        let text = DisplayText.help(for: Scope.ready).lowercased()
        #expect(text.contains("active"))
        #expect(text.contains("block"))
        #expect(text.contains("deferred"))
        #expect(text.contains("hook"))
    }

    @Test("built-in statuses use bd's own words from bd statuses")
    func bdWords() {
        let catalog = StatusCatalog.builtIn
        func help(_ status: String) -> String { DisplayText.help(forStatus: status, category: catalog.category(of: status)) }
        #expect(help("open").contains("Available to work"))
        #expect(help("in_progress").contains("Actively being worked on"))
        #expect(help("deferred").contains("put on ice"))
        #expect(help("pinned").contains("stays open"))
        #expect(help("hooked").contains("agent's hook"))
        #expect(help("closed").contains("Completed"))
        #expect(help("blocked").contains("stored"), "the stored status is not what the Blocked view shows")
    }
}

@MainActor
@Suite("Hover help wiring")
struct HelpWiringTests {
    func makeModel() async -> WorkspaceModel {
        let store = MemoryStore([
            makeIssue("a", status: "open", assignee: "ann", labels: ["ui"]),
            makeIssue("b", status: "in_progress"),
            makeIssue("c", status: "closed", closed: t0),
        ])
        let model = WorkspaceModel(title: "demo", store: store, now: { t0 })
        await model.load()
        return model
    }

    @Test("every lifecycle row in the sidebar carries its definition")
    func sidebar() async {
        let model = await makeModel()
        for entry in model.sidebarViews {
            guard case .lifecycle(let scope) = entry.source else { continue }
            #expect(entry.help == DisplayText.help(for: scope), Comment(rawValue: entry.title))
        }
    }

    @Test("filter chips carry the field's definition, and a single fixed value's")
    func chips() async {
        let model = await makeModel()
        model.toggleFilterValue("in_progress", in: .status)
        model.toggleFilterValue(TimeWindow.week.rawValue, in: .updated)
        model.toggleFilterValue("ann", in: .assignee)
        let chips = Dictionary(uniqueKeysWithValues: model.filterChips.map { ($0.field, $0) })
        #expect(chips[.status]?.fieldHelp == DisplayText.help(for: FilterField.status))
        #expect(chips[.status]?.valuesHelp == DisplayText.help(forValue: "in_progress", in: .status))
        #expect(chips[.updated]?.valuesHelp == DisplayText.help(forValue: "week", in: .updated))
        #expect(chips[.assignee]?.valuesHelp == nil, "a name has nothing to define")
        model.toggleFilterValue("open", in: .status)
        #expect(model.filterChips.first { $0.field == .status }?.valuesHelp == nil, "several values, no single definition")
    }

    @Test("filter menu options carry definitions for fixed values only")
    func menuOptions() async {
        let model = await makeModel()
        let statuses = model.filterOptions(for: .status)
        #expect(!statuses.isEmpty)
        #expect(statuses.allSatisfy { $0.help != nil })
        #expect(model.filterOptions(for: .updated).allSatisfy { $0.help != nil })
        #expect(model.filterOptions(for: .assignee).allSatisfy { $0.help == nil })
    }
}
