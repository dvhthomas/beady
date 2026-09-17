import BeadsCore
import Foundation

/// A colour, kept as plain numbers so themes can be defined and checked without SwiftUI.
public struct RGB: Equatable, Sendable {
    public let red: Double
    public let green: Double
    public let blue: Double

    public init(_ red: Double, _ green: Double, _ blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    public init(hex: UInt32) {
        self.init(
            Double((hex >> 16) & 0xFF) / 255,
            Double((hex >> 8) & 0xFF) / 255,
            Double(hex & 0xFF) / 255
        )
    }

    /// WCAG 2.1 relative luminance.
    public var luminance: Double {
        func channel(_ value: Double) -> Double {
            value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(red) + 0.7152 * channel(green) + 0.0722 * channel(blue)
    }

    /// WCAG contrast ratio, 1:1 (identical) to 21:1 (black on white).
    public func contrast(with other: RGB) -> Double {
        let a = luminance
        let b = other.luminance
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }
}

/// Every colour the app draws, named for what it means rather than what it looks like.
public struct ThemeColors: Equatable, Sendable {
    public let background: RGB
    /// Rows, cards, popovers: one step off the background.
    public let surface: RGB
    public let border: RGB
    public let text: RGB
    public let secondaryText: RGB
    public let accent: RGB
    /// The highlighted row. Chosen so text, status colours and priority badges all stay legible
    /// on it — there are tests for that, because a selection that swallows a badge is a bug.
    public let selection: RGB
    public let active: RGB
    public let wip: RGB
    public let frozen: RGB
    public let done: RGB
    public let blocked: RGB
    public let pinned: RGB
    public let starred: RGB

    public init(
        background: RGB, surface: RGB, border: RGB, text: RGB, secondaryText: RGB,
        accent: RGB, selection: RGB, active: RGB, wip: RGB, frozen: RGB, done: RGB,
        blocked: RGB, pinned: RGB, starred: RGB
    ) {
        self.background = background
        self.surface = surface
        self.border = border
        self.text = text
        self.secondaryText = secondaryText
        self.accent = accent
        self.selection = selection
        self.active = active
        self.wip = wip
        self.frozen = frozen
        self.done = done
        self.blocked = blocked
        self.pinned = pinned
        self.starred = starred
    }

    public func category(_ category: StatusCategory) -> RGB {
        switch category {
        case .active: active
        case .wip: wip
        case .frozen: frozen
        case .done: done
        }
    }
}

public struct Theme: Equatable, Sendable, Identifiable {
    public enum Appearance: String, CaseIterable, Sendable, Identifiable {
        case light, dark
        public var id: String { rawValue }
    }

    /// The stored preference, so it has to stay stable.
    public let name: String
    public let appearance: Appearance
    public let isHighContrast: Bool
    public let colors: ThemeColors

    public var id: String { name }
}

public extension Theme {
    static let all: [Theme] = [
        // Dark — the three best-known editor themes, then a high-contrast one.
        Theme(name: "Dracula", appearance: .dark, isHighContrast: false, colors: ThemeColors(
            background: RGB(hex: 0x282A36), surface: RGB(hex: 0x343746), border: RGB(hex: 0x4A4C5E),
            text: RGB(hex: 0xF8F8F2), secondaryText: RGB(hex: 0xA8AEC4),
            accent: RGB(hex: 0xBD93F9), selection: RGB(hex: 0x433D59),
            active: RGB(hex: 0x8BE9FD), wip: RGB(hex: 0xFFB86C), frozen: RGB(hex: 0xA6C2D8),
            done: RGB(hex: 0x50FA7B), blocked: RGB(hex: 0xFF6E77), pinned: RGB(hex: 0xFFB86C),
            starred: RGB(hex: 0xF1FA8C)
        )),
        Theme(name: "One Dark", appearance: .dark, isHighContrast: false, colors: ThemeColors(
            background: RGB(hex: 0x282C34), surface: RGB(hex: 0x32363F), border: RGB(hex: 0x4B5263),
            text: RGB(hex: 0xEBEFF5), secondaryText: RGB(hex: 0xA9B2C3),
            accent: RGB(hex: 0x74AEF6), selection: RGB(hex: 0x364357),
            active: RGB(hex: 0x74AEF6), wip: RGB(hex: 0xE5C07B), frozen: RGB(hex: 0x8FC6D8),
            done: RGB(hex: 0x98C379), blocked: RGB(hex: 0xEF7078), pinned: RGB(hex: 0xE5C07B),
            starred: RGB(hex: 0xE6C07B)
        )),
        Theme(name: "Nord", appearance: .dark, isHighContrast: false, colors: ThemeColors(
            background: RGB(hex: 0x2E3440), surface: RGB(hex: 0x3B4252), border: RGB(hex: 0x4C566A),
            text: RGB(hex: 0xECEFF4), secondaryText: RGB(hex: 0xBFC7D5),
            accent: RGB(hex: 0x88C0D0), selection: RGB(hex: 0x3E4D5A),
            active: RGB(hex: 0x88C0D0), wip: RGB(hex: 0xEBCB8B), frozen: RGB(hex: 0x9FB6CD),
            done: RGB(hex: 0xA3BE8C), blocked: RGB(hex: 0xE3808A), pinned: RGB(hex: 0xEBCB8B),
            starred: RGB(hex: 0xEBCB8B)
        )),
        Theme(name: "High Contrast Dark", appearance: .dark, isHighContrast: true, colors: ThemeColors(
            background: RGB(hex: 0x000000), surface: RGB(hex: 0x121212), border: RGB(hex: 0x8A8A8A),
            text: RGB(hex: 0xFFFFFF), secondaryText: RGB(hex: 0xD6D6D6),
            accent: RGB(hex: 0x6FB8FF), selection: RGB(hex: 0x21374C),
            active: RGB(hex: 0x6FB8FF), wip: RGB(hex: 0xFFC65C), frozen: RGB(hex: 0x9FD9E8),
            done: RGB(hex: 0x5BE07A), blocked: RGB(hex: 0xFF8A8A), pinned: RGB(hex: 0xFFC65C),
            starred: RGB(hex: 0xFFE066)
        )),
        // Light — likewise.
        Theme(name: "Solarized Light", appearance: .light, isHighContrast: false, colors: ThemeColors(
            background: RGB(hex: 0xFDF6E3), surface: RGB(hex: 0xF3ECD8), border: RGB(hex: 0xD9D2BC),
            text: RGB(hex: 0x073642), secondaryText: RGB(hex: 0x56676B),
            accent: RGB(hex: 0x1F6FA8), selection: RGB(hex: 0xDEE3DB),
            active: RGB(hex: 0x1F6FA8), wip: RGB(hex: 0x9A6700), frozen: RGB(hex: 0x4E6E75),
            done: RGB(hex: 0x4F7A15), blocked: RGB(hex: 0xC3282A), pinned: RGB(hex: 0x9A6700),
            starred: RGB(hex: 0x8A6D00)
        )),
        Theme(name: "GitHub Light", appearance: .light, isHighContrast: false, colors: ThemeColors(
            background: RGB(hex: 0xFFFFFF), surface: RGB(hex: 0xF6F8FA), border: RGB(hex: 0xD0D7DE),
            text: RGB(hex: 0x1F2328), secondaryText: RGB(hex: 0x5A6470),
            accent: RGB(hex: 0x0969DA), selection: RGB(hex: 0xD3E4F8),
            active: RGB(hex: 0x0969DA), wip: RGB(hex: 0x9A6700), frozen: RGB(hex: 0x57606A),
            done: RGB(hex: 0x1A7F37), blocked: RGB(hex: 0xCF222E), pinned: RGB(hex: 0x9A6700),
            starred: RGB(hex: 0x8A6D00)
        )),
        Theme(name: "One Light", appearance: .light, isHighContrast: false, colors: ThemeColors(
            background: RGB(hex: 0xFAFAFA), surface: RGB(hex: 0xF0F0F1), border: RGB(hex: 0xD3D3D6),
            text: RGB(hex: 0x383A42), secondaryText: RGB(hex: 0x5C6070),
            accent: RGB(hex: 0x3C74C8), selection: RGB(hex: 0xD0DDEF),
            active: RGB(hex: 0x3C74C8), wip: RGB(hex: 0x9A6700), frozen: RGB(hex: 0x4E6472),
            done: RGB(hex: 0x407A1F), blocked: RGB(hex: 0xCA1243), pinned: RGB(hex: 0x9A6700),
            starred: RGB(hex: 0x8A6D00)
        )),
        Theme(name: "High Contrast Light", appearance: .light, isHighContrast: true, colors: ThemeColors(
            background: RGB(hex: 0xFFFFFF), surface: RGB(hex: 0xF2F2F2), border: RGB(hex: 0x4A4A4A),
            text: RGB(hex: 0x000000), secondaryText: RGB(hex: 0x333333),
            accent: RGB(hex: 0x0B4FA8), selection: RGB(hex: 0xB6CAE5),
            active: RGB(hex: 0x0B4FA8), wip: RGB(hex: 0x7A4B00), frozen: RGB(hex: 0x33525E),
            done: RGB(hex: 0x1B5E20), blocked: RGB(hex: 0xA80000), pinned: RGB(hex: 0x7A4B00),
            starred: RGB(hex: 0x6B5200)
        )),
    ]

    static func dark(named name: String) -> Theme? {
        all.first { $0.name == name && $0.appearance == .dark }
    }

    static func light(named name: String) -> Theme? {
        all.first { $0.name == name && $0.appearance == .light }
    }

    /// What a fresh install uses.
    static var defaultDark: Theme { dark(named: "One Dark")! }
    static var defaultLight: Theme { light(named: "GitHub Light")! }
}

/// What the user asked for, as opposed to what macOS is currently doing.
public enum AppearancePreference: String, CaseIterable, Identifiable, Sendable {
    case system, light, dark

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }
}

/// What the sidebar is made of. Theming every surface makes the window look like one thing;
/// macOS's own material makes it look like a Mac app. Neither is wrong, so it's a setting.
public enum SidebarStyle: String, CaseIterable, Identifiable, Sendable {
    /// Painted from the theme, as Linear and VS Code do.
    case themed
    /// macOS's translucent sidebar material, as Finder and Xcode do.
    case native

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .themed: "Themed"
        case .native: "Translucent"
        }
    }

    public var detail: String {
        switch self {
        case .themed: "One coherent window, painted by the theme."
        case .native: "macOS's own material, which picks up what's behind the window."
        }
    }
}

/// How large the whole interface is drawn. macOS has no Dynamic Type, so the app provides it.
public enum TextSize: String, CaseIterable, Identifiable, Sendable {
    case small
    case `default`
    case large
    case extraLarge

    public var id: String { rawValue }

    public var scale: Double {
        switch self {
        case .small: 0.9
        case .default: 1
        case .large: 1.2
        case .extraLarge: 1.45
        }
    }

    public var title: String {
        switch self {
        case .small: "Small"
        case .default: "Default"
        case .large: "Large"
        case .extraLarge: "Extra Large"
        }
    }
}


/// Which theme the app is using, and which one it is trying on.
///
/// Previewing is deliberately separate from choosing: arrowing down the list repaints the app so
/// you can see a theme doing its job, and only Apply makes that the setting. Leaving the picker
/// without applying puts back what you had.
public struct ThemeSelection: Equatable, Sendable {
    /// Every theme in the order the picker shows them: dark first, then light.
    public static let catalog: [Theme] = Theme.all.filter { $0.appearance == .dark }
        + Theme.all.filter { $0.appearance == .light }

    public var appearance: AppearancePreference
    public var darkName: String
    public var lightName: String
    public private(set) var previewed: Theme?

    public init(
        appearance: AppearancePreference = .system,
        darkName: String = Theme.defaultDark.name,
        lightName: String = Theme.defaultLight.name
    ) {
        self.appearance = appearance
        self.darkName = darkName
        self.lightName = lightName
    }

    /// The theme to draw with. A preview wins; the system's Increase Contrast setting wins over
    /// everything, because it was asked for by someone who needs it.
    public func resolved(systemIsDark: Bool, highContrast: Bool = false) -> Theme {
        let wantsDark = switch effectiveAppearance {
        case .system: systemIsDark
        case .light: false
        case .dark: true
        }
        if highContrast {
            return Theme.all.first { $0.isHighContrast && $0.appearance == (wantsDark ? .dark : .light) }!
        }
        if let previewed { return previewed }
        return wantsDark
            ? (Theme.dark(named: darkName) ?? .defaultDark)
            : (Theme.light(named: lightName) ?? .defaultLight)
    }

    /// What light/dark the window chrome should follow, so a previewed light theme doesn't sit in
    /// a dark window.
    public var effectiveAppearance: AppearancePreference {
        guard let previewed else { return appearance }
        return previewed.appearance == .dark ? .dark : .light
    }

    public mutating func preview(_ theme: Theme?) {
        previewed = theme
    }

    public mutating func cancelPreview() {
        previewed = nil
    }

    /// Keeps whatever is being previewed as the choice for its own side — the dark theme or the
    /// light one — and leaves the Appearance setting alone.
    ///
    /// So with Appearance on System, picking a light theme says "this is the theme for when macOS
    /// is light" rather than forcing the app light. Appearance is the user's answer to a different
    /// question, and picking a theme shouldn't silently overrule it.
    public mutating func commitPreview() {
        guard let previewed else { return }
        switch previewed.appearance {
        case .dark: darkName = previewed.name
        case .light: lightName = previewed.name
        }
        self.previewed = nil
    }

    /// When a given theme actually gets used, so the picker can say so rather than leaving it to
    /// be guessed at.
    public func usage(of theme: Theme, systemIsDark: Bool) -> ThemeUsage {
        var settled = self
        settled.cancelPreview()
        if settled.resolved(systemIsDark: systemIsDark).name == theme.name { return .inUse }
        if appearance == .system { return .whenSystemIs(theme.appearance) }
        return .unusedWhile(appearance)
    }

    public func index(of theme: Theme) -> Int? {
        Self.catalog.firstIndex { $0.name == theme.name }
    }

    /// The theme the picker should start on: whatever is in use.
    public func startingIndex(systemIsDark: Bool) -> Int {
        index(of: resolved(systemIsDark: systemIsDark)) ?? 0
    }

    /// Arrowing stops at the ends rather than wrapping: a list you can fall off the bottom of is
    /// hard to trust when every step repaints the whole app.
    public static func step(_ index: Int, by delta: Int) -> Int {
        min(max(index + delta, 0), catalog.count - 1)
    }
}


/// When a theme applies, in words.
public enum ThemeUsage: Equatable, Sendable {
    case inUse
    /// Appearance is System, so this theme waits for macOS to be that way.
    case whenSystemIs(Theme.Appearance)
    /// Appearance is pinned to light or dark, so the other side's theme sits unused.
    case unusedWhile(AppearancePreference)

    public var title: String {
        switch self {
        case .inUse: "In use"
        case .whenSystemIs(let appearance): "When macOS is \(appearance.rawValue)"
        case .unusedWhile(let appearance): "Not used while Appearance is \(appearance.title)"
        }
    }
}
