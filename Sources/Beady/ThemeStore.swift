import AppKit
import BeadsCore
import BeadsPresentation
import Observation
import SwiftUI

extension Color {
    init(_ rgb: RGB) {
        self.init(.sRGB, red: rgb.red, green: rgb.green, blue: rgb.blue, opacity: 1)
    }
}

/// The chosen appearance, themes and text size, remembered between launches in UserDefaults
/// (`~/Library/Preferences/me.bitsby.beady.plist`, the standard place for app settings).
@MainActor
@Observable
final class ThemeStore {
    /// The choice, plus whatever is being tried on. Previews are never saved.
    private(set) var selection: ThemeSelection { didSet { save(); applyToApp() } }

    var appearance: AppearancePreference {
        get { selection.appearance }
        set { selection.appearance = newValue }
    }

    var darkThemeName: String {
        get { selection.darkName }
        set { selection.darkName = newValue }
    }

    var lightThemeName: String {
        get { selection.lightName }
        set { selection.lightName = newValue }
    }
    var textSize: TextSize { didSet { save() } }
    /// Set from the system's Increase Contrast setting; the high-contrast themes win while it's on.
    private(set) var systemWantsHighContrast: Bool

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        selection = ThemeSelection(
            appearance: AppearancePreference(rawValue: defaults.string(forKey: "appearance") ?? "") ?? .system,
            darkName: defaults.string(forKey: "darkTheme") ?? Theme.defaultDark.name,
            lightName: defaults.string(forKey: "lightTheme") ?? Theme.defaultLight.name
        )
        textSize = TextSize(rawValue: defaults.string(forKey: "textSize") ?? "") ?? .default
        systemWantsHighContrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        applyToApp()
    }

    /// The theme to draw with, given the setting, any preview, and what macOS is doing.
    func theme(for colorScheme: ColorScheme) -> Theme {
        selection.resolved(systemIsDark: colorScheme == .dark, highContrast: systemWantsHighContrast)
    }

    /// Try a theme on without keeping it.
    func preview(_ theme: Theme?) {
        selection.preview(theme)
    }

    /// Apply: the previewed theme becomes the setting.
    func commitPreview() {
        selection.commitPreview()
    }

    /// Leaving the picker without applying.
    func cancelPreview() {
        selection.cancelPreview()
    }

    var previewed: Theme? { selection.previewed }

    /// Watches the system's Increase Contrast setting, so accessibility wins without a relaunch.
    func watchAccessibility() {
        NotificationCenter.default.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: NSWorkspace.shared,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.systemWantsHighContrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
            }
        }
    }

    /// Light/dark applies to the window chrome too, not just our own drawing.
    private func applyToApp() {
        NSApp?.appearance = switch selection.effectiveAppearance {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }

    private func save() {
        // A preview is never written: only Apply changes what comes back next launch.
        defaults.set(selection.appearance.rawValue, forKey: "appearance")
        defaults.set(selection.darkName, forKey: "darkTheme")
        defaults.set(selection.lightName, forKey: "lightTheme")
        defaults.set(textSize.rawValue, forKey: "textSize")
    }
}

private struct ThemeKey: EnvironmentKey {
    static let defaultValue = Theme.defaultDark
}

extension EnvironmentValues {
    var theme: Theme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}

extension Theme {
    var background: Color { Color(colors.background) }
    var surface: Color { Color(colors.surface) }
    var border: Color { Color(colors.border) }
    var text: Color { Color(colors.text) }
    var secondaryText: Color { Color(colors.secondaryText) }
    var accent: Color { Color(colors.accent) }
    var selection: Color { Color(colors.selection) }
    var blocked: Color { Color(colors.blocked) }
    var pinned: Color { Color(colors.pinned) }
    var starred: Color { Color(colors.starred) }

    func color(_ category: StatusCategory) -> Color { Color(colors.category(category)) }
    func priority(_ priority: Int) -> Color { Color(colors.priority(priority)) }
}
