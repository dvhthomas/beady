import BeadsPresentation
import Foundation
import Testing

@Suite("What opening a chosen folder does")
struct WorkspaceOpeningTests {
    @Test("a folder that already holds a beads database is simply opened")
    func opensWorkspace() {
        let folder = ChosenFolder(path: "/Users/ada/code/engine", hasBeadsDatabase: true, isGitRepository: true)
        #expect(WorkspaceOpening.decide(folder) == .open)
    }

    @Test("a database in a folder without git is opened too: the git rule is for creating, not opening")
    func opensWorkspaceWithoutGit() {
        let folder = ChosenFolder(path: "/Users/ada/code/engine", hasBeadsDatabase: true, isGitRepository: false)
        #expect(WorkspaceOpening.decide(folder) == .open)
    }

    @Test("a git repository without a database gets an offer to create one, with defaults from the folder")
    func offersNewDatabase() {
        let folder = ChosenFolder(path: "/Users/ada/code/Tile Engine", hasBeadsDatabase: false, isGitRepository: true)
        #expect(WorkspaceOpening.decide(folder) == .offerNewDatabase(
            NewDatabasePlan(projectPath: "/Users/ada/code/Tile Engine", prefix: "tile-engine")
        ))
    }

    @Test("a plain folder is refused with the reason: bd would otherwise create a git repository there itself")
    func refusesPlainFolder() {
        let folder = ChosenFolder(path: "/Users/ada/Documents/notes", hasBeadsDatabase: false, isGitRepository: false)
        guard case .refuse(let reason) = WorkspaceOpening.decide(folder) else {
            Issue.record("expected a refusal")
            return
        }
        #expect(reason.contains("/Users/ada/Documents/notes"))
        #expect(reason.contains("git"))
    }
}

@Suite("The defaults for a new database")
struct NewDatabasePlanTests {
    @Test("the prefix is the folder name, lowercased, with runs of anything else becoming one hyphen")
    func prefixFromFolderName() {
        #expect(NewDatabasePlan.prefix(forFolderNamed: "beady") == "beady")
        #expect(NewDatabasePlan.prefix(forFolderNamed: "Tile Engine") == "tile-engine")
        #expect(NewDatabasePlan.prefix(forFolderNamed: "my_project_v2") == "my-project-v2")
        #expect(NewDatabasePlan.prefix(forFolderNamed: "  spaced..out!! ") == "spaced-out")
        #expect(NewDatabasePlan.prefix(forFolderNamed: "Ünïcödé-ok") == "unicode-ok")
    }

    @Test("it starts with a letter, since bd's database name must, and is kept short")
    func prefixShape() {
        #expect(NewDatabasePlan.prefix(forFolderNamed: "2024-planning") == "planning")
        #expect(NewDatabasePlan.prefix(forFolderNamed: "-leading") == "leading")
        #expect(NewDatabasePlan.prefix(forFolderNamed: "a-really-long-repository-name-for-a-project") == "a-really-long")
        #expect(NewDatabasePlan.prefix(forFolderNamed: "trailing-hyphen-at-the-cut-") == "trailing-hyphen")
        #expect(NewDatabasePlan.prefix(forFolderNamed: "sixteen-letters-x") == "sixteen-letters")
        #expect(NewDatabasePlan.prefix(forFolderNamed: "supercalifragilisticexpialidocious") == "supercalifragili")
    }

    @Test("a name with nothing usable in it falls back to a plain prefix")
    func prefixFallback() {
        #expect(NewDatabasePlan.prefix(forFolderNamed: "2024") == "beads")
        #expect(NewDatabasePlan.prefix(forFolderNamed: "日本語") == "beads")
        #expect(NewDatabasePlan.prefix(forFolderNamed: "") == "beads")
    }

    @Test("a plan made from a path takes its prefix from the last folder")
    func planFromPath() {
        let plan = NewDatabasePlan(projectPath: "/Users/ada/code/Tile Engine")
        #expect(plan.prefix == "tile-engine")
        #expect(plan.folderName == "Tile Engine")
    }

    @Test("the offer names the folder, the ids to expect, what bd will run and what it commits")
    func offerText() {
        let plan = NewDatabasePlan(projectPath: "/Users/ada/code/Tile Engine")
        let message = plan.offerMessage(command: "bd -C '/Users/ada/code/Tile Engine' init --prefix=tile-engine")
        #expect(plan.offerTitle == "Create a beads database in Tile Engine?")
        #expect(message.contains("tile-engine-"), "the user should see what ids will look like")
        #expect(message.contains("bd -C '/Users/ada/code/Tile Engine' init --prefix=tile-engine"))
        #expect(message.contains("commit"), "bd init commits its files to the repository; say so")
    }
}
