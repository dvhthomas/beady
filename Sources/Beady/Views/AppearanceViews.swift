import AppKit
import BeadsCore
import BeadsPresentation
import SwiftUI

/// ⌘T: arrow through the themes and watch the app repaint as you go. Apply keeps the one you
/// stopped on; Escape or Cancel puts back what you had.
struct ThemePickerView: View {
    @Environment(\.theme) private var current
    @Environment(\.colorScheme) private var colorScheme
    let themes: ThemeStore
    let onClose: () -> Void
    /// `State` as plain DynamicProperties: Command Line Tools lack the @State macro plugin.
    private var highlighted = State(initialValue: 0)
    private var monitor = State<Any?>(initialValue: nil)

    init(themes: ThemeStore, onClose: @escaping () -> Void) {
        self.themes = themes
        self.onClose = onClose
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollViewReader { scroller in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        section(.dark, ThemeSelection.catalog.filter { $0.appearance == .dark })
                        section(.light, ThemeSelection.catalog.filter { $0.appearance == .light })
                        if themes.systemWantsHighContrast {
                            Label(
                                "macOS has Increase Contrast turned on, so Beady is using its high-contrast theme whatever you pick here.",
                                systemImage: "eye"
                            )
                            .font(.caption)
                            .foregroundStyle(current.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(16)
                }
                .onChange(of: highlighted.wrappedValue) {
                    scroller.scrollTo(highlighted.wrappedValue, anchor: .center)
                }
            }
        }
        .frame(width: 520, height: 540)
        .background(current.background)
        .onAppear(perform: start)
        .onDisappear(perform: stopWatchingKeys)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Theme").font(.headline)
                Text(explanation)
                    .font(.caption)
                    .foregroundStyle(current.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Picker("Appearance", selection: appearance) {
                ForEach(AppearancePreference.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            Button("Cancel", action: cancel)
                .keyboardShortcut(.cancelAction)
            VStack(alignment: .trailing, spacing: 2) {
                Button("Apply", action: apply)
                    .keyboardShortcut(.defaultAction)
                if let hint = applyHint {
                    Text(hint)
                        .font(.caption2)
                        .foregroundStyle(current.secondaryText)
                }
            }
        }
        .padding(14)
    }

    /// Each side says when it's used, because "System" plus a light theme is otherwise a riddle.
    private func section(_ appearance: Theme.Appearance, _ options: [Theme]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(appearance == .dark ? "Dark" : "Light")
                    .font(.subheadline.weight(.semibold))
                Text("· \(sectionUsage(appearance))")
                    .font(.caption)
            }
            .foregroundStyle(current.secondaryText)
            ForEach(options) { theme in
                let index = ThemeSelection.catalog.firstIndex { $0.name == theme.name } ?? 0
                Button {
                    highlight(index)
                } label: {
                    ThemeSwatch(theme: theme, isSelected: index == highlighted.wrappedValue)
                }
                .buttonStyle(.plain)
                .id(index)
            }
        }
    }

    private var appearance: Binding<AppearancePreference> {
        Binding(
            get: { themes.appearance },
            set: { preference in
                // Switching light/dark here is a choice too, so it drops any preview.
                themes.cancelPreview()
                themes.appearance = preference
                highlighted.wrappedValue = themes.selection.startingIndex(systemIsDark: colorScheme == .dark)
            }
        )
    }

    /// What the Appearance setting means for the two lists below it.
    private var explanation: String {
        switch themes.appearance {
        case .system: "↑↓ to try them on. Appearance follows macOS, so your dark and light choices are both used — each when macOS switches to it."
        case .dark: "↑↓ to try them on. Appearance is pinned to Dark, so the dark choice is what you'll see."
        case .light: "↑↓ to try them on. Appearance is pinned to Light, so the light choice is what you'll see."
        }
    }

    private func sectionUsage(_ appearance: Theme.Appearance) -> String {
        switch themes.appearance {
        case .system: appearance == .dark ? "when macOS is dark" : "when macOS is light"
        case .dark: appearance == .dark ? "in use" : "unused while Appearance is Dark"
        case .light: appearance == .light ? "in use" : "unused while Appearance is Light"
        }
    }

    /// Says what Apply will actually do when the highlighted theme isn't the one in use.
    private var applyHint: String? {
        guard ThemeSelection.catalog.indices.contains(highlighted.wrappedValue) else { return nil }
        let theme = ThemeSelection.catalog[highlighted.wrappedValue]
        let usage = themes.selection.usage(of: theme, systemIsDark: colorScheme == .dark)
        return usage == .inUse ? nil : usage.title
    }

    private func start() {
        highlighted.wrappedValue = themes.selection.startingIndex(systemIsDark: colorScheme == .dark)
        startWatchingKeys()
    }

    private func highlight(_ index: Int) {
        highlighted.wrappedValue = index
        themes.preview(ThemeSelection.catalog[index])
    }

    private func apply() {
        themes.commitPreview()
        stopWatchingKeys()
        onClose()
    }

    private func cancel() {
        themes.cancelPreview()
        stopWatchingKeys()
        onClose()
    }

    /// Arrow keys through a sheet that has no focused list: the same local monitor the command
    /// palette uses, for the same reason.
    private func startWatchingKeys() {
        guard monitor.wrappedValue == nil else { return }
        let highlighted = highlighted.projectedValue
        let themes = themes
        monitor.wrappedValue = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { @MainActor event in
            switch event.keyCode {
            case 126, 125: // up, down
                let next = ThemeSelection.step(highlighted.wrappedValue, by: event.keyCode == 126 ? -1 : 1)
                highlighted.wrappedValue = next
                themes.preview(ThemeSelection.catalog[next])
                return nil
            default:
                return event
            }
        }
    }

    private func stopWatchingKeys() {
        if let monitor = monitor.wrappedValue { NSEvent.removeMonitor(monitor) }
        monitor.wrappedValue = nil
    }
}

/// A miniature of a row in that theme: the point is to see the colours doing their job.
private struct ThemeSwatch: View {
    let theme: Theme
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 4) {
                ForEach(StatusCategory.allCases, id: \.self) { category in
                    Circle().fill(Color(theme.colors.category(category))).frame(width: 12, height: 12)
                }
                Circle().fill(Color(theme.colors.blocked)).frame(width: 12, height: 12)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(theme.name)
                    .foregroundStyle(Color(theme.colors.text))
                Text(theme.isHighContrast ? "Maximum contrast, for easier reading" : "beady-1a2  Freeform positioning")
                    .font(.caption)
                    .foregroundStyle(Color(theme.colors.secondaryText))
            }
            Spacer()
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color(theme.colors.accent))
            }
        }
        .padding(10)
        .background(Color(theme.colors.surface), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color(isSelected ? theme.colors.accent : theme.colors.border), lineWidth: isSelected ? 2 : 1)
        )
    }
}

/// ⌘, — the standard place for settings, holding the same choices plus text size.
struct SettingsView: View {
    @Environment(\.theme) private var theme
    let themes: ThemeStore

    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Mode", selection: binding(\.appearance)) {
                    ForEach(AppearancePreference.allCases) { Text($0.title).tag($0) }
                }
                Picker("Dark theme", selection: binding(\.darkThemeName)) {
                    ForEach(Theme.all.filter { $0.appearance == .dark }) { Text($0.name).tag($0.name) }
                }
                Picker("Light theme", selection: binding(\.lightThemeName)) {
                    ForEach(Theme.all.filter { $0.appearance == .light }) { Text($0.name).tag($0.name) }
                }
            }
            Section("Sidebar") {
                Picker("Style", selection: binding(\.sidebarStyle)) {
                    ForEach(SidebarStyle.allCases) { Text($0.title).tag($0) }
                }
                Text(themes.sidebarStyle.detail)
                    .font(.caption)
                    .foregroundStyle(theme.secondaryText)
            }
            Section("Reading") {
                Picker("Text size", selection: binding(\.textSize)) {
                    ForEach(TextSize.allCases) { Text($0.title).tag($0) }
                }
                Text("macOS's Increase Contrast setting overrides the theme with Beady's high-contrast one.")
                    .font(.caption)
                    .foregroundStyle(theme.secondaryText)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(theme.background)
        .frame(width: 420)
    }

    private func binding<Value>(_ keyPath: ReferenceWritableKeyPath<ThemeStore, Value>) -> Binding<Value> {
        Binding(get: { themes[keyPath: keyPath] }, set: { themes[keyPath: keyPath] = $0 })
    }
}


extension View {
    /// Resolves the chosen theme against what macOS is currently doing, puts it in the
    /// environment, and scales the interface to the chosen text size.
    func themed(_ themes: ThemeStore) -> some View {
        modifier(Themed(themes: themes))
    }
}

private struct Themed: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    let themes: ThemeStore

    func body(content: Content) -> some View {
        let theme = themes.theme(for: colorScheme)
        content
            .environment(\.sidebarStyle, themes.sidebarStyle)
            .onAppear { themes.paintWindows(theme.colors.background) }
            .onChange(of: theme) { themes.paintWindows(theme.colors.background) }
            .environment(\.theme, theme)
            .tint(theme.accent)
            .foregroundStyle(theme.text)
            .background(theme.background)
            .dynamicTypeSize(dynamicType)
            .preferredColorScheme(preferredScheme)
    }

    /// macOS has no Dynamic Type of its own, so the app maps its text-size setting onto the
    /// same scale SwiftUI already understands.
    private var dynamicType: DynamicTypeSize {
        switch themes.textSize {
        case .small: .small
        case .default: .medium
        case .large: .xLarge
        case .extraLarge: .accessibility1
        }
    }

    /// Follows the preview as well as the setting: trying a light theme while the app is set to
    /// Dark used to leave AppKit drawing its dark controls — grey-on-cream text in the picker's
    /// own header — because the window's appearance said one thing and the background another.
    private var preferredScheme: ColorScheme? {
        switch themes.selection.effectiveAppearance {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}
