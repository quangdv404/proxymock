import SwiftUI
import AppKit

/// A self-contained, feature-rich JSON editor with toolbar, validation,
/// formatting, find & replace, and fullscreen expansion.
///
/// Drop-in replacement for bare `JSONEditorView` usage across the app.
struct PrettyJSONView: View {
    @Binding var text: String
    var isReadOnly: Bool = false
    var showToolbar: Bool = true
    var minHeight: CGFloat = 200

    @State private var coordinator: JSONEditorView.Coordinator?
    @State private var editorHeight: CGFloat = 300
    @State private var dragStartHeight: CGFloat = 300
    @State private var showFullscreen: Bool = false

    // MARK: - Validation

    private var isValidJSON: Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        guard let data = trimmed.data(using: .utf8) else { return false }
        return (try? JSONSerialization.jsonObject(with: data)) != nil
    }

    private var charCount: String {
        let count = text.count
        if count >= 1_000 {
            let formatted = NumberFormatter.localizedString(from: NSNumber(value: count), number: .decimal)
            return "\(formatted) chars"
        }
        return "\(count) chars"
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showToolbar {
                toolbar
            }

            // Editor
            JSONEditorView(
                text: $text,
                isEditable: !isReadOnly,
                onCoordinatorReady: { coord in
                    self.coordinator = coord
                }
            )
            .frame(height: editorHeight)
            .frame(minHeight: minHeight)
            .background(Color(nsColor: .textBackgroundColor))

            // Resize handle
            ResizeHandle()
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            editorHeight = max(minHeight, dragStartHeight + value.translation.height)
                        }
                        .onEnded { _ in
                            dragStartHeight = editorHeight
                        }
                )
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.25)))
        .onAppear {
            editorHeight = max(minHeight, editorHeight)
            dragStartHeight = editorHeight
        }
        .sheet(isPresented: $showFullscreen) {
            FullscreenJSONEditor(text: $text, isReadOnly: isReadOnly)
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 8) {
            // Validation badge
            let valid = isValidJSON
            HStack(spacing: 4) {
                Image(systemName: valid ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(valid ? .green : .red)
                Text(valid ? "Valid" : "Invalid")
                    .font(.caption.bold())
                    .foregroundStyle(valid ? .green : .red)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background((valid ? Color.green : Color.red).opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 5))

            Spacer()

            // Character count
            Text(charCount)
                .font(.caption.monospaced())
                .foregroundStyle(.tertiary)

            Divider().frame(height: 14)

            if !isReadOnly {
                // Format
                Button {
                    formatJSON()
                } label: {
                    Label("Format", systemImage: "text.alignleft")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(!isValidJSON || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .keyboardShortcut("f", modifiers: [.command, .shift])
                .help("Pretty-print JSON (⌘⇧F)")

                // Minify
                Button {
                    minifyJSON()
                } label: {
                    Label("Minify", systemImage: "arrow.down.right.and.arrow.up.left")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(!isValidJSON || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .keyboardShortcut("m", modifiers: [.command, .shift])
                .help("Compact single-line JSON (⌘⇧M)")
            }

            // Copy
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(text.isEmpty)
            .help("Copy to clipboard")

            // Find & Replace
            if !isReadOnly {
                Button {
                    coordinator?.openFindReplace()
                } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Find & Replace (⌘H)")
            }

            Divider().frame(height: 14)

            // Fullscreen
            Button {
                showFullscreen = true
            } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Edit in fullscreen")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(
            Rectangle().frame(height: 1).foregroundStyle(Color.secondary.opacity(0.2)),
            alignment: .bottom
        )
    }

    // MARK: - Actions

    private func formatJSON() {
        guard let data = text.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
              let str = String(data: pretty, encoding: .utf8) else { return }
        text = str
    }

    private func minifyJSON() {
        guard let data = text.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data),
              let compact = try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys]),
              let str = String(data: compact, encoding: .utf8) else { return }
        text = str
    }
}

// MARK: - Fullscreen JSON Editor

/// A modal sheet that provides a large editing surface for JSON.
private struct FullscreenJSONEditor: View {
    @Binding var text: String
    var isReadOnly: Bool = false
    @Environment(\.dismiss) private var dismiss
    @State private var coordinator: JSONEditorView.Coordinator?

    @State private var windowSize = CGSize(width: 900, height: 600)
    @State private var dragStartSize = CGSize(width: 900, height: 600)

    private var isValidJSON: Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        guard let data = trimmed.data(using: .utf8) else { return false }
        return (try? JSONSerialization.jsonObject(with: data)) != nil
    }

    private var charCount: String {
        let count = text.count
        if count >= 1_000 {
            let formatted = NumberFormatter.localizedString(from: NSNumber(value: count), number: .decimal)
            return "\(formatted) chars"
        }
        return "\(count) chars"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 12) {
                Image(systemName: "curlybraces")
                    .font(.title2)
                    .foregroundStyle(.blue)
                Text("JSON Editor")
                    .font(.title2.bold())

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Label("Close", systemImage: "xmark.circle.fill")
                }
                .buttonStyle(.bordered)
                .keyboardShortcut(.cancelAction)
            }
            .padding()
            .background(.bar)

            Divider()

            // Toolbar
            HStack(spacing: 8) {
                // Validation badge
                let valid = isValidJSON
                HStack(spacing: 4) {
                    Image(systemName: valid ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(valid ? .green : .red)
                    Text(valid ? "Valid JSON" : "Invalid JSON")
                        .font(.caption.bold())
                        .foregroundStyle(valid ? .green : .red)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background((valid ? Color.green : Color.red).opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 6))

                Spacer()

                Text(charCount)
                    .font(.caption.monospaced())
                    .foregroundStyle(.tertiary)

                Divider().frame(height: 14)

                if !isReadOnly {
                    Button {
                        formatJSON()
                    } label: {
                        Label("Format", systemImage: "text.alignleft")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(!isValidJSON || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .keyboardShortcut("f", modifiers: [.command, .shift])

                    Button {
                        minifyJSON()
                    } label: {
                        Label("Minify", systemImage: "arrow.down.right.and.arrow.up.left")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(!isValidJSON || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .keyboardShortcut("m", modifiers: [.command, .shift])
                }

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(text.isEmpty)

                if !isReadOnly {
                    Button {
                        coordinator?.openFindReplace()
                    } label: {
                        Label("Find & Replace", systemImage: "magnifyingglass")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(nsColor: .windowBackgroundColor))
            .overlay(
                Rectangle().frame(height: 1).foregroundStyle(Color.secondary.opacity(0.15)),
                alignment: .bottom
            )

            // Full-height editor with corner resize handle
            ZStack(alignment: .bottomTrailing) {
                JSONEditorView(
                    text: $text,
                    isEditable: !isReadOnly,
                    onCoordinatorReady: { coord in
                        self.coordinator = coord
                    }
                )
                .background(Color(nsColor: .textBackgroundColor))

                // Corner resize handle
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(6)
                    .background(Color(nsColor: .windowBackgroundColor).opacity(0.6))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .padding(4)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                windowSize.width = max(600, dragStartSize.width + value.translation.width)
                                windowSize.height = max(400, dragStartSize.height + value.translation.height)
                            }
                            .onEnded { _ in
                                dragStartSize = windowSize
                            }
                    )
                    .help("Drag to resize window")
            }
        }
        .frame(width: windowSize.width, height: windowSize.height)
    }

    private func formatJSON() {
        guard let data = text.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
              let str = String(data: pretty, encoding: .utf8) else { return }
        text = str
    }

    private func minifyJSON() {
        guard let data = text.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data),
              let compact = try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys]),
              let str = String(data: compact, encoding: .utf8) else { return }
        text = str
    }
}
