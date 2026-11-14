import AppKit
import BeadsPresentation
import SwiftUI

/// The edge every text input in a form wears: the theme's surface inside a hairline, which turns
/// to the accent with a soft halo while the input has the keyboard. One edge for one-line and
/// multi-line inputs alike, so a form reads as one thing rather than a mix of AppKit's bezel and
/// our own box.
struct FieldChrome: ViewModifier {
    @Environment(\.theme) private var theme
    let isFocused: Bool

    func body(content: Content) -> some View {
        content
            .background(theme.surface, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(isFocused ? theme.accent : theme.border))
            .background {
                if isFocused {
                    RoundedRectangle(cornerRadius: 9)
                        .fill(theme.accent.opacity(0.28))
                        .padding(-3)
                }
            }
    }
}

/// A one-line text input in the form's own edge. Its text starts 8 points in, the same as
/// `ProseEditor`'s, so a column of inputs shares a left margin.
struct LineField: View {
    let prompt: LocalizedStringKey
    let text: Binding<String>
    let font: Font
    let focusesOnAppear: Bool
    private var focus = FocusState<Bool>()

    init(_ prompt: LocalizedStringKey, text: Binding<String>, font: Font = .body, focusesOnAppear: Bool = false) {
        self.prompt = prompt
        self.text = text
        self.font = font
        self.focusesOnAppear = focusesOnAppear
    }

    var body: some View {
        TextField(prompt, text: text)
            .textFieldStyle(.plain)
            .font(font)
            .labelsHidden()
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            // A plain field otherwise stretches to the tallest thing beside it in a row.
            .fixedSize(horizontal: false, vertical: true)
            .focused(focus.projectedValue)
            .modifier(FieldChrome(isFocused: focus.wrappedValue))
            .onAppear { if focusesOnAppear { focus.wrappedValue = true } }
    }
}

/// A multi-line text box that reads as one: the form's edge, and a prompt while empty.
///
/// It wraps `NSTextView` itself rather than using `TextEditor`, for three things `TextEditor`
/// doesn't offer. The prompt is drawn by the text view at the origin its own text uses, so the
/// two can't drift apart (an overlaid `Text` had to guess AppKit's insets, and sat 8 points
/// low), and in the colour AppKit gives a one-line field's prompt, so `LineField` and this
/// match. The scroller hides until there is something to scroll, instead of leaving an empty
/// gutter for anyone whose scroll bars are always shown. And smart quotes and dashes are off:
/// what's typed here goes to bd as written, and `--flag` must not become `—flag`.
struct ProseEditor: View {
    @Environment(\.theme) private var theme
    let text: Binding<String>
    let prompt: String
    let minHeight: CGFloat
    /// The body size at the app's text-size setting, which reaches SwiftUI as Dynamic Type.
    private var fontSize = ScaledMetric(wrappedValue: NSFont.systemFontSize, relativeTo: .body)
    private var isFocused = State(initialValue: false)

    init(text: Binding<String>, prompt: String, minHeight: CGFloat) {
        self.text = text
        self.prompt = prompt
        self.minHeight = minHeight
    }

    var body: some View {
        ProseTextArea(
            text: text,
            prompt: prompt,
            font: .systemFont(ofSize: fontSize.wrappedValue),
            textColor: NSColor(theme.text),
            caretColor: NSColor(theme.accent),
            isFocused: isFocused.projectedValue
        )
        .frame(minHeight: minHeight)
        .modifier(FieldChrome(isFocused: isFocused.wrappedValue))
    }
}

private struct ProseTextArea: NSViewRepresentable {
    let text: Binding<String>
    let prompt: String
    let font: NSFont
    let textColor: NSColor
    let caretColor: NSColor
    let isFocused: Binding<Bool>

    func makeCoordinator() -> Coordinator {
        Coordinator(text: text)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = ProseTextView()
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        // 3 here plus the container's own 5 of line padding: text starts 8 in, as in LineField.
        textView.textContainerInset = NSSize(width: 3, height: 6)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        let isFocused = isFocused
        textView.onFocusChange = { focused in
            // First responder changes arrive mid-update often enough that SwiftUI complains.
            DispatchQueue.main.async { isFocused.wrappedValue = focused }
        }

        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.documentView = textView
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let textView = scroll.documentView as? ProseTextView else { return }
        context.coordinator.text = text
        if textView.string != text.wrappedValue {
            textView.string = text.wrappedValue
            textView.needsDisplay = true
        }
        if textView.font != font { textView.font = font }
        if textView.textColor != textColor { textView.textColor = textColor }
        if textView.insertionPointColor != caretColor { textView.insertionPointColor = caretColor }
        textView.prompt = prompt
        textView.setAccessibilityPlaceholderValue(prompt)
    }

    /// A scroll view has no size of its own: take what's offered, and let the caller's minimum
    /// height decide when nothing is.
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSScrollView, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 200, height: proposal.height ?? 0)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
        }
    }
}

/// A plain text view that draws its own prompt while empty and says when it gains or loses the
/// keyboard.
final class ProseTextView: NSTextView {
    var prompt = "" {
        didSet { if prompt != oldValue { needsDisplay = true } }
    }
    var onFocusChange: ((Bool) -> Void)?

    override func becomeFirstResponder() -> Bool {
        let became = super.becomeFirstResponder()
        if became { onFocusChange?(true) }
        return became
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned { onFocusChange?(false) }
        return resigned
    }

    override func didChangeText() {
        super.didChangeText()
        // Emptiness may have just changed, and with it whether the prompt shows.
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        // Marked text is an input method mid-composition: the string is still empty, but the
        // user is typing over where the prompt would be.
        guard string.isEmpty, !hasMarkedText(), !prompt.isEmpty, let font else { return }
        // Where the first line of real text goes: the container's origin, in by its padding.
        let origin = textContainerOrigin
        let inset = origin.x + (textContainer?.lineFragmentPadding ?? 0)
        let area = NSRect(x: inset, y: origin.y, width: bounds.width - inset * 2, height: bounds.height - origin.y * 2)
        (prompt as NSString).draw(
            with: area,
            options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
            attributes: [.font: font, .foregroundColor: NSColor.placeholderTextColor]
        )
    }
}
