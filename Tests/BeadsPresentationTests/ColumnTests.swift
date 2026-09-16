import BeadsCore
import BeadsPresentation
import Testing

@Suite("List columns")
struct ListColumnTests {
    @Test("the catalog is the row's columns, left to right, with ids that never change")
    func catalog() {
        // The ids are saved with the user's column widths and visibility; renaming one silently
        // resets their layout.
        #expect(ListColumn.allCases.map(\.id) == ["priority", "id", "status", "type", "title", "labels", "assignee", "progress", "date"])
        #expect(ListColumn.allCases.allSatisfy { !$0.title.isEmpty })
    }

    @Test("the title column is always there; everything else can be hidden")
    func titleIsFixed() {
        #expect(ListColumn.allCases.filter(\.isAlwaysVisible) == [.title])
    }

    @Test("a first-time user sees the columns the fixed row used to show")
    func defaults() {
        #expect(ListColumn.allCases.filter(\.isVisibleByDefault) == [.priority, .id, .status, .type, .title, .assignee, .date])
        #expect(!ListColumn.progress.isVisibleByDefault, "progress is for when you're looking at containers")
        #expect(!ListColumn.labels.isVisibleByDefault, "labels are noisy; on request only")
    }

    @Test("the date column says which date it is showing")
    func dateHeaderFollowsOrdering() {
        #expect(ListColumn.date.title(for: .recentlyUpdated) == "Updated")
        #expect(ListColumn.date.title(for: .recentlyCreated) == "Updated")
        #expect(ListColumn.date.title(for: .recentlyClosed) == "Closed")
        #expect(ListColumn.title.title(for: .recentlyClosed) == "Title", "other columns don't move")
    }

    @Test("an untouched column follows its default, so the menu and the table agree")
    func visibilityFollowsTheDefault() {
        #expect(ListColumn.labels.isVisible(customized: nil) == false)
        #expect(ListColumn.progress.isVisible(customized: nil) == false)
        #expect(ListColumn.assignee.isVisible(customized: nil) == true)
        #expect(ListColumn.labels.isVisible(customized: true) == true)
        #expect(ListColumn.assignee.isVisible(customized: false) == false)
        #expect(ListColumn.title.isVisible(customized: false) == true, "the title can't be hidden")
    }

    @Test("columns have a sensible starting width, and the title one stretches")
    func widths() {
        #expect(ListColumn.allCases.allSatisfy { $0.idealWidth > 0 })
        #expect(ListColumn.title.maximumWidth == nil)
        #expect(ListColumn.priority.maximumWidth != nil, "badges shouldn't stretch")
    }
}


@Suite("Hover previews")
struct PreviewTextTests {
    @Test("short text is shown as it is")
    func short() {
        #expect(DisplayText.preview("Freeform furniture positioning") == "Freeform furniture positioning")
        #expect(DisplayText.preview("  padded  ") == "padded")
        #expect(DisplayText.preview("") == nil, "nothing to preview")
    }

    @Test("long text is cut at 512 characters, with an ellipsis to say there is more")
    func long() {
        let text = String(repeating: "a", count: 600)
        let preview = try! #require(DisplayText.preview(text))
        #expect(preview.count == 513)
        #expect(preview.hasSuffix("…"))
        #expect(!DisplayText.preview(String(repeating: "b", count: 512))!.hasSuffix("…"), "exactly at the limit is whole")
    }

    @Test("the cut lands on a word boundary when there is one nearby")
    func wordBoundary() {
        let text = String(repeating: "word ", count: 200)
        let preview = try! #require(DisplayText.preview(text))
        #expect(preview.hasSuffix("word…"))
    }
}
