import SwiftUI

struct MapRemoteView: View {
    @Environment(AppState.self) private var appState
    @State private var editingRule: MapRemoteRule?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("Map Remote").font(.headline)
                Spacer()
                Button { editingRule = MapRemoteRule() } label: { Label("Add Rule", systemImage: "plus") }
                    .buttonStyle(.borderedProminent)
                Text("\(appState.mapRemoteRules.count) rules").font(.caption.monospaced()).foregroundStyle(.secondary)
            }
            .padding(12).background(.bar)
            Divider()

            if appState.mapRemoteRules.isEmpty {
                EmptyFeatureView(icon: "arrow.triangle.branch", title: "No Map Remote Rules",
                    subtitle: "Redirect API requests to a different server. E.g., redirect production → localhost for testing.") {
                    editingRule = MapRemoteRule()
                }
            } else {
                List {
                    ForEach(appState.mapRemoteRules) { rule in
                        HStack(spacing: 12) {
                            Toggle("", isOn: Binding(
                                get: { rule.isEnabled },
                                set: { val in var r = rule; r.isEnabled = val; appState.updateMapRemoteRule(r) }
                            )).labelsHidden()

                            VStack(alignment: .leading, spacing: 2) {
                                Text(rule.name).font(.headline)
                                HStack(spacing: 4) {
                                    Text(rule.sourcePattern).font(.caption.monospaced()).foregroundStyle(.red)
                                    Image(systemName: "arrow.right").font(.caption2).foregroundStyle(.secondary)
                                    Text(rule.destinationURL).font(.caption.monospaced()).foregroundStyle(.green)
                                }
                                if rule.preservePath {
                                    Text("Path preserved").font(.caption2).foregroundStyle(.orange)
                                }
                            }
                            Spacer()
                            Button { editingRule = rule } label: { Image(systemName: "pencil") }.buttonStyle(.plain)
                            Button { appState.deleteMapRemoteRule(id: rule.id) } label: { Image(systemName: "trash").foregroundStyle(.red) }.buttonStyle(.plain)
                        }
                        .padding(.vertical, 4).opacity(rule.isEnabled ? 1 : 0.5)
                    }
                }.listStyle(.plain)
            }
        }
        .sheet(item: $editingRule) { rule in
            MapRemoteEditor(rule: rule, isNew: !appState.mapRemoteRules.contains { $0.id == rule.id }) { saved in
                if appState.mapRemoteRules.contains(where: { $0.id == saved.id }) { appState.updateMapRemoteRule(saved) }
                else { appState.addMapRemoteRule(saved) }
                editingRule = nil
            } onCancel: { editingRule = nil }
        }
    }
}

struct MapRemoteEditor: View {
    @State var rule: MapRemoteRule
    let isNew: Bool
    let onSave: (MapRemoteRule) -> Void
    let onCancel: () -> Void

    private let methods = ["*", "GET", "POST", "PUT", "DELETE"]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(isNew ? "New Map Remote" : "Edit Map Remote").font(.title2.bold())
                Spacer()
                Button("Cancel") { onCancel() }.keyboardShortcut(.cancelAction)
                Button("Save") { onSave(rule) }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }.padding().background(.bar)
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    LabeledField(label: "Name") { TextField("Rule name", text: $rule.name).textFieldStyle(.roundedBorder) }
                    Toggle("Enabled", isOn: $rule.isEnabled)
                    Divider()
                    LabeledField(label: "Source URL Pattern") {
                        TextField("*api.production.com*", text: $rule.sourcePattern).textFieldStyle(.roundedBorder).font(.body.monospaced())
                    }
                    LabeledField(label: "Destination URL") {
                        TextField("http://localhost:3000", text: $rule.destinationURL).textFieldStyle(.roundedBorder).font(.body.monospaced())
                    }
                    LabeledField(label: "HTTP Method") {
                        Picker("", selection: $rule.httpMethod) {
                            ForEach(methods, id: \.self) { Text($0 == "*" ? "Any" : $0).tag($0) }
                        }.labelsHidden().frame(width: 150)
                    }
                    Toggle("Preserve original path", isOn: $rule.preservePath)

                    GroupBox {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("How it works:").font(.caption.bold())
                            if rule.preservePath {
                                Text("Request to \(rule.sourcePattern)/users/1 → \(rule.destinationURL)/users/1")
                                    .font(.caption.monospaced()).foregroundStyle(.secondary)
                            } else {
                                Text("Request to \(rule.sourcePattern) → \(rule.destinationURL)")
                                    .font(.caption.monospaced()).foregroundStyle(.secondary)
                            }
                        }.padding(4)
                    }
                }.padding(20)
            }
        }.frame(minWidth: 600, minHeight: 450)
    }
}
