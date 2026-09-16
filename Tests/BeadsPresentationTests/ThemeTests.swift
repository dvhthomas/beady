import BeadsCore
import BeadsPresentation
import Testing

@Suite("Themes and contrast")
struct ThemeTests {
    /// WCAG 2.1: normal body text needs 4.5:1, large text and meaningful graphics 3:1.
    @Test("every theme's body text is readable on its own background")
    func bodyText() {
        for theme in Theme.all {
            let ratio = theme.colors.text.contrast(with: theme.colors.background)
            #expect(ratio >= 4.5, "\(theme.name): text on background is \(String(format: "%.2f", ratio)):1")
            let secondary = theme.colors.secondaryText.contrast(with: theme.colors.background)
            #expect(secondary >= 4.5, "\(theme.name): secondary text is \(String(format: "%.2f", secondary)):1")
            let onSurface = theme.colors.text.contrast(with: theme.colors.surface)
            #expect(onSurface >= 4.5, "\(theme.name): text on a row is \(String(format: "%.2f", onSurface)):1")
        }
    }

    @Test("status, priority and warning colours stand out enough to carry meaning")
    func meaningfulColors() {
        for theme in Theme.all {
            for category in StatusCategory.allCases {
                let ratio = theme.colors.category(category).contrast(with: theme.colors.background)
                #expect(ratio >= 3, "\(theme.name): \(category.rawValue) is \(String(format: "%.2f", ratio)):1")
            }
            for priority in 0...4 {
                let ratio = theme.colors.priority(priority).contrast(with: theme.colors.background)
                #expect(ratio >= 3, "\(theme.name): P\(priority) is \(String(format: "%.2f", ratio)):1")
            }
            for accent in [theme.colors.blocked, theme.colors.pinned, theme.colors.starred, theme.colors.accent] {
                #expect(accent.contrast(with: theme.colors.background) >= 3, "\(theme.name): an accent is too faint")
            }
        }
    }

    @Test("the high-contrast themes clear the stricter AAA bar, for eyes that need it")
    func highContrast() {
        for theme in Theme.all where theme.isHighContrast {
            #expect(theme.colors.text.contrast(with: theme.colors.background) >= 7)
            #expect(theme.colors.secondaryText.contrast(with: theme.colors.background) >= 7)
            for category in StatusCategory.allCases {
                #expect(theme.colors.category(category).contrast(with: theme.colors.background) >= 4.5)
            }
        }
        #expect(Theme.all.filter(\.isHighContrast).count == 2, "one for dark, one for light")
    }

    @Test("there is a theme for each appearance, including the three best-known of each")
    func catalog() {
        #expect(Theme.all.filter { $0.appearance == .dark }.count >= 4)
        #expect(Theme.all.filter { $0.appearance == .light }.count >= 4)
        let names = Theme.all.map(\.name)
        #expect(names.contains("Dracula") && names.contains("One Dark") && names.contains("Nord"))
        #expect(names.contains("Solarized Light") && names.contains("GitHub Light") && names.contains("One Light"))
        #expect(Set(names).count == names.count, "names are the stored preference; they must be unique")
        #expect(Theme.dark(named: "Nord")?.appearance == .dark)
        #expect(Theme.light(named: "Nord") == nil, "a dark theme can't be chosen as the light one")
    }

    @Test("contrast maths matches the WCAG reference values")
    func contrastMaths() {
        let white = RGB(1, 1, 1)
        let black = RGB(0, 0, 0)
        #expect(abs(white.contrast(with: black) - 21) < 0.01)
        #expect(abs(white.contrast(with: white) - 1) < 0.01)
        // #767676 on white is the classic 4.54:1 boundary case from the WCAG docs.
        #expect(abs(RGB(hex: 0x767676).contrast(with: white) - 4.54) < 0.05)
    }

    @Test("text sizes scale sensibly and remember their name")
    func textSizes() {
        #expect(TextSize.allCases.map(\.id) == ["small", "default", "large", "extraLarge"])
        #expect(TextSize.default.scale == 1)
        #expect(TextSize.small.scale < 1)
        #expect(TextSize.large.scale > 1)
        #expect(TextSize.extraLarge.scale > TextSize.large.scale)
        #expect(TextSize.extraLarge.scale <= 1.6, "beyond this the fixed row heights break")
    }
}
