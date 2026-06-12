import SwiftUI
import AppKit

/// A custom NSTextView that manually handles standard keyboard shortcuts.
/// This is needed in SwiftUI macOS apps if the standard Edit menu is missing.
class CustomJSONTextView: NSTextView {
    // We can call these handlers from performKeyEquivalent
    var onFind: (() -> Void)?
    var onReplace: (() -> Void)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        if flags == .command {
            switch event.charactersIgnoringModifiers {
            case "x":
                if NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: self) { return true }
            case "c":
                if NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: self) { return true }
            case "v":
                if NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: self) { return true }
            case "z":
                if NSApp.sendAction(Selector(("undo:")), to: nil, from: self) { return true }
            case "a":
                if NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: self) { return true }
            case "f":
                onFind?()
                return true
            case "r":
                onReplace?()
                return true
            default:
                break
            }
        } else if flags == [.command, .shift] {
            if event.charactersIgnoringModifiers == "z" {
                if NSApp.sendAction(Selector(("redo:")), to: nil, from: self) { return true }
            }
        }
        return super.performKeyEquivalent(with: event)
    }
}

/// A macOS-specific code editor wrapping NSTextView, optimized for JSON editing.
/// Features: syntax highlighting (debounced, visible-range-only for large docs),
/// line-number gutter with cached offsets, horizontal scrolling.
struct JSONEditorView: NSViewRepresentable {
    @Binding var text: String
    var isEditable: Bool = true
    /// Called once after the view is created, providing a reference to the coordinator
    /// so the parent can call `openFindReplace()`, etc.
    var onCoordinatorReady: ((Coordinator) -> Void)?

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        let textView = CustomJSONTextView()
        textView.autoresizingMask = [.width, .height]
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isEditable = isEditable
        textView.isSelectable = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.smartInsertDeleteEnabled = false
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        
        // Horizontal scrolling (disable word wrap)
        textView.isHorizontallyResizable = true
        textView.isVerticallyResizable = true
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.containerSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        
        textView.font = .monospacedSystemFont(ofSize: 12.5, weight: .regular)
        textView.backgroundColor = .textBackgroundColor
        textView.textColor = .textColor
        textView.textContainerInset = NSSize(width: 4, height: 6)
        textView.delegate = context.coordinator
        textView.onFind = { [weak coordinator = context.coordinator] in coordinator?.openFind() }
        textView.onReplace = { [weak coordinator = context.coordinator] in coordinator?.openFindReplace() }

        textView.string = text
        context.coordinator.textViewRef = textView
        context.coordinator.scheduleHighlight(textView: textView)

        scrollView.documentView = textView

        // Notify parent so it can hold a reference to the coordinator
        DispatchQueue.main.async {
            onCoordinatorReady?(context.coordinator)
        }

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        textView.isEditable = isEditable
        if textView.string != text {
            let sel = textView.selectedRange()
            textView.string = text
            let safeEnd = min(sel.location, (text as NSString).length)
            textView.setSelectedRange(NSRange(location: safeEnd, length: 0))
            context.coordinator.scheduleHighlight(textView: textView)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    // MARK: - Coordinator

    @MainActor final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: JSONEditorView
        /// Weak reference to the underlying NSTextView for programmatic actions
        weak var textViewRef: NSTextView?

        /// Debounce task for syntax highlighting
        private var highlightTask: Task<Void, Never>?

        // Pre-compiled regex patterns (compiled once, reused forever)
        let keyRegex      = try! NSRegularExpression(pattern: "\"([^\"]+)\"\\s*:")
        let stringRegex   = try! NSRegularExpression(pattern: ":\\s*\"([^\"]*)\"")
        let numberRegex   = try! NSRegularExpression(pattern: ":\\s*(-?\\d+\\.?\\d*)")
        let boolNullRegex = try! NSRegularExpression(pattern: ":\\s*(true|false|null)")

        init(_ parent: JSONEditorView) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            scheduleHighlight(textView: textView)
        }

        // MARK: - Find & Replace

        /// Programmatically open the NSTextView find bar with Replace field visible and focus it.
        func openFindReplace() {
            guard let textView = textViewRef else { return }
            let sender = NSMenuItem()
            sender.tag = NSTextFinder.Action.showReplaceInterface.rawValue
            textView.performFindPanelAction(sender)
            focusFindTextField(in: textView)
        }

        /// Programmatically open the NSTextView find bar (find only) and focus it.
        func openFind() {
            guard let textView = textViewRef else { return }
            let sender = NSMenuItem()
            sender.tag = NSTextFinder.Action.showFindInterface.rawValue
            textView.performFindPanelAction(sender)
            focusFindTextField(in: textView)
        }

        private func focusFindTextField(in textView: NSTextView) {
            // The find bar is added asynchronously to the scroll view. 
            // We search for the NSSearchField and force focus on it.
            DispatchQueue.main.async {
                if let scrollView = textView.enclosingScrollView,
                   let searchField = scrollView.findNSSearchField() {
                    textView.window?.makeFirstResponder(searchField)
                }
            }
        }

        /// Debounced highlight: fires 200ms after the last keystroke.
        /// For small documents (< 5 KB) it highlights the whole string;
        /// for larger ones it only processes the visible range.
        func scheduleHighlight(textView: NSTextView) {
            highlightTask?.cancel()
            highlightTask = Task { [weak textView, weak self] in
                // 200ms debounce — tolerable for syntax colouring
                try? await Task.sleep(nanoseconds: 200_000_000)
                guard !Task.isCancelled, let textView, let self else { return }
                await MainActor.run { self.highlight(textView: textView) }
            }
        }

        func highlight(textView: NSTextView) {
            let str = textView.string
            guard !str.isEmpty else { return }

            let storage = textView.textStorage
            let totalLen = str.utf16.count

            // For large documents only colour the visible text + a small padding buffer
            let highlightRange: NSRange
            let bigDocThreshold = 5_000 // bytes
            if totalLen > bigDocThreshold,
               let layoutManager = textView.layoutManager,
               let textContainer = textView.textContainer {
                let visible = textView.visibleRect
                let glyphRange = layoutManager.glyphRange(forBoundingRect: visible, in: textContainer)
                let charRange = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
                // Add 300-char buffer on each side
                let start = max(0, charRange.location - 300)
                let end   = min(totalLen, charRange.location + charRange.length + 300)
                highlightRange = NSRange(location: start, length: end - start)
            } else {
                highlightRange = NSRange(location: 0, length: totalLen)
            }

            storage?.beginEditing()
            storage?.setAttributes([
                .foregroundColor: NSColor.textColor,
                .font: NSFont.monospacedSystemFont(ofSize: 12.5, weight: .regular)
            ], range: highlightRange)

            keyRegex.enumerateMatches(in: str, range: highlightRange) { match, _, _ in
                if let r = match?.range(at: 1) {
                    storage?.addAttribute(.foregroundColor, value: NSColor.systemTeal, range: r)
                }
            }
            stringRegex.enumerateMatches(in: str, range: highlightRange) { match, _, _ in
                if let r = match?.range(at: 1) {
                    storage?.addAttribute(.foregroundColor, value: NSColor.systemOrange, range: r)
                }
            }
            numberRegex.enumerateMatches(in: str, range: highlightRange) { match, _, _ in
                if let r = match?.range(at: 1) {
                    storage?.addAttribute(.foregroundColor, value: NSColor.systemPurple, range: r)
                }
            }
            boolNullRegex.enumerateMatches(in: str, range: highlightRange) { match, _, _ in
                if let r = match?.range(at: 1) {
                    storage?.addAttribute(.foregroundColor, value: NSColor.systemPink, range: r)
                }
            }
            storage?.endEditing()
        }
    }
}

extension NSView {
    func findNSSearchField() -> NSSearchField? {
        if let sf = self as? NSSearchField { return sf }
        for sub in subviews {
            if let sf = sub.findNSSearchField() { return sf }
        }
        return nil
    }
}
