import BeadsCore
import BeadsPresentation
import SwiftUI

/// ⌘T: pick a theme, with a swatch of what it does to a row so the choice is visible before
/// it's made.
struct ThemePickerView: View {
    @Environment(\.theme) private var current
    let themes: ThemeStore
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Theme").font(.headline)
                Spacer()
                Picker("Appearance", selection: appearance) {
                    ForEach(AppearancePreference.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                Button("Done", action: onClose)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(14)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    section("Dark", Theme.all.filter { $0.appearance == .dark }, selected: themes.darkThemeName)
                    section("Light", Theme.all.filter { $0.appearance == .light }, selected: themes.lightThemeName)
                    if themes.systemWantsHighContrast {
                        Label(
                            "macOS has Increase Contrast turned on, so Beady is using its high-contrast theme.",
                            systemImage: "eye"
                        )
                        .font(.caption)
                        .foregroundStyle(current.secondaryText)
                    }
                }
                .padding(16)
            }
        }
        .frame(width: 520, height: 520)
        .background(current.background)
    }

    private func section(_ title: String, _ options: [Theme], selected: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(current.secondaryText)
            ForEach(options) { theme in
                Button {
                    if theme.appearance == .dark {
                        themes.darkThemeName = theme.name
                        themes.appearance = .dark
                    } else {
                        themes.lightThemeName = theme.name
                        themes.appearance = .light
                    }
                } label: {
                    ThemeSwatch(theme: theme, isSelected: theme.name == selected)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var appearance: Binding<AppearancePreference> {
        Binding(get: { themes.appearance }, set: { themes.appearance = $0 })
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

    private var preferredScheme: ColorScheme? {
        switch themes.appearance {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}
