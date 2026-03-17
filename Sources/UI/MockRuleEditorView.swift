import SwiftUI

struct MockRuleEditorView: View {
    @State var rule: MockRule
    let isNew: Bool
    let onSave: (MockRule) -> Void
    let onCancel: () -> Void

    @State private var newHeaderKey = ""
    @State private var newHeaderValue = ""

    private let methods = ["*", "GET", "POST", "PUT", "DELETE", "PATCH", "HEAD", "OPTIONS"]
    private let commonStatusCodes = [200, 201, 204, 301, 302, 400, 401, 403, 404, 405, 500, 502, 503]

    var body: some View {
        VStack(spacing: 0) {
            // Header bar
            HStack {
                Text(isNew ? "New Mock Rule" : "Edit Mock Rule")
                    .font(.title2.bold())
                Spacer()
                Button("Cancel", role: .cancel) { onCancel() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") { onSave(rule) }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(rule.name.isEmpty || rule.urlPattern.isEmpty)
            }
            .padding()
            .background(.bar)

            Divider()

            // Scrollable content — using ScrollView + VStack instead of Form
            // because Form inside sheet has text field focus issues on macOS
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {

                    // --- General ---
                    SectionHeader(title: "General", icon: "info.circle")

                    LabeledField(label: "Rule Name") {
                        TextField("e.g. Mock Login API", text: $rule.name)
                            .textFieldStyle(.roundedBorder)
                    }

                    Toggle("Enabled", isOn: $rule.isEnabled)
                        .toggleStyle(.switch)

                    Divider()

                    // --- Request Matching ---
                    SectionHeader(title: "Request Matching", icon: "target")

                    LabeledField(label: "URL Pattern") {
                        TextField("e.g. */api/login* or regex:.*/users/[0-9]+", text: $rule.urlPattern)
                            .textFieldStyle(.roundedBorder)
                            .font(.body.monospaced())
                    }

                    LabeledField(label: "HTTP Method") {
                        Picker("", selection: $rule.httpMethod) {
                            ForEach(methods, id: \.self) { method in
                                Text(method == "*" ? "Any Method (*)" : method).tag(method)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 200)
                    }

                    Text("Use `*` for wildcard matching, or prefix with `regex:` for regex.\nExamples: `*/api/users*`, `*login*`, `regex:.*/v[0-9]+/users.*`")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Divider()

                    // --- Response ---
                    SectionHeader(title: "Response", icon: "arrow.down.doc")

                    LabeledField(label: "Status Code") {
                        Picker("", selection: $rule.responseStatusCode) {
                            ForEach(commonStatusCodes, id: \.self) { code in
                                Text("\(code) — \(statusMessage(code))").tag(code)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 250)
                    }

                    LabeledField(label: "Delay") {
                        HStack {
                            Slider(value: $rule.delaySeconds, in: 0...10, step: 0.5)
                            Text("\(rule.delaySeconds, specifier: "%.1f")s")
                                .font(.callout.monospaced())
                                .frame(width: 45)
                        }
                    }

                    Divider()

                    // --- Response Headers ---
                    SectionHeader(title: "Response Headers", icon: "list.bullet.rectangle")

                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(rule.responseHeaders.sorted(by: { $0.key < $1.key })), id: \.key) { key, value in
                            HStack {
                                Text(key)
                                    .font(.callout.monospaced().bold())
                                    .foregroundStyle(.blue)
                                Text(": ")
                                    .foregroundStyle(.secondary)
                                Text(value)
                                    .font(.callout.monospaced())
                                Spacer()
                                Button {
                                    rule.responseHeaders.removeValue(forKey: key)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.red.opacity(0.6))
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.vertical, 2)
                        }

                        HStack {
                            TextField("Key", text: $newHeaderKey)
                                .textFieldStyle(.roundedBorder)
                                .font(.callout.monospaced())
                                .frame(maxWidth: 200)
                            TextField("Value", text: $newHeaderValue)
                                .textFieldStyle(.roundedBorder)
                                .font(.callout.monospaced())
                            Button("Add") {
                                guard !newHeaderKey.isEmpty else { return }
                                rule.responseHeaders[newHeaderKey] = newHeaderValue
                                newHeaderKey = ""
                                newHeaderValue = ""
                            }
                            .disabled(newHeaderKey.isEmpty)
                        }
                    }
                    .padding(12)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                    Divider()

                    // --- Response Body ---
                    SectionHeader(title: "Response Body", icon: "doc.text")

                    HStack {
                        Spacer()
                        Button("Format JSON") { formatJSON() }
                            .buttonStyle(.bordered)
                    }

                    TextEditor(text: $rule.responseBody)
                        .font(.system(.body, design: .monospaced))
                        .disableAutocorrection(true)
                        .frame(minHeight: 180)
                        .padding(4)
                        .background(Color(nsColor: .textBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .onChange(of: rule.responseBody) { newValue in
                            let fixed = newValue.replacingOccurrences(of: "“", with: "\"").replacingOccurrences(of: "”", with: "\"")
                            if fixed != newValue { rule.responseBody = fixed }
                        }
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                        )
                }
                .padding(20)
            }
        }
        .frame(minWidth: 650, idealWidth: 700, minHeight: 650, idealHeight: 750)
    }

    private func formatJSON() {
        guard let data = rule.responseBody.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data),
              let prettyData = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]),
              let prettyString = String(data: prettyData, encoding: .utf8) else {
            return
        }
        rule.responseBody = prettyString
    }

    private func statusMessage(_ code: Int) -> String {
        switch code {
        case 200: return "OK"
        case 201: return "Created"
        case 204: return "No Content"
        case 301: return "Moved Permanently"
        case 302: return "Found"
        case 400: return "Bad Request"
        case 401: return "Unauthorized"
        case 403: return "Forbidden"
        case 404: return "Not Found"
        case 405: return "Method Not Allowed"
        case 500: return "Internal Server Error"
        case 502: return "Bad Gateway"
        case 503: return "Service Unavailable"
        default: return "Unknown"
        }
    }
}

