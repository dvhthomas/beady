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
            for accent in [theme.colors.blocked, theme.colors.pinned, theme.colors.starred, theme.colors.accent] {
                #expect(accent.contrast(with: theme.colors.background) >= 3, "\(theme.name): an accent is too faint")
            }
        }
    }

    @Test("nothing goes illegible on a highlighted row")
    func selection() {
        for theme in Theme.all {
            let text = theme.colors.text.contrast(with: theme.colors.selection)
            #expect(text >= 4.5, "\(theme.name): text on a selected row is \(String(format: "%.2f", text)):1")
            let secondary = theme.colors.secondaryText.contrast(with: theme.colors.selection)
            #expect(secondary >= 4.5, "\(theme.name): secondary text on a selected row is \(String(format: "%.2f", secondary)):1")
            for category in StatusCategory.allCases {
                let ratio = theme.colors.category(category).contrast(with: theme.colors.selection)
                #expect(ratio >= 3, "\(theme.name): \(category.rawValue) on a selected row is \(String(format: "%.2f", ratio)):1")
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

    @Test("content drawn over any theme's accent or selection gets a legible foreground")
    func foregroundOnAccent() {
        for theme in Theme.all {
            for (name, background) in [("accent", theme.colors.accent), ("selection", theme.colors.selection)] {
                let ratio = RGB.legibleForeground(on: background).contrast(with: background)
                #expect(ratio >= 4.5, "\(theme.name): foreground on \(name) is \(String(format: "%.2f", ratio)):1")
            }
        }
    }

    @Test("legibleForeground clears 4.5:1 on any colour at all, not just the shipped accents")
    func foregroundOnAnything() {
        // A coarse sweep of the whole gamut. The worst case for "the better of white and black"
        // is a mid-luminance background, which still yields about 4.58:1.
        let steps = stride(from: 0.0, through: 1.0, by: 0.25)
        for red in steps {
            for green in steps {
                for blue in steps {
                    let background = RGB(red, green, blue)
                    let foreground = RGB.legibleForeground(on: background)
                    let ratio = foreground.contrast(with: background)
                    #expect(ratio >= 4.5, "(\(red), \(green), \(blue)) got only \(String(format: "%.2f", ratio)):1")
                }
            }
        }
    }

    @Test("legibleForeground goes light on deep accents and dark on pale ones")
    func foregroundPicksTheRightSide() {
        let white = RGB(1, 1, 1)
        let black = RGB(0, 0, 0)
        // GitHub Light's blue is deep: white text, as macOS itself would draw it.
        #expect(RGB.legibleForeground(on: RGB(hex: 0x0969DA)) == white)
        // Dracula's lavender and Nord's frost are pale: white on them is the bug this guards against.
        #expect(RGB.legibleForeground(on: RGB(hex: 0xBD93F9)) == black)
        #expect(RGB.legibleForeground(on: RGB(hex: 0x88C0D0)) == black)
    }

    @Test("an 18% accent wash — filter chips, drop targets — leaves the theme's text legible")
    func tintedChips() {
        // How the views draw a chip: the accent at 0.18 opacity composited over what's beneath.
        func wash(_ accent: RGB, over base: RGB) -> RGB {
            RGB(
                accent.red * 0.18 + base.red * 0.82,
                accent.green * 0.18 + base.green * 0.82,
                accent.blue * 0.18 + base.blue * 0.82
            )
        }
        for theme in Theme.all {
            for base in [theme.colors.background, theme.colors.surface] {
                let chip = wash(theme.colors.accent, over: base)
                let ratio = theme.colors.text.contrast(with: chip)
                #expect(ratio >= 4.5, "\(theme.name): text on a chip is \(String(format: "%.2f", ratio)):1")
            }
        }
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
