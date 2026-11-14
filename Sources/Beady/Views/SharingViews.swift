import BeadsCore
import BeadsPresentation
import SwiftUI

// Sharing (plan 0006): the toolbar's word, its popover, the Share Beads sheet and the Workspace
// Setup sheet. Every sentence and every choice comes from BeadsPresentation; these only draw.

/// The toolbar's one word about where the beads live, and the popover behind it.
struct SharingIndicator: View {
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let model: WorkspaceModel
    let ui: WorkspaceUI
    let run: (AppCommand) -> Void

    var body: some View {
        if let summary = model.sharingSummary {
            Button {
                ui.showsSharingPopover.toggle()
            } label: {
                SharingWord(summary: summary)
                    .foregroundStyle(summary.tone == .problem ? theme.blocked : theme.text)
            }
            .labelStyle(.titleAndIcon)
            .controlSize(.small)
            .help("Where these beads live besides this Mac, and whether that is up to date")
            // The word changing is the acknowledgement that a sync landed; a crossfade, which
            // Reduce Motion keeps.
            .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: summary.word)
            .popover(
                isPresented: Binding(get: { ui.showsSharingPopover }, set: { ui.showsSharingPopover = $0 }),
                arrowEdge: .bottom
            ) {
                SharingPopover(model: model, ui: ui, summary: summary, run: run)
                    .environment(\.theme, theme)
            }
        }
    }
}

/// The status word with its symbol. While bd works the symbol turns, which is the sign that
/// something is happening; Reduce Motion keeps it still, and the word "Syncing…" says it instead.
struct SharingWord: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let summary: SharingSummary

    var body: some View {
        Label {
            Text(summary.word)
        } icon: {
            Image(systemName: summary.symbol)
                .symbolEffect(.rotate, options: .repeat(.continuous), isActive: summary.isWorking && !reduceMotion)
        }
    }
}

/// Internal rather than private so the offscreen snapshots can render it without a toolbar.
struct SharingPopover: View {
    @Environment(\.theme) private var theme
    let model: WorkspaceModel
    let ui: WorkspaceUI
    let summary: SharingSummary
    let run: (AppCommand) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SharingWord(summary: summary)
                .font(.headline)
                .foregroundStyle(summary.tone == .problem ? theme.blocked : theme.text)

            Text(summary.detail)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

            if let remote = model.sharingState?.remote {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Shared through \(remote.name)", comment: "Sharing popover: the remote's name")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(remote.displayURL)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
            }

            if let notice = model.sharingNotice {
                SharingNotice(text: notice, isFailure: model.sharingNoticeIsFailure)
            }

            if let side = ui.confirmingConflictSide {
                confirmation(for: side)
            } else if !summary.buttons.isEmpty {
                HStack {
                    ForEach(Array(summary.buttons.enumerated()), id: \.offset) { _, action in
                        Button(action.title) { perform(action) }
                            // What can be started now: while a sync runs, only Stop.
                            .disabled(!summary.actions.contains(action) || !model.canEdit)
                            // The command is there for whoever wants it, and out of the way.
                            .help(model.command(for: action) ?? "")
                    }
                    // Always laid out, so the row is the same height working or not.
                    ProgressView()
                        .controlSize(.small)
                        .opacity(summary.isWorking ? 1 : 0)
                        .accessibilityHidden(!summary.isWorking)
                }
            }

            if model.sharingState?.offersSyncCadence == true {
                cadence
            }

            Divider()

            HStack {
                if let backup = model.backupSummary {
                    Label(backup, systemImage: model.backup.lastSync == nil ? "externaldrive.badge.exclamationmark" : "externaldrive.badge.checkmark")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .labelStyle(.titleAndIcon)
                }
                Spacer()
                Button("Workspace Setup…") { run(.workspaceSetup) }
            }
        }
        .padding(16)
        .frame(width: 400)
        // Its own height, always: a popover's window follows the content's ideal size.
        .fixedSize(horizontal: false, vertical: true)
        .background(theme.background)
    }

    /// How often this workspace syncs by itself (plan 0007), and one line on what that means.
    /// The line always takes two lines' room, so choosing doesn't resize the popover.
    private var cadence: some View {
        VStack(alignment: .leading, spacing: 4) {
            Picker(selection: Binding(get: { model.syncCadence }, set: { model.syncCadence = $0 })) {
                ForEach(SyncCadence.allCases) { cadence in
                    Text(cadence.title).tag(cadence)
                }
            } label: {
                Text("Sync", comment: "Sharing popover: label of the choice of how often to sync")
            }
            .pickerStyle(.menu)
            .fixedSize()
            .disabled(!model.canEdit)
            Text(model.autoSyncCaption)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2, reservesSpace: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Settling a conflict throws one side's version of the conflicted beads away, so it is
    /// asked twice, with the command (interaction rule 9: confirm on risk).
    @ViewBuilder
    private func confirmation(for side: ConflictSide) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(side == .mine
                ? "Keep this Mac's version of every bead in conflict? The remote's changes to those beads are discarded when this is sent."
                : "Take the remote's version of every bead in conflict? This Mac's changes to those beads are discarded.")
                .fixedSize(horizontal: false, vertical: true)
            if let command = model.command(for: .settleConflict(keeping: side)) {
                Text(command)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Button("Cancel") { ui.confirmingConflictSide = nil }
                    .keyboardShortcut(.cancelAction)
                Button(SharingAction.settleConflict(keeping: side).title, role: .destructive) {
                    ui.confirmingConflictSide = nil
                    Task { await model.settleConflict(keeping: side) }
                }
            }
        }
    }

    private func perform(_ action: SharingAction) {
        switch action {
        case .share: run(.shareBeads)
        case .sync: run(.syncNow)
        case .checkAgain: Task { await model.refreshSharing() }
        case .settleConflict(let side): ui.confirmingConflictSide = side
        case .stop: run(.stopSync)
        }
    }
}

/// What the last sharing action has to say: a failure in bd's own words, or the plain word that
/// a sync was stopped. Selectable, and never taller than the window can take.
private struct SharingNotice: View {
    @Environment(\.theme) private var theme
    let text: String
    var isFailure = true

    var body: some View {
        ScrollView {
            Label(text, systemImage: isFailure ? "exclamationmark.triangle.fill" : "stop.circle")
                .foregroundStyle(isFailure ? theme.blocked : theme.secondaryText)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: 140)
    }
}

/// Share Beads: the one question, what follows from the answer, and the commands. Nothing runs
/// until its button is pressed.
struct ShareBeadsSheet: View {
    @Environment(\.theme) private var theme
    let model: WorkspaceModel
    let ui: WorkspaceUI
    let run: (AppCommand) -> Void
    /// `State` as a plain DynamicProperty: Command Line Tools lack the @State macro plugin.
    private var showsMechanics = State(initialValue: false)

    init(model: WorkspaceModel, ui: WorkspaceUI, run: @escaping (AppCommand) -> Void) {
        self.model = model
        self.ui = ui
        self.run = run
    }

    private var plan: SharePlan { model.sharePlan(url: ui.shareURL, audience: ui.shareAudience) }

    var body: some View {
        let plan = plan
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Share Beads")
                    .font(.title3.weight(.semibold))
                Text("Who works on the beads in \(model.title)?", comment: "Share Beads sheet; the workspace's name")
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .top, spacing: 8) {
                ForEach(ShareAudience.allCases) { audience in
                    audienceCard(audience)
                }
            }

            if ui.shareAudience.shares {
                sharing(plan)
            } else {
                onlyMe
            }

            if let notice = model.sharingNotice {
                SharingNotice(text: notice, isFailure: model.sharingNoticeIsFailure)
            }

            HStack {
                if model.isSyncing {
                    ProgressView().controlSize(.small)
                    Text("Sending…", comment: "Share Beads sheet, while bd pushes").foregroundStyle(.secondary)
                }
                Spacer()
                Button(ui.shareAudience.shares ? "Cancel" : "Done") { ui.showsShareBeads = false }
                    .keyboardShortcut(.cancelAction)
                if ui.shareAudience.shares {
                    Button("Share Beads") {
                        Task {
                            if await model.share(plan) { ui.showsShareBeads = false }
                        }
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!plan.canShare || model.isSyncing || !model.canEdit)
                }
            }
        }
        .padding(20)
        .frame(width: 600)
        .background(theme.background)
    }

    private func audienceCard(_ audience: ShareAudience) -> some View {
        let isChosen = ui.shareAudience == audience
        return Button {
            ui.shareAudience = audience
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Image(systemName: audience.symbol)
                    .font(.title3)
                Text(audience.title)
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                Text(audience.blurb)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
            .background(Color.secondary.opacity(isChosen ? 0.14 : 0.06), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(isChosen ? theme.accent : Color.clear, lineWidth: 2))
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isChosen ? .isSelected : [])
    }

    @ViewBuilder
    private func sharing(_ plan: SharePlan) -> some View {
        if let remote = model.sharing?.remote {
            box("Where") {
                Text("\(remote.name), already set up for this database", comment: "Share Beads sheet; the remote's name")
                Text(remote.displayURL)
                    .font(.callout.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text("Where").font(.headline)
                TextField("Git URL or Dolt remote", text: Binding(get: { ui.shareURL }, set: { ui.shareURL = $0 }))
                    .textFieldStyle(.roundedBorder)
                    .font(.body.monospaced())
                Text(model.gitOrigin == nil
                    ? "This repository has no git origin. Enter a git URL, or any Dolt remote: DoltHub, S3, GCS, Azure or a folder."
                    : "The repository's own git origin, which is where bd puts beads by default. Any Dolt remote works too: DoltHub, S3, GCS, Azure or a folder.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }

        if let problem = plan.problem {
            Label(problem, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(theme.pinned)
                .fixedSize(horizontal: false, vertical: true)
        }

        if !plan.consequences.isEmpty {
            box("What sharing means") {
                ForEach(Array(plan.consequences.enumerated()), id: \.offset) { index, line in
                    // The first is who can read the beads: the one that can't be taken back.
                    Label(line, systemImage: index == 0 ? "eye" : "circle.fill")
                        .labelStyle(ConsequenceLabelStyle(isLead: index == 0, tint: theme.pinned))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }

        if !plan.steps.isEmpty {
            DisclosureGroup(isExpanded: showsMechanics.projectedValue) {
                box("bd will run") {
                    ForEach(model.commands(for: plan), id: \.self) { command in
                        Text(command)
                            .font(.callout.monospaced())
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.top, 6)
            } label: {
                Text("How this will be done", comment: "Disclosure on the Share Beads sheet hiding the bd commands")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var onlyMe: some View {
        box("Nothing is shared") {
            Text("The beads stay in this Mac's copy of the repository. A backup is the way to keep a second copy.")
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                if let backup = model.backupSummary {
                    Text(backup.prefix(1).uppercased() + backup.dropFirst()).foregroundStyle(.secondary)
                }
                Spacer()
                Button(model.backup.isConfigured ? "Back Up Now" : "Choose Backup Folder…") {
                    run(model.backup.isConfigured ? .backUpNow : .setUpBackup)
                }
                .disabled(model.isBackingUp)
            }
        }
    }

    private func box<Content: View>(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            VStack(alignment: .leading, spacing: 8, content: content)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        }
    }
}

/// A consequence line: an eye for who can read, a small dot for the rest.
private struct ConsequenceLabelStyle: LabelStyle {
    let isLead: Bool
    let tint: Color

    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            configuration.icon
                .font(isLead ? .body : .system(size: 5))
                .foregroundStyle(isLead ? tint : Color.secondary)
                .frame(width: 18)
            configuration.title
                .fontWeight(isLead ? .medium : .regular)
        }
    }
}

/// Workspace Setup: what is true of this workspace, a row a fact, each with at most one button.
struct WorkspaceSetupSheet: View {
    @Environment(\.theme) private var theme
    let model: WorkspaceModel
    let ui: WorkspaceUI
    let run: (AppCommand) -> Void
    /// `State` as a plain DynamicProperty: Command Line Tools lack the @State macro plugin.
    private var showsMechanics = State(initialValue: false)

    init(model: WorkspaceModel, ui: WorkspaceUI, run: @escaping (AppCommand) -> Void) {
        self.model = model
        self.ui = ui
        self.run = run
    }

    private var rows: [SetupRow] {
        WorkspaceSetupRows.rows(
            sharing: model.sharingState, isSyncing: model.isSyncing,
            backup: model.backup, backupSummary: model.backupSummary ?? "",
            setup: model.setup, beadCount: model.snapshot?.issues.count ?? 0
        )
    }

    private var factsMaxHeight: CGFloat {
        let screen = (NSApp.keyWindow?.screen ?? NSScreen.main)?.visibleFrame.height
        return WorkspaceSetupRows.factsMaxHeight(visibleScreenHeight: screen.map(Double.init))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Workspace Setup")
                    .font(.title3.weight(.semibold))
                Text("Where the beads of \(model.title) are kept, shared and backed up, as bd reports it.", comment: "Workspace Setup sheet, under its title; the workspace's name")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // The facts scroll and the buttons don't: however much bd reports, Done stays in
            // reach. `fixedSize` lets the scroll view be as short as its content.
            ScrollView {
                facts
            }
            .frame(maxHeight: factsMaxHeight)
            .fixedSize(horizontal: false, vertical: true)

            HStack {
                if model.isSyncing { ProgressView().controlSize(.small) }
                Spacer()
                Button("Check Again") {
                    Task {
                        await model.refreshSetup()
                        await model.refreshSharing()
                    }
                }
                .disabled(model.isSyncing)
                Button("Done") { ui.showsWorkspaceSetup = false }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 620)
        .background(theme.background)
        // Esc closes it too; Return is Done's.
        .background {
            Button("Done") { ui.showsWorkspaceSetup = false }
                .keyboardShortcut(.cancelAction)
                .opacity(0)
                .accessibilityHidden(true)
        }
        .task {
            await model.refreshSetup()
            await model.refreshSharing()
        }
    }

    private var facts: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    if index > 0 { Divider() }
                    rowView(row)
                }
            }
            .padding(.horizontal, 10)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))

            if let notice = model.sharingNotice {
                SharingNotice(text: notice, isFailure: model.sharingNoticeIsFailure)
            }

            DisclosureGroup(isExpanded: showsMechanics.projectedValue) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Self.sources, id: \.self) { command in
                        Text(command)
                            .font(.callout.monospaced())
                            .textSelection(.enabled)
                    }
                    Text("Beady reads these and nothing else: it never opens the database or Dolt's files itself.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 4)
                }
                .padding(.top, 6)
            } label: {
                Text("Where this comes from", comment: "Disclosure on the Workspace Setup sheet listing the bd commands it reads")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The read-only commands the rows come from, as they would be typed in the repository.
    private static let sources = [
        "bd context --json",
        "bd dolt remote list --json",
        "bd federation status --json",
        "bd worktree list --json",
        "bd hooks list --json",
        "bd backup status --json",
    ]

    private func rowView(_ row: SetupRow) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol(for: row.level))
                .foregroundStyle(color(for: row.level))
                .frame(width: 20)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title).font(.headline)
                Text(row.detail)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if let action = row.action {
                Button(action.title) { perform(action) }
                    // Stop is the one thing to press while a sync runs.
                    .disabled(action == .sharing(.stop) ? false : (model.isSyncing || model.isBackingUp || !model.canEdit))
            }
        }
        .padding(.vertical, 10)
    }

    private func symbol(for level: SetupRow.Level) -> String {
        switch level {
        case .good: "checkmark.circle.fill"
        case .info: "info.circle"
        case .attention: "exclamationmark.triangle.fill"
        }
    }

    private func color(for level: SetupRow.Level) -> Color {
        switch level {
        case .good: theme.color(.done)
        case .info: theme.secondaryText
        case .attention: theme.pinned
        }
    }

    private func perform(_ action: SetupRow.Action) {
        switch action {
        case .sharing(.share): run(.shareBeads)
        case .sharing(.sync): run(.syncNow)
        case .sharing(.checkAgain): Task { await model.refreshSharing() }
        case .sharing(.stop): run(.stopSync)
        case .sharing(.settleConflict):
            // The decision is made in the popover, where it is asked twice.
            ui.showsWorkspaceSetup = false
            ui.showsSharingPopover = true
        case .setUpBackup: run(.setUpBackup)
        case .backUpNow: run(.backUpNow)
        }
    }
}
