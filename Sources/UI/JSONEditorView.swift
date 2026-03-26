import SwiftUI
import AppKit

/// A macOS-specific code editor wrapping NSTextView, optimized for JSON editing.
/// Features: syntax highlighting, line-number gutter, horizontal scrolling,
/// smart quote/dash disabled.
struct JSONEditorView: NSViewRepresentable {
    @Binding var text: String

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        // Setup the NSTextView
        let textView = NSTextView()
        textView.autoresizingMask = [.width]
        textView.isRichText = false
        textView.allowsUndo = true

        // Code-editor features
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.smartInsertDeleteEnabled = false

        // Native Search (CMD+F)
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true

        // Prevent auto-wrap
        textView.isHorizontallyResizable = true
        textView.isVerticallyResizable = true
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)

        // Font & styling
        textView.font = .monospacedSystemFont(ofSize: 12.5, weight: .regular)
        textView.backgroundColor = .textBackgroundColor
        textView.textColor = .textColor

        // Comfortable inset so text doesn't hug the left edge
        textView.textContainerInset = NSSize(width: 4, height: 6)

        textView.delegate = context.coordinator

        // Apply initial text
        textView.string = text
        context.coordinator.highlight(textView: textView)

        // Line number ruler
        let lineNumberView = LineNumberRulerView(textView: textView)
        scrollView.verticalRulerView = lineNumberView
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = true

        scrollView.documentView = textView

        // Keep ruler in sync when text changes
        context.coordinator.lineNumberView = lineNumberView

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        if let textView = nsView.documentView as? NSTextView {
            if textView.string != text {
                // Preserve cursor position if possible
                let sel = textView.selectedRange()
                textView.string = text
                let safeEnd = min(sel.location, (text as NSString).length)
                textView.setSelectedRange(NSRange(location: safeEnd, length: 0))
                context.coordinator.highlight(textView: textView)
                context.coordinator.lineNumberView?.needsDisplay = true
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    @MainActor class Coordinator: NSObject, NSTextViewDelegate {
        var parent: JSONEditorView
        weak var lineNumberView: LineNumberRulerView?

        // Regex patterns for JSON tokens
        let keyRegex     = try! NSRegularExpression(pattern: "\"([^\"]+)\"\\s*:")
        let stringRegex  = try! NSRegularExpression(pattern: ":\\s*\"([^\"]*)\"")
        let numberRegex  = try! NSRegularExpression(pattern: ":\\s*(-?\\d+\\.?\\d*)")
        let boolNullRegex = try! NSRegularExpression(pattern: ":\\s*(true|false|null)")

        init(_ parent: JSONEditorView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            self.parent.text = textView.string
            highlight(textView: textView)
            lineNumberView?.needsDisplay = true
        }

        func highlight(textView: NSTextView) {
            let str = textView.string
            let fullRange = NSRange(location: 0, length: str.utf16.count)
            let storage = textView.textStorage

            storage?.beginEditing()

            // 1. Reset to default
            storage?.setAttributes([
                .foregroundColor: NSColor.textColor,
                .font: NSFont.monospacedSystemFont(ofSize: 12.5, weight: .regular)
            ], range: fullRange)

            // 2. Keys → teal
            keyRegex.enumerateMatches(in: str, range: fullRange) { match, _, _ in
                if let r = match?.range(at: 1) {
                    storage?.addAttribute(.foregroundColor, value: NSColor.systemTeal, range: r)
                }
            }

            // 3. String values → orange
            stringRegex.enumerateMatches(in: str, range: fullRange) { match, _, _ in
                if let r = match?.range(at: 1) {
                    storage?.addAttribute(.foregroundColor, value: NSColor.systemOrange, range: r)
                }
            }

            // 4. Numbers → purple
            numberRegex.enumerateMatches(in: str, range: fullRange) { match, _, _ in
                if let r = match?.range(at: 1) {
                    storage?.addAttribute(.foregroundColor, value: NSColor.systemPurple, range: r)
                }
            }

            // 5. Booleans / null → pink
            boolNullRegex.enumerateMatches(in: str, range: fullRange) { match, _, _ in
                if let r = match?.range(at: 1) {
                    storage?.addAttribute(.foregroundColor, value: NSColor.systemPink, range: r)
                }
            }

            storage?.endEditing()
        }
    }
}

// MARK: - Line Number Ruler

final class LineNumberRulerView: NSRulerView {
    weak var textView: NSTextView?

    private let font: NSFont = .monospacedSystemFont(ofSize: 10.5, weight: .regular)
    private let textColor: NSColor = .tertiaryLabelColor
    private let backgroundColor: NSColor = NSColor(white: 0, alpha: 0.04)
    private let borderColor: NSColor = NSColor.separatorColor

    init(textView: NSTextView) {
        self.textView = textView
        super.init(scrollView: textView.enclosingScrollView, orientation: .verticalRuler)
        ruleThickness = 38
    }

    required init(coder: NSCoder) { fatalError() }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let textView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else { return }

        // Fill background
        backgroundColor.setFill()
        rect.fill()

        // Right border
        borderColor.setStroke()
        let border = NSBezierPath()
        border.move(to: NSPoint(x: bounds.maxX - 0.5, y: rect.minY))
        border.line(to: NSPoint(x: bounds.maxX - 0.5, y: rect.maxY))
        border.lineWidth = 1
        border.stroke()

        let visibleRect = textView.visibleRect
        let glyphRange = layoutManager.glyphRange(forBoundingRect: visibleRect, in: textContainer)
        let charRange = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)

        let string = textView.string as NSString
        var lineNumber = 1

        // Count lines before the visible range
        string.enumerateSubstrings(in: NSRange(location: 0, length: charRange.location),
                                   options: [.byLines, .substringNotRequired]) { _, _, _, _ in
            lineNumber += 1
        }

        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor
        ]

        let containerOrigin = textView.textContainerOrigin
        let scrollOffset = textView.enclosingScrollView?.contentView.bounds.origin ?? .zero

        string.enumerateSubstrings(in: charRange,
                                   options: [.byLines, .substringNotRequired]) { [weak self] _, lineRange, _, _ in
            guard let self else { return }
            let glyphIdx = layoutManager.glyphIndexForCharacter(at: lineRange.location)
            var lineFragmentRect = layoutManager.lineFragmentRect(forGlyphAt: glyphIdx, effectiveRange: nil)
            lineFragmentRect.origin.y += containerOrigin.y - scrollOffset.y

            let label = "\(lineNumber)" as NSString
            let size = label.size(withAttributes: attrs)
            let drawRect = NSRect(
                x: 0,
                y: lineFragmentRect.midY - size.height / 2,
                width: self.ruleThickness - 6,
                height: size.height
            )
            label.draw(in: drawRect, withAttributes: attrs.merging([.paragraphStyle: {
                let ps = NSMutableParagraphStyle(); ps.alignment = .right; return ps
            }()]) { $1 })

            lineNumber += 1
        }
    }
}
