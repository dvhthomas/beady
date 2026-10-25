import BeadsCore
import BeadsPresentation
import Foundation
import Testing

/// The second tier of views: `.beads/beady/views` in the open workspace, shared through git.
/// A view is moved between My Views and This Workspace, and its file follows.
@MainActor
@Suite("Views kept in the workspace")
struct WorkspaceViewTierTests {
    func scratch(_ name: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("beady-\(name)-\(UUID().uuidString)", isDirectory: true)
    }

    func makeView(_ name: String, id: String) -> IssueView {
        IssueView(
            id: IssueView.ID(id), name: name, symbol: "bookmark",
            filter: ViewFilter(rules: [FilterRule(field: .labels, op: .includesAny, values: [name.lowercased()])]),
            presentation: ViewPresentation(layout: .list, grouping: .none, ordering: .priority)
        )
    }

    func files(in directory: URL) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []).sorted()
    }

    @Test("loading reads both folders and remembers which views are the workspace's")
    func load() throws {
        let library = scratch("library"), workspace = scratch("workspace")
        try FileManager.default.createDirectory(at: library, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        try makeView("Mine", id: "mine").documentData().write(to: library.appendingPathComponent("mine.beadyview"))
        try makeView("Team", id: "team").documentData().write(to: workspace.appendingPathComponent("team.beadyview"))
        try makeView("Clash", id: "mine").documentData().write(to: workspace.appendingPathComponent("clash.beadyview"))

        let loaded = ViewLibrary.load(from: library, workspaceDirectory: workspace, preferences: nil)
        #expect(loaded.views.filter { !$0.isBuiltIn }.map(\.name) == ["Mine", "Team"], "a workspace file with the Library's id is left to the Library")
        #expect(loaded.tier(of: IssueView.ID("team")) == .workspace)
        #expect(loaded.tier(of: IssueView.ID("mine")) == .library)
        #expect(loaded.tier(of: .frontier) == .library)

        // No workspace folder yet is simply no workspace views.
        let none = ViewLibrary.load(from: library, workspaceDirectory: scratch("missing"), preferences: nil)
        #expect(none.workspaceViewIDs.isEmpty)
    }

    @Test("saving writes each tier to its own folder, and never creates the workspace folder until something is moved in")
    func save() {
        let library = scratch("library"), workspace = scratch("workspace")
        var views = ViewLibrary()
        views.views.append(makeView("Mine", id: "mine"))
        views.save(to: library, workspaceDirectory: workspace, preferences: nil)
        #expect(files(in: library) == ["mine.beadyview"])
        #expect(!FileManager.default.fileExists(atPath: workspace.path), "opening a database leaves no mark in its .beads")

        let toWorkspace = views.moveView(IssueView.ID("mine"), to: .workspace)
        #expect(toWorkspace)
        views.save(to: library, workspaceDirectory: workspace, preferences: nil)
        #expect(files(in: library).isEmpty)
        #expect(files(in: workspace) == ["mine.beadyview"], "the file moved with the view")
        #expect(ViewLibrary.load(from: library, workspaceDirectory: workspace, preferences: nil).tier(of: IssueView.ID("mine")) == .workspace)

        let back = views.moveView(IssueView.ID("mine"), to: .library)
        #expect(back)
        views.save(to: library, workspaceDirectory: workspace, preferences: nil)
        #expect(files(in: library) == ["mine.beadyview"])
        #expect(files(in: workspace).isEmpty, "and back")

        let again = views.moveView(IssueView.ID("mine"), to: .library)
        #expect(!again, "already there")
        let builtIn = views.moveView(.frontier, to: .workspace)
        #expect(!builtIn, "a built-in stays in the Library")
        var frontier = views.views[0]
        frontier.presentation.layout = .board
        views.views[0] = frontier
        views.save(to: library, workspaceDirectory: workspace, preferences: nil)
        #expect(files(in: library) == ["frontier.beadyview", "mine.beadyview"], "a built-in's remembered presentation is the user's, not the workspace's")
    }

    @Test("the model shows a This Workspace section, moves views between tiers, and picks up files that change on disk")
    func model() async throws {
        let library = scratch("library"), workspace = scratch("workspace")
        let store = StubStore([makeIssue("a", labels: ["team"]), makeIssue("b")])
        let model = WorkspaceModel(title: "demo", store: store, viewsDirectory: library, workspaceViewsDirectory: workspace, now: { t0 })
        await model.load()
        #expect(model.canShareViews)
        #expect(model.sidebarSections.map(\.kind) == [.views, .mine, .workspace])
        #expect(model.sidebarSections.map(\.title) == ["Views", "My Views", "This Workspace"])
        #expect(model.sidebarSections.map(\.dropTier) == [nil, .library, .workspace])
        #expect(!FileManager.default.fileExists(atPath: workspace.path))

        model.toggleFilterValue("team", in: .labels)
        let team = model.saveAsNewView(name: "Team")
        #expect(model.sidebarSections[1].entries.map(\.title) == ["Team"])
        #expect(model.moveView(team.id, to: .workspace))
        #expect(model.sidebarSections[1].entries.isEmpty)
        #expect(model.sidebarSections[2].entries.map(\.title) == ["Team"])
        #expect(model.sidebarSections[2].entries.first?.tier == .workspace)
        #expect(model.sidebarSections[2].entries.first?.count == 1)
        #expect(files(in: workspace) == ["\(team.id.rawValue).beadyview"])
        #expect(files(in: library).isEmpty)
        #expect(model.views.contains { $0.id == team.id }, "still a view like any other")

        // Someone pulled a view into the workspace folder: it appears on the next reload.
        try makeView("Pulled", id: "pulled").documentData().write(to: workspace.appendingPathComponent("pulled.beadyview"))
        model.reloadViews()
        #expect(model.sidebarSections[2].entries.map(\.title) == ["Pulled", "Team"])
        #expect(model.tier(of: IssueView.ID("pulled")) == .workspace)
        // And one edited by hand is read as edited.
        var edited = makeView("Pulled again", id: "pulled")
        edited.symbol = "flag"
        try edited.documentData().write(to: workspace.appendingPathComponent("pulled.beadyview"))
        model.reloadViews()
        #expect(model.sidebarSections[2].entries.map(\.title) == ["Pulled again", "Team"])

        // Without a workspace folder there is no section and nothing to move into.
        let plain = WorkspaceModel(title: "demo", store: store, viewsDirectory: scratch("other"), now: { t0 })
        await plain.load()
        #expect(!plain.canShareViews)
        #expect(plain.sidebarSections.map(\.kind) == [.views, .mine])
        let mine = plain.saveAsNewView(name: "Mine")
        #expect(!plain.moveView(mine.id, to: .workspace))
    }

    @Test("a dragged view is carried under a private prefix, so stray text never moves anything")
    func dragPayload() {
        let id = IssueView.ID("2F1A")
        #expect(ViewDragPayload.decode([ViewDragPayload.encode(id)]) == id)
        #expect(ViewDragPayload.decode(["2F1A"]) == nil)
        #expect(ViewDragPayload.decode([ViewDragPayload.encode(id), ViewDragPayload.encode(id)]) == nil)
        #expect(ViewDragPayload.decode([IssueDragPayload.encode("bead-1")]) == nil, "a bead isn't a view")
    }
}
