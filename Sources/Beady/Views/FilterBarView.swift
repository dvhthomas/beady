import BeadsCore
import BeadsPresentation
import SwiftUI

/// The view header, as in Linear: Filter menu and chips on the left, Display options on the right.
struct FilterBar: View {
    @Environment(\.theme) private var theme
    @Bindable var model: WorkspaceModel
    let ui: WorkspaceUI
    let run: (AppCommand) -> Void

    init(model: WorkspaceModel, ui: WorkspaceUI, run: @escaping (AppCommand) -> Void) {
        self.model = model
        self.ui = ui
        self.run = run
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                if let focused = model.focusedIssue {
                    FocusBreadcrumb(issue: focused) { model.unfocus() }
                }

                Button {
                    ui.showsFilterMenu = true
                } label: {
                    Label("Filter", systemImage: "line.3.horizontal.decrease")
                }
                .keyboardShortcut(plainKey(.addFilter))
                .help("Add a filter (F)")
                .popover(isPresented: binding(\.showsFilterMenu), arrowEdge: .bottom) {
                    FilterMenu(model: model)
                }

                // Bounded: a ScrollView is greedy vertically, and would take half the pane
                // whenever the content below it (an empty state) doesn't claim the space.
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(model.filterChips) { chip in
                            FilterChipView(model: model, chip: chip)
                        }
                    }
                    .padding(.vertical, 1)
                }
                .frame(height: 26)

                if !model.filter.rules.isEmpty {
                    Button("Clear") { model.clearFilters() }
                        .buttonStyle(.link)
                        .help("Remove this view's filters")
                }

                if let error = model.refreshError {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(theme.pinned)
                        .help("Refresh failed; showing the last good data.\n\(error)")
                }

                layoutSwitcher

                Button {
                    ui.showsDisplayOptions = true
                } label: {
                    Label("Display", systemImage: "slider.horizontal.3")
                }
                .keyboardShortcut(plainKey(.displayOptions))
                .help("Display options (⇧V)")
                .popover(isPresented: binding(\.showsDisplayOptions), arrowEdge: .bottom) {
                    DisplayOptionsView(model: model, columns: ui.columns)
                }
            }
            .controlSize(.small)
            .fixedSize(horizontal: false, vertical: true)
            .background(shortcuts)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            Divider()
        }
    }

    /// The layout is the one display choice worth a click rather than a menu; the Display
    /// popover keeps the same picker for people who go looking there.
    private var layoutSwitcher: some View {
        Picker("Layout", selection: $model.layout) {
            ForEach(WorkspaceModel.Layout.allCases) { layout in
                Image(systemName: DisplayText.layoutSymbol(layout))
                    .help(DisplayText.layout(layout))
                    .tag(layout)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
        .help("List, Tree or Board (⌘1, ⌘2, ⌘3)")
    }

    /// Single-key shortcuts live on real (invisible) buttons rather than menu items, so they
    /// don't swallow the same letters while you're typing in a field.
    private var shortcuts: some View {
        ZStack {
            Button("Search This View") { run(.focusSearch) }
                .keyboardShortcut(plainKey(.focusSearch))
            Button("Keyboard Shortcuts") { run(.showShortcuts) }
                .keyboardShortcut(plainKey(.showShortcuts))
        }
        .opacity(0)
        .frame(width: 0, height: 0)
        .allowsHitTesting(false)
    }

    /// A command's bare key. It stands down while a field has the keyboard or a sheet is open —
    /// otherwise typing "f" into a title would open the filter menu behind it. The menu bar's ⌘
    /// equivalents keep working throughout.
    private func plainKey(_ command: AppCommand) -> KeyboardShortcut? {
        ui.isSearchFocused || ui.isSheetOpen ? nil : command.plainShortcut
    }

    private func binding(_ keyPath: ReferenceWritableKeyPath<WorkspaceUI, Bool>) -> Binding<Bool> {
        Binding(get: { ui[keyPath: keyPath] }, set: { ui[keyPath: keyPath] = $0 })
    }
}

/// Shows which bead the view is focused on, and gets you back out of it.
private struct FocusBreadcrumb: View {
    @Environment(\.theme) private var theme
    let issue: Issue
    let onClear: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "scope")
            Text(issue.title)
                .lineLimit(1)
                .frame(maxWidth: 220, alignment: .leading)
            Button(action: onClear) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .help("Back to the view you came from")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(theme.accent.opacity(0.18), in: Capsule())
        .help("\(issue.id.rawValue): everything under this bead")
    }
}

/// Pick a property, then tick values. The popover stays open, so several values take several clicks.
struct FilterMenu: View {
    let model: WorkspaceModel
    private var field: State<FilterField?>
    private var query = State(initialValue: "")

    init(model: WorkspaceModel, initialField: FilterField? = nil) {
        self.model = model
        field = State(initialValue: initialField)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                if field.wrappedValue != nil {
                    Button {
                        field.wrappedValue = nil
                        query.wrappedValue = ""
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .buttonStyle(.borderless)
                    .help("Back to properties")
                }
                TextField(prompt, text: query.projectedValue)
                    .textFieldStyle(.plain)
            }
            .padding(10)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let field = field.wrappedValue {
                        FilterValuesList(model: model, field: field, query: query.wrappedValue)
                    } else {
                        ForEach(fields) { candidate in
                            Button {
                                field.wrappedValue = candidate
                                query.wrappedValue = ""
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: FilterStyle.symbol(for: candidate))
                                        .frame(width: 18)
                                        .foregroundStyle(.secondary)
                                    Text(DisplayText.field(candidate))
                                    Spacer()
                                    if model.filter.rule(for: candidate) != nil {
                                        Image(systemName: "checkmark").foregroundStyle(.tint)
                                    }
                                    Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(maxHeight: 380)
        }
        .frame(width: 300)
    }

    private var prompt: String {
        field.wrappedValue.map { "Filter \(DisplayText.field($0).lowercased())…" } ?? "Filter by…"
    }

    private var fields: [FilterField] {
        let text = query.wrappedValue.trimmingCharacters(in: .whitespaces)
        return FilterField.allCases.filter { text.isEmpty || DisplayText.field($0).localizedCaseInsensitiveContains(text) }
    }
}

/// Checkboxes for one property's values, with how many issues each would show.
struct FilterValuesList: View {
    let model: WorkspaceModel
    let field: FilterField
    var query: String = ""

    var body: some View {
        let text = query.trimmingCharacters(in: .whitespaces)
        let options = model.filterOptions(for: field).filter { text.isEmpty || $0.title.localizedCaseInsensitiveContains(text) }
        if options.isEmpty {
            Text("Nothing to filter by in this view")
                .foregroundStyle(.secondary)
                .padding(10)
        }
        ForEach(options) { option in
            HStack(spacing: 8) {
                Toggle(option.title, isOn: Binding(
                    get: { option.isSelected },
                    set: { _ in model.toggleFilterValue(option.value, in: field) }
                ))
                .toggleStyle(.checkbox)
                .lineLimit(1)
                Spacer(minLength: 12)
                Text("\(option.count)")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .opacity(option.count == 0 && !option.isSelected ? 0.55 : 1)
        }
    }
}

/// `field · operator · values · ✕`. The operator is a menu; the values open the checkbox list.
struct FilterChipView: View {
    let model: WorkspaceModel
    let chip: FilterChipModel
    /// `State` as a plain DynamicProperty: Command Line Tools lack the @State macro plugin.
    private var showsValues = State(initialValue: false)

    init(model: WorkspaceModel, chip: FilterChipModel) {
        self.model = model
        self.chip = chip
    }

    var body: some View {
        HStack(spacing: 0) {
            Text(chip.fieldTitle)
                .padding(.horizontal, 7)
            separator
            Menu {
                ForEach(chip.operators) { choice in
                    Button {
                        model.setFilterOperator(choice.op, for: chip.field)
                    } label: {
                        if choice.isSelected {
                            Label(choice.title, systemImage: "checkmark")
                        } else {
                            Text(choice.title)
                        }
                    }
                }
            } label: {
                Text(chip.operatorTitle).foregroundStyle(.secondary)
            }
            .menuStyle(.button)
            .buttonStyle(.borderless)
            .menuIndicator(.hidden)
            .fixedSize()
            .padding(.horizontal, 7)
            .disabled(chip.operators.count < 2)
            if !chip.valuesTitle.isEmpty {
                separator
                Button {
                    showsValues.wrappedValue = true
                } label: {
                    Text(chip.valuesTitle).lineLimit(1)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 7)
                .popover(isPresented: showsValues.projectedValue, arrowEdge: .bottom) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            FilterValuesList(model: model, field: chip.field)
                        }
                        .padding(.vertical, 6)
                    }
                    .frame(width: 280)
                    .frame(maxHeight: 380)
                }
            }
            separator
            Button {
                model.removeFilter(chip.field)
            } label: {
                Image(systemName: "xmark").font(.caption2.weight(.semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .help("Remove this filter")
        }
        .font(.callout)
        .padding(.vertical, 3)
        .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.secondary.opacity(0.25)))
    }

    private var separator: some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.25))
            .frame(width: 1, height: 14)
    }
}

struct DisplayOptionsView: View {
    @Environment(\.theme) private var theme
    @Bindable var model: WorkspaceModel
    let columns: ColumnLayout

    var body: some View {
        Form {
            Picker("Layout", selection: $model.layout) {
                ForEach(WorkspaceModel.Layout.allCases) { layout in
                    Label(DisplayText.layout(layout), systemImage: DisplayText.layoutSymbol(layout)).tag(layout)
                }
            }
            .pickerStyle(.segmented)
            Picker("Grouping", selection: $model.grouping) {
                ForEach(IssueGrouping.allCases) { grouping in
                    Text(DisplayText.grouping(grouping)).tag(grouping)
                }
            }
            .disabled(model.layout == .tree)
            Picker("Ordering", selection: $model.ordering) {
                ForEach(IssueSort.allCases) { sort in
                    Text(DisplayText.sort(sort)).tag(sort)
                }
            }
            if model.layout == .list {
                Section("Columns") {
                    ForEach(ListColumn.allCases) { column in
                        Toggle(column.title(for: model.ordering), isOn: Binding(
                            get: { columns.isVisible(column) },
                            set: { columns.setVisible(column, $0) }
                        ))
                        .disabled(column.isAlwaysVisible)
                    }
                    Button("Reset Columns") { columns.reset() }
                        .help("Back to the starting widths and columns")
                }
            }
            Text("Saved with this view. Other views keep their own.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(theme.background)
        .frame(width: 340)
    }
}

enum FilterStyle {
    static func symbol(for field: FilterField) -> String {
        switch field {
        case .status: "circle.lefthalf.filled"
        case .priority: "exclamationmark.3"
        case .type: "square.grid.2x2"
        case .assignee: "person"
        case .labels: "tag"
        case .blocked: "exclamationmark.octagon"
        case .parent: "square.stack.3d.up"
        case .updated: "clock.arrow.circlepath"
        case .closed: "checkmark.circle"
        }
    }
}
