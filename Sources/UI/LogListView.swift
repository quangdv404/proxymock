import SwiftUI

struct LogListView: View {
    @Environment(AppState.self) private var appState
    @State private var selectedLogIDs: Set<UUID> = []
    @State private var showBulkSheet = false

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

    /// The single log to show in the detail panel (last-selected or only selected).
    var primarySelectedLog: NetworkLog? {
        guard let id = selectedLogIDs.first else { return nil }
        return appState.logs.first { $0.id == id }
    }

    /// Logs that are currently selected (for the bulk sheet).
    var selectedLogs: [NetworkLog] {
        appState.logs.filter { selectedLogIDs.contains($0.id) }
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

                    // Bulk create Map Local button — visible when ≥1 row selected
                    if !selectedLogIDs.isEmpty {
                        Button {
                            showBulkSheet = true
                        } label: {
                            Label("Create Map Local (\(selectedLogIDs.count))", systemImage: "doc.badge.plus")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.blue)
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                    }

                    Button {
                        appState.clearLogs()
                        selectedLogIDs = []
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
                .animation(.easeInOut(duration: 0.2), value: selectedLogIDs.isEmpty)

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
                        List(selection: $selectedLogIDs) {
                            ForEach(filteredLogs) { log in
                                LogRowView(log: log, isSelected: selectedLogIDs.contains(log.id))
                                    .tag(log.id)
                                    .contextMenu {
                                        Button("Copy URL") {
                                            NSPasteboard.general.clearContents()
                                            NSPasteboard.general.setString(log.url, forType: .string)
                                        }

                                        // If multiple are selected and this row is among them, bulk-create them all;
                                        // otherwise create just this one via the editor.
                                        if selectedLogIDs.count > 1 && selectedLogIDs.contains(log.id) {
                                            Button("Create Map Local for \(selectedLogIDs.count) Selected…") {
                                                showBulkSheet = true
                                            }
                                        } else {
                                            Button("Create Map Local…") {
                                                selectedLogIDs = [log.id]
                                                let newRule = makeMapLocalRule(from: log)
                                                appState.draftMapLocalRule = newRule
                                                appState.selectedSidebarItem = .mapLocal
                                            }
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
            if let log = primarySelectedLog {
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
        .sheet(isPresented: $showBulkSheet) {
            let logs = selectedLogs
            let groups = Array(Set(appState.mapLocalRules.map { $0.group.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })).sorted()
            BulkMapLocalSheet(logs: logs, existingGroups: groups) { rules in
                appState.addMapLocalRules(rules)
                showBulkSheet = false
            } onCancel: {
                showBulkSheet = false
            }
        }
    }

    // MARK: - Helpers

    private func makeMapLocalRule(from log: NetworkLog, group: String = "") -> MapLocalRule {
        var rule = MapLocalRule()
        rule.name = "Mock " + (URL(string: log.url)?.lastPathComponent ?? "API")
        rule.group = group

        if let comps = URLComponents(string: log.url) {
            var clean = comps.scheme ?? "https"
            clean += "://"
            clean += comps.host ?? ""
            if let port = comps.port { clean += ":\(port)" }
            clean += comps.path
            rule.urlPattern = clean + "*"
        } else {
            rule.urlPattern = log.url + "*"
        }

        rule.httpMethod = log.method
        rule.source = .inline
        rule.inlineBody = log.responseBody
        rule.statusCode = log.responseStatusCode ?? 200

        if let ct = log.responseHeaders["Content-Type"] {
            rule.contentType = ct.components(separatedBy: ";").first ?? "application/json"
        }

        return rule
    }
}

// MARK: - Bulk Map Local Sheet

struct BulkMapLocalSheet: View {
    let logs: [NetworkLog]
    let existingGroups: [String]
    let onCreate: ([MapLocalRule]) -> Void
    let onCancel: () -> Void

    @State private var group: String = ""

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Create Map Local Rules")
                        .font(.title2.bold())
                    Text("\(logs.count) request\(logs.count == 1 ? "" : "s") selected")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel") { onCancel() }
                    .keyboardShortcut(.cancelAction)
                Button("Create \(logs.count) Rule\(logs.count == 1 ? "" : "s")") {
                    let rules = logs.map { makeRule(from: $0) }
                    onCreate(rules)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(logs.isEmpty)
            }
            .padding()
            .background(.bar)

            Divider()

            VStack(alignment: .leading, spacing: 16) {
                // Group field
                VStack(alignment: .leading, spacing: 6) {
                    Label("Group / Folder (optional)", systemImage: "folder")
                        .font(.subheadline.bold())

                    HStack {
                        TextField("e.g. User API", text: $group)
                            .textFieldStyle(.roundedBorder)

                        if !existingGroups.isEmpty {
                            Menu {
                                ForEach(existingGroups, id: \.self) { g in
                                    Button(g) { group = g }
                                }
                            } label: {
                                Image(systemName: "chevron.down")
                            }
                            .menuIndicator(.hidden)
                            .fixedSize()
                        }
                    }
                }

                Divider()

                // Preview list
                VStack(alignment: .leading, spacing: 6) {
                    Label("Requests to convert", systemImage: "list.bullet")
                        .font(.subheadline.bold())

                    ScrollView {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(logs) { log in
                                HStack(spacing: 8) {
                                    Text(log.method)
                                        .font(.caption.monospaced().bold())
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(methodColor(log.method))
                                        .clipShape(RoundedRectangle(cornerRadius: 4))

                                    if let status = log.responseStatusCode {
                                        Text("\(status)")
                                            .font(.caption.monospaced().bold())
                                            .foregroundStyle(statusColor(status))
                                            .frame(width: 32)
                                    }

                                    Text(displayURL(log.url))
                                        .font(.caption.monospaced())
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                        .frame(maxWidth: .infinity, alignment: .leading)

                                    // Rule name preview
                                    Text("→ Mock \(URL(string: log.url)?.lastPathComponent ?? "API")")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                .padding(.vertical, 3)
                                .padding(.horizontal, 8)
                                .background(.ultraThinMaterial)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                        }
                    }
                    .frame(maxHeight: 280)
                }

                // Info note
                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.blue)
                    Text("Each rule will use the captured response body as the inline mock. You can edit rules individually in Map Local afterwards.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(10)
                .background(.blue.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .padding()
        }
        .frame(minWidth: 560, minHeight: 420)
    }

    private func makeRule(from log: NetworkLog) -> MapLocalRule {
        var rule = MapLocalRule()
        rule.name = "Mock " + (URL(string: log.url)?.lastPathComponent ?? "API")
        rule.group = group.trimmingCharacters(in: .whitespaces)

        if let comps = URLComponents(string: log.url) {
            var clean = comps.scheme ?? "https"
            clean += "://"
            clean += comps.host ?? ""
            if let port = comps.port { clean += ":\(port)" }
            clean += comps.path
            rule.urlPattern = clean + "*"
        } else {
            rule.urlPattern = log.url + "*"
        }

        rule.httpMethod = log.method
        rule.source = .inline
        rule.inlineBody = log.responseBody
        rule.statusCode = log.responseStatusCode ?? 200

        if let ct = log.responseHeaders["Content-Type"] {
            rule.contentType = ct.components(separatedBy: ";").first ?? "application/json"
        }

        return rule
    }

    private func displayURL(_ url: String) -> String {
        guard let comps = URLComponents(string: url) else { return url }
        return (comps.host ?? "") + comps.path
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

// MARK: - Log Row

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
            if log.isPending {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 35)
            } else if let statusCode = log.responseStatusCode {
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
            if log.isPending {
                Text("...")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .frame(width: 60, alignment: .trailing)
            } else {
                Text(String(format: "%.0fms", log.duration * 1000))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .frame(width: 60, alignment: .trailing)
            }

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
