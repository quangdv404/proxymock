import SwiftUI
import AppKit

/// A macOS-specific code editor wrapping NSTextView, optimized for JSON editing.
/// It provides basic syntax highlighting, horizontal scrolling, and disables smart quotes/dashes.
struct JSONEditorView: NSViewRepresentable {
    @Binding var text: String
    
    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        
        // Setup the NSTextView
        let textView = NSTextView()
        textView.autoresizingMask = [.width, .height]
        textView.isRichText = false
        textView.allowsUndo = true
        
        // Code-editor features
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.smartInsertDeleteEnabled = false
        
        // Native Search capabilities (CMD+F)
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        
        // Important: Stop NSTextView from automatically wrapping text to window width!
        textView.isHorizontallyResizable = true
        textView.isVerticallyResizable = true
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        
        // Font & styling
        textView.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.backgroundColor = .textBackgroundColor
        textView.textColor = .textColor
        
        textView.delegate = context.coordinator
        
        // Apply initial text
        textView.string = text
        
        // Apply syntax highlighting
        context.coordinator.highlight(textView: textView)
        
        scrollView.documentView = textView
        return scrollView
    }
    
    func updateNSView(_ nsView: NSScrollView, context: Context) {
        if let textView = nsView.documentView as? NSTextView {
            if textView.string != text {
                textView.string = text
                context.coordinator.highlight(textView: textView)
            }
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    @MainActor class Coordinator: NSObject, NSTextViewDelegate {
        var parent: JSONEditorView
        
        // Regex patterns for JSON tokens
        let keyRegex = try! NSRegularExpression(pattern: "\"([^\"]+)\"\\s*:")
        let stringRegex = try! NSRegularExpression(pattern: ":\\s*\"([^\"]*)\"")
        let numberRegex = try! NSRegularExpression(pattern: ":\\s*(-?\\d+\\.?\\d*)")
        let boolNullRegex = try! NSRegularExpression(pattern: ":\\s*(true|false|null)")
        
        init(_ parent: JSONEditorView) {
            self.parent = parent
        }
        
        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            self.parent.text = textView.string
            highlight(textView: textView)
        }
        
        func highlight(textView: NSTextView) {
            let str = textView.string
            let fullRange = NSRange(location: 0, length: str.utf16.count)
            let storage = textView.textStorage
            
            storage?.beginEditing()
            
            // 1. Reset all text to default color and font
            storage?.setAttributes([
                .foregroundColor: NSColor.textColor,
                .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
            ], range: fullRange)
            
            // 2. Highlight Keys (e.g. "name":) -> Blue/Cyan
            let keyColor = NSColor.systemTeal
            keyRegex.enumerateMatches(in: str, range: fullRange) { match, _, _ in
                if let r = match?.range(at: 1) { storage?.addAttribute(.foregroundColor, value: keyColor, range: r) }
            }
            
            // 3. Highlight Strings (e.g. : "value") -> Orange/Red
            let stringColor = NSColor.systemOrange
            stringRegex.enumerateMatches(in: str, range: fullRange) { match, _, _ in
                if let r = match?.range(at: 1) { storage?.addAttribute(.foregroundColor, value: stringColor, range: r) }
            }
            
            // 4. Highlight Numbers (e.g. : 123) -> Purple/Pink
            let numberColor = NSColor.systemPurple
            numberRegex.enumerateMatches(in: str, range: fullRange) { match, _, _ in
                if let r = match?.range(at: 1) { storage?.addAttribute(.foregroundColor, value: numberColor, range: r) }
            }
            
            // 5. Highlight Booleans & Null (e.g. : true) -> Pink/Rose
            let boolColor = NSColor.systemPink
            boolNullRegex.enumerateMatches(in: str, range: fullRange) { match, _, _ in
                if let r = match?.range(at: 1) { storage?.addAttribute(.foregroundColor, value: boolColor, range: r) }
            }
            
            storage?.endEditing()
        }
    }
}
