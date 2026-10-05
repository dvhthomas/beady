import BeadsCore
import BeadsPresentation
import SwiftUI

/// Shown in place of the list when bd won't read the database because its schema differs from
/// bd's own. It explains which way round the difference is and offers what fits it: an upgrade
/// for a database older than this bd, a read-only look for one a newer bd has upgraded. Nothing
/// is changed until the user chooses.
struct SchemaMismatchView: View {
    let mismatch: SchemaMismatch
    let model: WorkspaceModel
    let ui: WorkspaceUI
    let run: (AppCommand) -> Void

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: mismatch.direction == .behind ? "arrow.up.circle" : "clock.arrow.circlepath")
        } description: {
            Text(explanation)
        } actions: {
            VStack(spacing: 12) {
                actions
                failure
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var title: String {
        mismatch.direction == .behind
            ? "This database needs upgrading for your bd"
            : "This database is newer than your bd"
    }

    private var explanation: String {
        switch mismatch.direction {
        case .behind:
            "It was last written by an older bd (schema v\(mismatch.databaseVersion)). Your bd needs v\(mismatch.bdVersion) and can't read it until it's upgraded.\n\nThe upgrade is one-way: any older bd still using this workspace, such as an agent, CI or another Mac, won't open it afterwards."
        case .ahead:
            "A newer bd has upgraded it to schema v\(mismatch.databaseVersion); yours understands up to v\(mismatch.bdVersion). Update bd to work with it, or look at it read-only for now."
        }
    }

    @ViewBuilder
    private var actions: some View {
        let busy = model.schemaUpgrade == .upgrading
        if model.offersSchemaUpgrade {
            Toggle("Copy the database to a folder first", isOn: copiesFirst)
                .toggleStyle(.checkbox)
                .disabled(busy)
            HStack {
                Button("Upgrade Database…") { run(.upgradeDatabase) }
                    .buttonStyle(.borderedProminent)
                    .disabled(busy)
                Button("Try Again") { Task { await model.load() } }
                    .disabled(busy)
            }
            if busy { ProgressView().controlSize(.small) }
        } else if model.offersReadingPastSchemaSkew {
            HStack {
                Button("Open Read-Only") { run(.readPastSchemaSkew) }
                    .buttonStyle(.borderedProminent)
                Button("Try Again") { Task { await model.load() } }
            }
        } else {
            Button("Try Again") { Task { await model.load() } }
        }
    }

    @ViewBuilder
    private var failure: some View {
        if case .failed(let message, let needsDecision) = model.schemaUpgrade {
            VStack(spacing: 6) {
                Text(message)
                    .foregroundStyle(.red)
                if needsDecision {
                    Text("This database is shared, so bd leaves the upgrade to you. Run `bd migrate --inspect` in a terminal in this project to see the options.")
                        .foregroundStyle(.secondary)
                }
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: 520)
            .textSelection(.enabled)
        }
    }

    private var copiesFirst: Binding<Bool> {
        Binding(get: { ui.copiesDatabaseBeforeUpgrade }, set: { ui.copiesDatabaseBeforeUpgrade = $0 })
    }
}
