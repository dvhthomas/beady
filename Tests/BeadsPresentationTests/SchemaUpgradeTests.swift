import BeadsCore
import BeadsPresentation
import Foundation
import Testing

@MainActor
@Suite("A database on a different schema from this bd")
struct SchemaUpgradeTests {
    let behind = SchemaMismatch(.behind, database: 53, bd: 66)
    let ahead = SchemaMismatch(.ahead, database: 66, bd: 53)

    /// A store whose first load fails with `mismatch` and whose later loads succeed.
    func makeModel(_ mismatch: SchemaMismatch, allowsWriting: Bool = true) -> (WorkspaceModel, StubStore) {
        let store = StubStore([.failure(mismatch), .success(IssueSnapshot(issues: [makeIssue("demo-1")]))])
        return (WorkspaceModel(title: "demo", store: store, allowsWriting: allowsWriting, now: { t0 }), store)
    }

    @Test("a database behind this bd is recognised, and nothing is changed on its own")
    func recognisesBehind() async {
        let (model, store) = makeModel(behind)
        await model.load()
        #expect(model.schemaMismatch == behind)
        #expect(model.offersSchemaUpgrade)
        #expect(!model.offersReadingPastSchemaSkew, "bd can't read past this one: its own queries fail on the old schema")
        #expect(!model.canEdit)
        #expect(store.upgrades == 0 && store.copies.isEmpty)
        #expect(CommandCatalog.all(for: model).contains(.upgradeDatabase))
    }

    @Test("the failure reads as an explanation, not bd's internals")
    func message() async {
        let (model, _) = makeModel(behind)
        await model.load()
        guard case .failed(let message) = model.loadState else { Testing.Issue.record("expected a failure"); return }
        #expect(message.contains("v53") && message.contains("v66"))
        #expect(!message.contains("BD_IGNORE_SCHEMA_SKEW"))
    }

    @Test("upgrading copies the database first, then upgrades it, then loads")
    func upgradeWithCopy() async {
        let (model, store) = makeModel(behind)
        await model.load()
        #expect(await model.upgradeDatabase(copyingTo: "/Backups"))
        #expect(store.copies.map(\.folder) == ["/Backups"])
        #expect(store.copies.map(\.schema) == [53], "the copy is named for the schema it holds")
        #expect(store.upgrades == 1)
        #expect(model.loadState == .loaded)
        #expect(model.schemaMismatch == nil)
        #expect(model.preUpgradeCopy == "/Backups/demo-beads-v53")
        #expect(model.schemaUpgrade == .idle)
        #expect(model.canEdit)
    }

    @Test("without a copy, it just upgrades")
    func upgradeWithoutCopy() async {
        let (model, store) = makeModel(behind)
        await model.load()
        #expect(await model.upgradeDatabase(copyingTo: nil))
        #expect(store.copies.isEmpty)
        #expect(store.upgrades == 1)
        #expect(model.preUpgradeCopy == nil)
    }

    @Test("if the copy fails, nothing is upgraded")
    func copyFails() async {
        let (model, store) = makeModel(behind)
        store.copyFailure = LoadFailure()
        await model.load()
        #expect(!(await model.upgradeDatabase(copyingTo: "/Backups")))
        #expect(store.upgrades == 0)
        guard case .failed(let message, let needsDecision) = model.schemaUpgrade else { Testing.Issue.record("expected a failure"); return }
        #expect(message.contains("Nothing was upgraded"))
        #expect(!needsDecision)
        #expect(model.schemaMismatch == behind, "still waiting for an upgrade")
    }

    @Test("bd refusing to migrate a shared remote is shown as a decision, not retried")
    func refused() async {
        let (model, store) = makeModel(behind)
        store.upgradeFailure = SchemaUpgradeRefused(message: "refusing to migrate a remote-backed database (v53 -> v66) (#4259)")
        await model.load()
        #expect(!(await model.upgradeDatabase(copyingTo: nil)))
        #expect(model.schemaUpgrade == .failed("refusing to migrate a remote-backed database (v53 -> v66) (#4259)", needsDecision: true))
        #expect(store.upgrades == 1)
    }

    @Test("bd's version is checked again after an upgrade, so the journal offer reflects the upgraded database")
    func rechecksJournal() async {
        let (model, store) = makeModel(behind)
        await model.load()
        await model.upgradeDatabase(copyingTo: nil)
        #expect(store.journalStatusChecks == 2)
    }

    @Test("the confirmation lists the copy and the exact bd command")
    func preview() async {
        let (model, _) = makeModel(behind)
        await model.load()
        #expect(model.schemaUpgradeSteps(copyingTo: "/Backups") == [
            "Copy .beads to /Backups",
            "bd migrate schema",
        ])
        #expect(model.schemaUpgradeSteps(copyingTo: nil) == ["bd migrate schema"])
    }

    @Test("a window that can't write can't upgrade")
    func readOnlyWindow() async {
        let (model, store) = makeModel(behind, allowsWriting: false)
        await model.load()
        #expect(!model.offersSchemaUpgrade)
        #expect(!(await model.upgradeDatabase(copyingTo: nil)))
        #expect(store.upgrades == 0)
    }

    @Test("a database ahead of this bd can't be upgraded here, but can be read without editing")
    func ahead() async {
        let (model, store) = makeModel(ahead)
        await model.load()
        #expect(model.schemaMismatch == ahead)
        #expect(!model.offersSchemaUpgrade)
        #expect(model.offersReadingPastSchemaSkew)
        #expect(CommandCatalog.all(for: model).contains(.readPastSchemaSkew))
        #expect(!CommandCatalog.all(for: model).contains(.upgradeDatabase))

        await model.readPastSchemaSkew()
        #expect(model.loadState == .loaded)
        #expect(model.isReadingPastSchemaSkew)
        #expect(!model.canEdit, "writing with an older bd to a newer schema is exactly what bd guards against")
        #expect(store.skewFlags == [false, true])

        store.setToken("t1")
        await model.refreshIfChanged()
        #expect(store.skewFlags == [false, true, true], "it keeps reading that way while the window is open")
    }

    @Test("an ordinary failure isn't mistaken for a schema problem")
    func otherFailure() async {
        let store = StubStore([.failure(LoadFailure())])
        let model = WorkspaceModel(title: "demo", store: store, now: { t0 })
        await model.load()
        #expect(model.schemaMismatch == nil)
        #expect(!model.offersSchemaUpgrade && !model.offersReadingPastSchemaSkew)
    }
}
