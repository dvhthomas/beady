import BeadsCore
import BeadsPresentation
import Foundation
import Observation
import SwiftUI

/// The list's column widths, order and visibility, as the user has dragged them.
///
/// `Table` owns this state and applies it to the header itself (drag to resize, right-click to
/// show and hide); this type only keeps it alive between launches and lets the Display menu
/// toggle the same thing the header menu does.
@MainActor
@Observable
final class ColumnLayout {
    var customization: TableColumnCustomization<BeadsCore.Issue> {
        didSet { save() }
    }

    @ObservationIgnored private let defaults: UserDefaults
    private static let key = "issueListColumns"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let saved = defaults.data(forKey: Self.key)
            .flatMap { try? JSONDecoder().decode(TableColumnCustomization<BeadsCore.Issue>.self, from: $0) }
        customization = saved ?? TableColumnCustomization<BeadsCore.Issue>()
    }

    func isVisible(_ column: ListColumn) -> Bool {
        column.isVisible(customized: choice(for: column))
    }

    /// What the user has dragged wins; otherwise the view says which columns it shows (Stuck
    /// turns Blocked-by on), and a view that doesn't say takes the defaults.
    func isVisible(_ column: ListColumn, in presentation: ViewPresentation) -> Bool {
        if let chosen = choice(for: column) { return column.isVisible(customized: chosen) }
        if let columns = presentation.columns { return column.isAlwaysVisible || columns.contains(column.id) }
        return isVisible(column)
    }

    /// What the table has stored: nil when the user has never shown or hidden this column.
    private func choice(for column: ListColumn) -> Bool? {
        switch customization[visibility: column.id] {
        case .visible: true
        case .hidden: false
        default: nil
        }
    }

    func setVisible(_ column: ListColumn, _ visible: Bool) {
        guard !column.isAlwaysVisible else { return }
        customization[visibility: column.id] = visible ? .visible : .hidden
    }

    /// Back to the starting widths and columns.
    func reset() {
        customization = TableColumnCustomization<BeadsCore.Issue>()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(customization) else { return }
        defaults.set(data, forKey: Self.key)
    }
}
