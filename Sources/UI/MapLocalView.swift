import SwiftUI
import AppKit

struct MapLocalView: View {
    @Environment(AppState.self) private var appState
    @State private var editingRule: MapLocalRule?
    @State private var expandedGroups: Set<String> = []

    private var groupedRules: [(String, [MapLocalRule])] {
        let grouped = Dictionary(grouping: appState.mapLocalRules, by: { $0.group.trimmingCharacters(in: .whitespaces) })
        return grouped.map { ($0.key, $0.value) }.sorted {
            if $0.0 == "" && $1.0 != "" { return false }
            if $0.0 != "" && $1.0 == "" { return true }
            return $0.0.localizedCaseInsensitiveCompare($1.0) == .orderedAscending
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("Map Local").font(.headline)
                
                if !appState.mapLocalRules.isEmpty {
                    let allGroups = Set(groupedRules.map { $0.0 })
                    let allCollapsed = expandedGroups.count == allGroups.count && !allGroups.isEmpty
                    Button(action: {
                        if allCollapsed {
                            expandedGroups.removeAll()
                        } else {
                            expandedGroups = allGroups
                        }
                    }) {
                        Text(allCollapsed ? "Expand All" : "Collapse All")
                            .font(.caption)
                    }
                    .buttonStyle(.link)
                    .foregroundStyle(.secondary)
                    
                    Divider().frame(height: 12)
                    
                    let allEnabled = appState.mapLocalRules.allSatisfy { $0.isEnabled }
                    Toggle("Enable All", isOn: Binding(
                        get: { allEnabled },
                        set: { val in
                            var updatedRules = appState.mapLocalRules
                            for i in updatedRules.indices {
                                updatedRules[i].isEnabled = val
                            }
                            appState.mapLocalRules = updatedRules
                            appState.saveMapLocalRules()
                        }
                    ))
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .font(.caption)
                }
                
                Spacer()
                
                Button { importYaml() } label: { Label("Import YAML", systemImage: "square.and.arrow.down") }
                    .buttonStyle(.bordered)
                
                Button { editingRule = MapLocalRule() } label: { Label("Add Rule", systemImage: "plus") }
                    .buttonStyle(.borderedProminent)
                    
                Text("\(appState.mapLocalRules.count) rules").font(.caption.monospaced()).foregroundStyle(.secondary)
            }
            .padding(12).background(.bar)
            Divider()

            if appState.mapLocalRules.isEmpty {
                EmptyFeatureView(icon: "doc.on.doc", title: "No Map Local Rules",
                    subtitle: "Map URL patterns to local files on disk. Great for offline dev or testing custom responses.") {
                    editingRule = MapLocalRule()
                }
            } else {
                List {
                    ForEach(groupedRules, id: \.0) { groupName, rules in
                        DisclosureGroup(
                            isExpanded: Binding(
                                get: { !expandedGroups.contains(groupName) },
                                set: { isExpanded in
                                    if isExpanded {
                                        expandedGroups.remove(groupName)
                                    } else {
                                        expandedGroups.insert(groupName)
                                    }
                                }
                            ),
                            content: {
                                ForEach(rules) { rule in
                                    HStack(spacing: 12) {
                                        Toggle("", isOn: Binding(
                                            get: { rule.isEnabled },
                                            set: { val in var r = rule; r.isEnabled = val; appState.updateMapLocalRule(r) }
                                        )).labelsHidden()

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(rule.name).font(.headline)
                                            HStack(spacing: 6) {
                                                Text(rule.httpMethod).font(.caption.monospaced().bold())
                                                    .foregroundStyle(.white).padding(.horizontal, 4).padding(.vertical, 1)
                                                    .background(.blue).clipShape(RoundedRectangle(cornerRadius: 3))
                                                Text(rule.urlPattern).font(.caption.monospaced()).foregroundStyle(.secondary)
                                            }
                                            if rule.source == .file {
                                                Text("→ File: \(rule.localFilePath.isEmpty ? "None" : (rule.localFilePath as NSString).lastPathComponent)")
                                                    .font(.caption.monospaced()).foregroundStyle(.green).lineLimit(1)
                                            } else {
                                                Text("→ Inline Text")
                                                    .font(.caption.monospaced()).foregroundStyle(.blue).lineLimit(1)
                                            }
                                        }
                                        Spacer()
                                        Text("\(rule.statusCode)").font(.caption.monospaced().bold()).foregroundStyle(.green)
                                        Button { editingRule = rule } label: { Image(systemName: "pencil") }.buttonStyle(.plain)
                                        Button { appState.deleteMapLocalRule(id: rule.id) } label: { Image(systemName: "trash").foregroundStyle(.red) }.buttonStyle(.plain)
                                    }
                                    .padding(.horizontal, 24).opacity(rule.isEnabled ? 1 : 0.5)
                                }
                            },
                            label: {
                                MapLocalGroupHeader(groupName: groupName, rules: rules)
                            }
                        )
                    }
                }.listStyle(.sidebar)
            }
        }
        .sheet(item: $editingRule) { rule in
            let groups = Array(Set(appState.mapLocalRules.map { $0.group.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })).sorted()
            MapLocalEditor(rule: rule, existingGroups: groups, isNew: !appState.mapLocalRules.contains { $0.id == rule.id }) { saved in
                if appState.mapLocalRules.contains(where: { $0.id == saved.id }) { appState.updateMapLocalRule(saved) }
                else { appState.addMapLocalRule(saved) }
                editingRule = nil
            } onCancel: { editingRule = nil }
        }
        .onAppear { checkDraftRule() }
        .onChange(of: appState.draftMapLocalRule) { _, _ in checkDraftRule() }
    }
    
    private func importYaml() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.yaml]
        
        panel.begin { response in
            if response == .OK, let url = panel.url {
                do {
                    let yamlString = try String(contentsOf: url, encoding: .utf8)
                    let newRules = try MapLocalYamlTemplate.parse(yamlString: yamlString)
                    appState.mapLocalRules.append(contentsOf: newRules)
                    appState.saveMapLocalRules()
                } catch {
                    print("YAML Import Error: \(error)")
                }
            }
        }
    }
    
    private func checkDraftRule() {
        if let draft = appState.draftMapLocalRule {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                appState.draftMapLocalRule = nil
                editingRule = draft
            }
        }
    }
}

struct MapLocalGroupHeader: View {
    let groupName: String
    let rules: [MapLocalRule]
    @Environment(AppState.self) private var appState

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: groupName.isEmpty ? "folder.badge.minus" : "folder.fill")
                .foregroundStyle(.blue)
            Text(groupName.isEmpty ? "Uncategorized" : groupName)
                .font(.headline)
                .foregroundStyle(.primary)
            Spacer()
            
            let allEnabled = rules.allSatisfy { $0.isEnabled }
            
            Button {
                let ruleIds = Set(rules.map { $0.id })
                appState.mapLocalRules.removeAll { ruleIds.contains($0.id) }
                appState.saveMapLocalRules()
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
            .help("Delete Folder and all its rules")
            
            Toggle(allEnabled ? "" : "", isOn: Binding(
                get: { allEnabled },
                set: { val in
                    var updatedRules = appState.mapLocalRules
                    for rule in rules {
                        if let idx = updatedRules.firstIndex(where: { $0.id == rule.id }) {
                            updatedRules[idx].isEnabled = val
                        }
                    }
                    appState.mapLocalRules = updatedRules
                    appState.saveMapLocalRules()
                }
            ))
            .toggleStyle(.switch)
            .controlSize(.mini)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 16)
    }
}

struct MapLocalEditor: View {
    @State var rule: MapLocalRule
    let existingGroups: [String]
    let isNew: Bool
    let onSave: (MapLocalRule) -> Void
    let onCancel: () -> Void

    private let methods = ["*", "GET", "POST", "PUT", "DELETE"]
    private let contentTypes = [
        "application/json", "text/html", "text/plain", "text/xml", "application/xml", 
        "image/png", "image/jpeg", "image/gif", "image/svg+xml", "image/webp", "text/css", 
        "application/javascript", "text/csv", "application/pdf", "text/markdown", 
        "application/zip", "audio/mpeg", "video/mp4",
        "application/x-www-form-urlencoded", "multipart/form-data"
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(isNew ? "New Map Local" : "Edit Map Local").font(.title2.bold())
                Spacer()
                Button("Cancel") { onCancel() }.keyboardShortcut(.cancelAction)
                Button("Save") { onSave(rule) }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }.padding().background(.bar)
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    LabeledField(label: "Name") { TextField("Rule name", text: $rule.name).textFieldStyle(.roundedBorder) }
                    LabeledField(label: "Group / Folder") {
                        HStack {
                            TextField("Optional", text: $rule.group).textFieldStyle(.roundedBorder)
                            if !existingGroups.isEmpty {
                                Menu {
                                    ForEach(existingGroups, id: \.self) { group in
                                        Button(group) { rule.group = group }
                                    }
                                } label: {
                                    Image(systemName: "chevron.down")
                                }
                                .menuIndicator(.hidden)
                                .fixedSize()
                            }
                        }
                    }
                    Toggle("Enabled", isOn: $rule.isEnabled)
                    Divider()
                    LabeledField(label: "URL Pattern") { TextField("*/api/config*", text: $rule.urlPattern).textFieldStyle(.roundedBorder).font(.body.monospaced()) }
                    LabeledField(label: "HTTP Method") {
                        Picker("", selection: $rule.httpMethod) {
                            ForEach(methods, id: \.self) { Text($0 == "*" ? "Any" : $0).tag($0) }
                        }.labelsHidden().frame(width: 150)
                    }
                    Divider()
                    LabeledField(label: "Source") {
                        Picker("", selection: $rule.source) {
                            Text("Inline Text").tag(MapLocalRule.DataSource.inline)
                            Text("Local File").tag(MapLocalRule.DataSource.file)
                        }.pickerStyle(.segmented).frame(width: 250)
                    }

                    if rule.source == .file {
                        LabeledField(label: "File Path") {
                            HStack {
                                TextField("/path/to/response.json", text: $rule.localFilePath).textFieldStyle(.roundedBorder).font(.body.monospaced())
                                Button("Browse…") { browseFile() }.buttonStyle(.bordered)
                            }
                        }
                    } else {
                        LabeledField(label: "Response Body") {
                            InlineBodyEditor(text: $rule.inlineBody, onImport: importFile)
                        }
                    }
                    
                    Divider()

                    LabeledField(label: "Content-Type") {
                        Picker("", selection: $rule.contentType) {
                            ForEach(contentTypes, id: \.self) { Text($0).tag($0) }
                        }.labelsHidden().frame(width: 250)
                    }
                    LabeledField(label: "Status Code") {
                        TextField("200", value: $rule.statusCode, format: .number).textFieldStyle(.roundedBorder).frame(width: 100)
                    }
                    LabeledField(label: "Delay") {
                        HStack {
                            Slider(value: $rule.delaySeconds, in: 0...10, step: 0.5)
                            Text("\(rule.delaySeconds, specifier: "%.1f")s").font(.caption.monospaced())
                        }.frame(width: 250)
                    }
                }.padding(20)
            }
        }.frame(minWidth: 600, minHeight: 450)
    }

    private func browseFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.begin { response in
            if response == .OK, let url = panel.url {
                rule.localFilePath = url.path
                if let newType = detectContentType(from: url) {
                    if !contentTypes.contains(newType) {
                        rule.contentType = newType // Will still bind behind the scenes
                    } else {
                        rule.contentType = newType
                    }
                }
            }
        }
    }
    
    private func importFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.begin { response in
            if response == .OK, let url = panel.url {
                if let text = try? String(contentsOf: url, encoding: .utf8) {
                    rule.inlineBody = text
                } else {
                    // Cannot be read as text (binary file like PDF/Image).
                    // Automatically switch the rule mode to stream from disk!
                    rule.source = .file
                    rule.localFilePath = url.path
                }
                if let newType = detectContentType(from: url) {
                    if !contentTypes.contains(newType) {
                        rule.contentType = newType
                    } else {
                        rule.contentType = newType
                    }
                }
            }
        }
    }
    
    private func detectContentType(from url: URL) -> String? {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "json": return "application/json"
        case "html", "htm": return "text/html"
        case "txt": return "text/plain"
        case "xml": return "application/xml"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "svg": return "image/svg+xml"
        case "webp": return "image/webp"
        case "css": return "text/css"
        case "js": return "application/javascript"
        case "csv": return "text/csv"
        case "pdf": return "application/pdf"
        case "md", "markdown": return "text/markdown"
        case "zip": return "application/zip"
        case "mp3": return "audio/mpeg"
        case "mp4": return "video/mp4"
        default: return nil
        }
    }
}

// MARK: - Inline Body Editor

/// A self-contained response body editor.
struct InlineBodyEditor: View {
    @Binding var text: String
    let onImport: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Spacer()
                Button {
                    onImport()
                } label: {
                    Label("Import from File...", systemImage: "square.and.arrow.down")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            PrettyJSONView(text: $text, minHeight: 200)
        }
    }
}

/// A thin draggable resize handle bar.
struct ResizeHandle: View {
    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            HStack(spacing: 3) {
                ForEach(0..<3, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 1)
                        .frame(width: 20, height: 2)
                        .foregroundStyle(Color.secondary.opacity(0.4))
                }
            }
        }
        .frame(height: 12)
        .overlay(Rectangle().frame(height: 1).foregroundStyle(Color.secondary.opacity(0.15)), alignment: .top)
        .onHover { inside in
            if inside {
                NSCursor.resizeUpDown.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}
