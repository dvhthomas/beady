import BeadsPresentation
import Testing

@Suite("Choosing a theme")
struct ThemeSelectionTests {
    @Test("with nothing being previewed, the appearance decides which theme is used")
    func resolves() {
        var selection = ThemeSelection(appearance: .dark, darkName: "Nord", lightName: "One Light")
        #expect(selection.resolved(systemIsDark: false).name == "Nord", "the setting wins over the system")
        selection.appearance = .system
        #expect(selection.resolved(systemIsDark: true).name == "Nord")
        #expect(selection.resolved(systemIsDark: false).name == "One Light")
    }

    @Test("a preview takes over, including its light or dark appearance")
    func preview() {
        var selection = ThemeSelection(appearance: .dark, darkName: "Nord", lightName: "One Light")
        selection.preview(Theme.light(named: "Solarized Light"))
        #expect(selection.resolved(systemIsDark: true).name == "Solarized Light")
        #expect(selection.effectiveAppearance == .light, "so the window chrome follows the preview")
    }

    @Test("Apply keeps the previewed theme; leaving without it puts the old one back")
    func commitAndCancel() {
        var selection = ThemeSelection(appearance: .dark, darkName: "Nord", lightName: "One Light")
        selection.preview(Theme.dark(named: "Dracula"))
        selection.cancelPreview()
        #expect(selection.resolved(systemIsDark: true).name == "Nord")
        #expect(selection.darkName == "Nord")

        selection.preview(Theme.dark(named: "Dracula"))
        selection.commitPreview()
        #expect(selection.darkName == "Dracula")
        #expect(selection.appearance == .dark, "Appearance is the user's, and picking a theme doesn't change it")
        #expect(selection.resolved(systemIsDark: false).name == "Dracula", "and it sticks with no preview left")

        // Choosing a light theme while the app is set to Dark sets the light slot and leaves the
        // Appearance setting alone: it's the theme macOS light will use.
        selection.preview(Theme.light(named: "GitHub Light"))
        selection.commitPreview()
        #expect(selection.lightName == "GitHub Light")
        #expect(selection.appearance == .dark)
        #expect(selection.resolved(systemIsDark: true).name == "Dracula")
    }

    @Test("the picker can say when each theme is used")
    func usage() {
        var selection = ThemeSelection(appearance: .system, darkName: "Nord", lightName: "One Light")
        #expect(selection.usage(of: Theme.dark(named: "Nord")!, systemIsDark: true) == .inUse)
        #expect(selection.usage(of: Theme.light(named: "One Light")!, systemIsDark: true) == .whenSystemIs(.light))
        #expect(selection.usage(of: Theme.dark(named: "Dracula")!, systemIsDark: true) == .whenSystemIs(.dark),
                "a theme you haven't chosen still belongs to its side")

        selection.appearance = .dark
        #expect(selection.usage(of: Theme.dark(named: "Nord")!, systemIsDark: false) == .inUse)
        #expect(selection.usage(of: Theme.light(named: "One Light")!, systemIsDark: false) == .unusedWhile(.dark))

        #expect(ThemeUsage.inUse.title == "In use")
        #expect(ThemeUsage.whenSystemIs(.light).title == "When macOS is light")
        #expect(ThemeUsage.unusedWhile(.dark).title == "Not used while Appearance is Dark")
    }

    @Test("the system's Increase Contrast setting wins over any of it")
    func highContrast() {
        var selection = ThemeSelection(appearance: .dark, darkName: "Nord", lightName: "One Light")
        selection.preview(Theme.dark(named: "Dracula"))
        let theme = selection.resolved(systemIsDark: true, highContrast: true)
        #expect(theme.isHighContrast)
        #expect(theme.appearance == .dark)
    }

    @Test("arrowing runs through every theme, dark then light, and stops at the ends")
    func stepping() {
        let selection = ThemeSelection(appearance: .dark, darkName: "Nord", lightName: "One Light")
        #expect(ThemeSelection.catalog.first?.appearance == .dark)
        #expect(ThemeSelection.catalog.last?.appearance == .light)
        #expect(ThemeSelection.catalog.count == Theme.all.count)
        #expect(selection.index(of: Theme.dark(named: "Nord")!) == ThemeSelection.catalog.firstIndex { $0.name == "Nord" })
    }
}
