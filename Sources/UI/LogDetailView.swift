import SwiftUI

struct LogDetailView: View {
    let log: NetworkLog

    @State private var selectedTab: DetailTab = .request

    enum DetailTab: String, CaseIterable {
        case request = "Request"
        case response = "Response"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(log.method)
                        .font(.headline.monospaced().bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(methodColor(log.method))
                        .clipShape(RoundedRectangle(cornerRadius: 5))

                    if log.isPending {
                        ProgressView()
                            .controlSize(.small)
                            .padding(.leading, 4)
                    } else if let statusCode = log.responseStatusCode {
                        Text("\(statusCode)")
                            .font(.headline.monospaced())
                            .foregroundStyle(statusColor(statusCode))
                    }

                    if log.isMocked {
                        Text("MOCKED")
                            .font(.caption.bold())
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.orange.opacity(0.15))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }

                    Spacer()

                    if log.isPending {
                        Text("...")
                            .font(.callout.monospaced())
                            .foregroundStyle(.secondary)
                    } else {
                        Text(String(format: "%.2fms", log.duration * 1000))
                            .font(.callout.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }

                Text(log.url)
                    .font(.callout.monospaced())
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)

                Text(log.timestamp.formatted(date: .abbreviated, time: .standard))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding()
            .background(.bar)

            Divider()

            // Tabs
            Picker("", selection: $selectedTab) {
                ForEach(DetailTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch selectedTab {
                    case .request:
                        HeadersSection(title: "Request Headers", headers: log.requestHeaders)
                        BodySection(title: "Request Body", content: log.requestBody)
                    case .response:
                        HeadersSection(title: "Response Headers", headers: log.responseHeaders)
                        BodySection(title: "Response Body", content: log.responseBody)
                    }
                }
                .padding()
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func methodColor(_ method: String) -> Color {
        switch method.uppercased() {
        case "GET": return .blue
        case "POST": return .green
        case "PUT": return .orange
        case "DELETE": return .red
        case "PATCH": return .purple
        case "CONNECT": return .gray
        default: return .gray
        }
    }

    private func statusColor(_ code: Int) -> Color {
        switch code {
        case 200..<300: return .green
        case 300..<400: return .orange
        case 400..<500: return .red
        case 500...: return .red
        default: return .secondary
        }
    }
}

struct HeadersSection: View {
    let title: String
    let headers: [String: String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: "list.bullet")
                .font(.subheadline.bold())

            if headers.isEmpty {
                Text("No headers")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .italic()
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(headers.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                        HStack(alignment: .top, spacing: 8) {
                            Text(key)
                                .font(.caption.monospaced().bold())
                                .foregroundStyle(.blue)
                                .frame(minWidth: 120, alignment: .trailing)
                            Text(value)
                                .font(.caption.monospaced())
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .padding(10)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }
}

struct BodySection: View {
    let title: String
    let content: String
    @State private var text: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: "doc.text")
                .font(.subheadline.bold())

            if content.isEmpty {
                Text("Empty body")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .italic()
            } else {
                PrettyJSONView(text: $text, isReadOnly: true, minHeight: 200)
            }
        }
        .onAppear {
            text = prettyPrintedJSON(content)
        }
        .onChange(of: content) { _, newContent in
            text = prettyPrintedJSON(newContent)
        }
    }

    private func prettyPrintedJSON(_ string: String) -> String {
        guard let data = string.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data),
              let prettyData = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]),
              let prettyString = String(data: prettyData, encoding: .utf8) else {
            return string
        }
        return prettyString
    }
}
