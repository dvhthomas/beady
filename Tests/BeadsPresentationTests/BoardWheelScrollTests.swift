import BeadsPresentation
import Foundation
import Testing

@Suite("A mouse wheel tilted sideways glides the board by columns")
struct BoardWheelScrollTests {
    let stride: CGFloat = 302

    @Test("a notch to the right moves the origin right by half a column; to the left, left")
    func notch() {
        #expect(BoardWheelScroll.step(deltaX: -1, deltaY: 0, precise: false, columnStride: stride) == 151)
        #expect(BoardWheelScroll.step(deltaX: 1, deltaY: 0, precise: false, columnStride: stride) == -151)
    }

    @Test("a fast turn counts its lines, up to the cap")
    func magnitude() {
        #expect(BoardWheelScroll.step(deltaX: -2, deltaY: 0, precise: false, columnStride: stride) == 302)
        #expect(BoardWheelScroll.step(deltaX: -10, deltaY: 0, precise: false, columnStride: stride) == 453)
        #expect(BoardWheelScroll.step(deltaX: -0.4, deltaY: 0, precise: false, columnStride: stride) == 151, "less than a line is still a notch")
    }

    @Test("a trackpad, a vertical turn and a still wheel are left to the scroll view")
    func leftAlone() {
        #expect(BoardWheelScroll.step(deltaX: -1, deltaY: 0, precise: true, columnStride: stride) == nil)
        #expect(BoardWheelScroll.step(deltaX: -1, deltaY: 3, precise: false, columnStride: stride) == nil)
        #expect(BoardWheelScroll.step(deltaX: 0, deltaY: 0, precise: false, columnStride: stride) == nil)
        #expect(BoardWheelScroll.step(deltaX: -1, deltaY: -1, precise: false, columnStride: stride) == 151, "a diagonal that is at least as sideways as it is up counts")
    }

    @Test("a glide starts where the board is, and a held tilt extends the glide under way")
    func target() {
        #expect(BoardWheelScroll.target(from: 100, pending: nil, step: 151, contentWidth: 2000, visibleWidth: 800) == 251)
        #expect(BoardWheelScroll.target(from: 100, pending: 251, step: 151, contentWidth: 2000, visibleWidth: 800) == 402)
    }

    @Test("a glide stops at either edge of the content, and a board that fits never moves")
    func clamped() {
        #expect(BoardWheelScroll.target(from: 1150, pending: nil, step: 151, contentWidth: 2000, visibleWidth: 800) == 1200)
        #expect(BoardWheelScroll.target(from: 50, pending: nil, step: -151, contentWidth: 2000, visibleWidth: 800) == 0)
        #expect(BoardWheelScroll.target(from: 0, pending: nil, step: 151, contentWidth: 600, visibleWidth: 800) == 0)
    }
}
