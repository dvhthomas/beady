import BeadsCore
import BeadsPresentation
import Testing

@Suite("The details pane: one that came with a bead leaves with it; one asked for stays")
struct DetailsPaneTests {
    @Test("selecting a bead while the pane is hidden opens it, only for as long as the bead is held")
    func selectingOpensAPeek() {
        #expect(DetailsPane.closed.following(selection: "a") == .peeking)
        #expect(DetailsPane.peeking.isOpen)
    }

    @Test("moving to another bead keeps the pane as it was")
    func anotherBead() {
        #expect(DetailsPane.peeking.following(selection: "b") == .peeking)
        #expect(DetailsPane.pinned.following(selection: "b") == .pinned)
    }

    @Test("letting go of the bead closes a pane that came with it")
    func lettingGoClosesAPeek() {
        #expect(DetailsPane.peeking.following(selection: nil) == .closed)
        #expect(!DetailsPane.closed.isOpen)
    }

    @Test("a pane the user asked for stays through an empty selection")
    func pinnedStays() {
        #expect(DetailsPane.pinned.following(selection: nil) == .pinned)
        #expect(DetailsPane.pinned.isOpen)
    }

    @Test("a hidden pane stays hidden while nothing is selected")
    func closedStaysClosed() {
        #expect(DetailsPane.closed.following(selection: nil) == .closed)
    }

    @Test("the Details command pins the pane open — a peeking one too — and hides a pinned one")
    func toggling() {
        #expect(DetailsPane.closed.toggled() == .pinned)
        #expect(DetailsPane.peeking.toggled() == .pinned)
        #expect(DetailsPane.pinned.toggled() == .closed)
    }

    @Test("only a pinned pane takes room from the beads; a peeking one floats over them")
    func floating() {
        #expect(DetailsPane.peeking.floats)
        #expect(!DetailsPane.pinned.floats)
        #expect(!DetailsPane.closed.floats)
    }

    @Test("showing the pane on request pins a hidden one and leaves an open one alone")
    func shown() {
        #expect(DetailsPane.closed.shown() == .pinned)
        #expect(DetailsPane.peeking.shown() == .peeking)
        #expect(DetailsPane.pinned.shown() == .pinned)
    }

    @Test("only a pane that came with the bead lets go of it on Escape or a click away")
    func clickAway() {
        #expect(DetailsPane.peeking.letsGoOnClickAway)
        #expect(!DetailsPane.pinned.letsGoOnClickAway)
        #expect(!DetailsPane.closed.letsGoOnClickAway)
    }
}
