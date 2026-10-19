import Foundation

/// How a mouse wheel moves the board sideways.
///
/// A trackpad reports precise deltas and the scroll view follows the fingers; nothing to add. A
/// wheel tilted sideways reports a notch: a small fixed delta with no acceleration, which AppKit
/// turns into a few points, so the board crawls, and in jumps. Each notch moves the board by half
/// a column instead, and while the tilt is held every notch extends the glide already under way.
public enum BoardWheelScroll {
    /// A notch moves this fraction of a column.
    public static let columnsPerNotch: CGFloat = 0.5
    /// A wheel event with a bigger delta than this counts as this many notches: some mice report
    /// several lines per tick when turned fast, none report more than a few.
    public static let notchCap: CGFloat = 3

    /// How far the board's origin moves for one wheel event, in points; nil when the event is not
    /// a sideways notch (a trackpad's precise deltas, or a mostly vertical turn, are left to the
    /// scroll view). AppKit's deltaX is negative when the wheel tilts right, which reveals what
    /// is to the right, so the origin moves the other way.
    public static func step(deltaX: CGFloat, deltaY: CGFloat, precise: Bool, columnStride: CGFloat) -> CGFloat? {
        guard !precise, deltaX != 0, abs(deltaX) >= abs(deltaY) else { return nil }
        let notches = min(max(abs(deltaX).rounded(.up), 1), notchCap)
        return (deltaX < 0 ? 1 : -1) * notches * columnsPerNotch * columnStride
    }

    /// Where a glide ends: `step` on from the glide already under way when there is one, else from
    /// where the board is, kept within the content.
    public static func target(from current: CGFloat, pending: CGFloat?, step: CGFloat, contentWidth: CGFloat, visibleWidth: CGFloat) -> CGFloat {
        let start = pending ?? current
        return min(max(start + step, 0), max(contentWidth - visibleWidth, 0))
    }
}
