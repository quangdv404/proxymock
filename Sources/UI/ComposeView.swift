import SwiftUI

struct ComposeView: View {
    @Environment(AppState.self) private var appState
    @State private var method: String = "GET"
    @State private var url: String = "https://jsonplaceholder.typicode.com/posts/1"
    @State private var requestBody: String = ""
    @State private var headers: [String: String] = ["Content-Type": "application/json"]
    @State private var newHeaderKey = ""
    @State private var newHeaderValue = ""
    @State private var isSending = false

    private let methods = ["GET", "POST", "PUT", "DELETE", "PATCH", "HEAD", "OPTIONS"]

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 12) {
                Text("Compose Request").font(.headline)
                Spacer()
                Button {
                    isSending = true
                    appState.sendComposedRequest(method: method, url: url, headers: headers, body: requestBody)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { isSending = false }
                } label: {
                    HStack(spacing: 6) {
                        if isSending {
                            ProgressView().scaleEffect(0.7)
                        } else {
                            Image(systemName: "paperplane.fill")
                        }
                        Text("Send")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(url.isEmpty || isSending)
            }
            .padding(12).background(.bar)
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Method + URL
                    HStack(spacing: 8) {
                        Picker("", selection: $method) {
                            ForEach(methods, id: \.self) { Text($0).tag($0) }
                        }
                        .labelsHidden()
                        .frame(width: 110)
                        .tint(methodColor(method))

                        TextField("https://api.example.com/endpoint", text: $url)
                            .textFieldStyle(.roundedBorder)
                            .font(.body.monospaced())
                    }

                    Divider()

                    // Headers
                    SectionHeader(title: "Headers", icon: "list.bullet")
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(headers.sorted(by: { $0.key < $1.key })), id: \.key) { key, value in
                            HStack {
                                Text(key).font(.callout.monospaced().bold()).foregroundStyle(.blue)
                                Text(": ").foregroundStyle(.secondary)
                                Text(value).font(.callout.monospaced())
                                Spacer()
                                Button { headers.removeValue(forKey: key) } label: {
                                    Image(systemName: "xmark.circle.fill").foregroundStyle(.red.opacity(0.6))
                                }.buttonStyle(.plain)
                            }
                        }
                        HStack {
                            TextField("Key", text: $newHeaderKey).textFieldStyle(.roundedBorder).font(.callout.monospaced()).frame(maxWidth: 200)
                            TextField("Value", text: $newHeaderValue).textFieldStyle(.roundedBorder).font(.callout.monospaced())
                            Button("Add") {
                                guard !newHeaderKey.isEmpty else { return }
                                headers[newHeaderKey] = newHeaderValue
                                newHeaderKey = ""; newHeaderValue = ""
                            }.disabled(newHeaderKey.isEmpty)
                        }
                    }
                    .padding(12).background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                    Divider()

                    // Body
                    SectionHeader(title: "Body", icon: "doc.text")
                    PrettyJSONView(text: $requestBody, minHeight: 200)

                    // Quick templates
                    HStack(spacing: 8) {
                        Text("Templates:").font(.caption).foregroundStyle(.secondary)
                        Button("JSON Post") {
                            method = "POST"
                            headers["Content-Type"] = "application/json"
                            requestBody = "{\n  \"key\": \"value\"\n}"
                        }.buttonStyle(.bordered).controlSize(.small)
                        Button("Form Data") {
                            method = "POST"
                            headers["Content-Type"] = "application/x-www-form-urlencoded"
                            requestBody = "username=test&password=12345"
                        }.buttonStyle(.bordered).controlSize(.small)
                    }
                }
                .padding(20)
            }
        }
    }

    func methodColor(_ m: String) -> Color {
        switch m {
        case "GET": return .blue; case "POST": return .green; case "PUT": return .orange
        case "DELETE": return .red; case "PATCH": return .purple; default: return .gray
        }
    }
}
