import SwiftUI

struct LogListView: View {
    @Environment(AppState.self) private var appState
    @State private var selectedLogID: UUID?

    private let methods = ["ALL", "GET", "POST", "PUT", "DELETE", "PATCH", "CONNECT"]

    var filteredLogs: [NetworkLog] {
        if appState.logSearchText.isEmpty && appState.logMethodFilter == "ALL" {
            return appState.logs
        }
        
        return appState.logs.filter { log in
            let matchesMethod = appState.logMethodFilter == "ALL" || log.method.uppercased() == appState.logMethodFilter
            let matchesSearch = appState.logSearchText.isEmpty ||
                log.url.localizedCaseInsensitiveContains(appState.logSearchText) ||
                log.method.localizedCaseInsensitiveContains(appState.logSearchText) ||
                (log.responseStatusCode.map { "\($0)" } ?? "").contains(appState.logSearchText)
            return matchesMethod && matchesSearch
        }
    }

    var selectedLog: NetworkLog? {
        guard let id = selectedLogID else { return nil }
        return appState.logs.first { $0.id == id }
    }

    var body: some View {
        @Bindable var state = appState
        
        HStack(spacing: 0) {
            // Left panel — log list
            VStack(spacing: 0) {
                // Toolbar
                HStack(spacing: 12) {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField("Filter by URL, method, or status...", text: $state.logSearchText)
                            .textFieldStyle(.plain)
                    }
                    .padding(8)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                    Picker("Method", selection: $state.logMethodFilter) {
                        ForEach(methods, id: \.self) { method in
                            Text(method).tag(method)
                        }
                    }
                    .frame(width: 110)

                    Button {
                        appState.clearLogs()
                        selectedLogID = nil
                    } label: {
                        Image(systemName: "trash")
                    }
                    .help("Clear all logs")

                    Text("\(filteredLogs.count) requests")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .background(.bar)

                Divider()

                // Log entries
                if filteredLogs.isEmpty {
                    VStack(spacing: 16) {
                        Spacer()
                        Image(systemName: "network.slash")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)
                        Text("No requests captured yet")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                        if !appState.isRunning {
                            Text("Start the proxy to begin capturing traffic")
                                .font(.callout)
                                .foregroundStyle(.tertiary)
                        }
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    ScrollViewReader { proxy in
                        List(selection: $selectedLogID) {
                            ForEach(filteredLogs) { log in
                                LogRowView(log: log, isSelected: selectedLogID == log.id)
                                    .tag(log.id)
                                    .contextMenu {
                                        Button("Copy URL") {
                                            NSPasteboard.general.clearContents()
                                            NSPasteboard.general.setString(log.url, forType: .string)
                                        }
                                        Button("Create Map Local...") {
                                            var newRule = MapLocalRule()
                                            newRule.name = "Mock " + (URL(string: log.url)?.lastPathComponent ?? "API")
                                            
                                            // Escape query parameters and create a clean wildcard pattern
                                            if let comps = URLComponents(string: log.url) {
                                                var clean = comps.scheme ?? "https"
                                                clean += "://"
                                                clean += comps.host ?? ""
                                                if let port = comps.port { clean += ":\(port)" }
                                                clean += comps.path
                                                newRule.urlPattern = clean + "*"
                                            } else {
                                                newRule.urlPattern = log.url + "*"
                                            }
                                            
                                            newRule.httpMethod = log.method
                                            newRule.source = .inline
                                            newRule.inlineBody = log.responseBody
                                            
                                            if let ct = log.responseHeaders["Content-Type"] {
                                                newRule.contentType = ct.components(separatedBy: ";").first ?? "application/json"
                                            }
                                            
                                            appState.draftMapLocalRule = newRule
                                            appState.selectedSidebarItem = .mapLocal
                                        }
                                        Divider()
                                        Button("Block This Domain") {
                                            if let host = URL(string: log.url)?.host {
                                                let exists = appState.domainFilterRules.contains { $0.domain == host && $0.listType == .block }
                                                if !exists {
                                                    appState.domainFilterRules.append(DomainFilterRule(domain: host, listType: .block))
                                                    appState.saveDomainFilters()
                                                }
                                            }
                                        }
                                        Button("Allow This Domain") {
                                            if let host = URL(string: log.url)?.host {
                                                let exists = appState.domainFilterRules.contains { $0.domain == host && $0.listType == .allow }
                                                if !exists {
                                                    appState.domainFilterRules.append(DomainFilterRule(domain: host, listType: .allow))
                                                    appState.saveDomainFilters()
                                                }
                                            }
                                        }
                                    }
                            }
                        }
                        .listStyle(.plain)
                    }
                }
            }
            .frame(minWidth: 450, idealWidth: 550)

            Divider()

            // Right panel — detail
            if let log = selectedLog {
                LogDetailView(log: log)
                    .frame(minWidth: 350, idealWidth: 400)
                    .id(log.id)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "sidebar.right")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                    Text("Select a request to view details")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .frame(minWidth: 350)
            }
        }
    }
}

struct LogRowView: View {
    let log: NetworkLog
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            // Method badge
            Text(log.method)
                .font(.caption.monospaced().bold())
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .frame(width: 65)
                .background(methodColor(log.method))
                .clipShape(RoundedRectangle(cornerRadius: 4))

            // Status code
            if let statusCode = log.responseStatusCode {
                Text("\(statusCode)")
                    .font(.caption.monospaced().bold())
                    .foregroundStyle(statusColor(statusCode))
                    .frame(width: 35)
            } else {
                Text("---")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .frame(width: 35)
            }

            // URL
            Text(log.url)
                .font(.callout.monospaced())
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Badges
            if log.isMocked {
                Text("MOCK")
                    .font(.caption2.bold())
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(.orange.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            }

            if log.isHTTPS {
                Image(systemName: "lock.fill")
                    .font(.caption2)
                    .foregroundStyle(.green)
            }

            // Duration
            Text(String(format: "%.0fms", log.duration * 1000))
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .trailing)

            // Timestamp
            Text(log.timestamp, style: .time)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(width: 70)
        }
        .padding(.vertical, 4)
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

extension NetworkLog: Hashable {
    static func == (lhs: NetworkLog, rhs: NetworkLog) -> Bool {
        lhs.id == rhs.id
    }
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
