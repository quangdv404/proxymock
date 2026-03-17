import SwiftUI

struct BreakpointsView: View {
    @Environment(AppState.self) private var appState
    @State private var editingRule: BreakpointRule?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("Breakpoints")
                    .font(.headline)
                Spacer()
                Button { editingRule = BreakpointRule() } label: {
                    Label("Add Breakpoint", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                Text("\(appState.breakpointManager.rules.count) rules")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .background(.bar)
            Divider()

            if appState.breakpointManager.rules.isEmpty {
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: "pause.circle")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("No breakpoints defined")
                        .font(.title3).foregroundStyle(.secondary)
                    Text("Breakpoints pause requests/responses so you can edit them before they continue.")
                        .font(.callout).foregroundStyle(.tertiary).multilineTextAlignment(.center)
                    Button("Add Breakpoint") { editingRule = BreakpointRule() }
                        .buttonStyle(.borderedProminent)
                    Spacer()
                }
                .padding()
            } else {
                List {
                    ForEach(appState.breakpointManager.rules) { rule in
                        HStack(spacing: 12) {
                            Button {
                                appState.breakpointManager.toggleRule(id: rule.id)
                            } label: {
                                Image(systemName: rule.isEnabled ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(rule.isEnabled ? .green : .secondary)
                            }
                            .buttonStyle(.plain)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(rule.name).font(.headline)
                                HStack(spacing: 6) {
                                    Text(rule.httpMethod).font(.caption.monospaced().bold())
                                        .foregroundStyle(.white).padding(.horizontal, 4).padding(.vertical, 1)
                                        .background(Color.blue).clipShape(RoundedRectangle(cornerRadius: 3))
                                    Text(rule.urlPattern).font(.caption.monospaced()).foregroundStyle(.secondary)
                                    Text("→ \(rule.direction.rawValue)").font(.caption).foregroundStyle(.orange)
                                }
                            }
                            Spacer()
                            Button { editingRule = rule } label: { Image(systemName: "pencil") }.buttonStyle(.plain)
                            Button { appState.breakpointManager.deleteRule(id: rule.id) } label: {
                                Image(systemName: "trash").foregroundStyle(.red)
                            }.buttonStyle(.plain)
                        }
                        .padding(.vertical, 4)
                        .opacity(rule.isEnabled ? 1 : 0.5)
                    }
                }
                .listStyle(.plain)
            }

            // Pending breakpoint banner
            if appState.breakpointManager.hasPending {
                VStack(spacing: 8) {
                    Divider()
                    HStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow).font(.title3)
                        Text("Breakpoint hit! A request is paused and waiting for your action.")
                            .font(.callout.bold()).foregroundStyle(.orange)
                        Spacer()
                        Button("Open Editor") {
                            // The breakpoint editor is shown as an overlay/sheet from ContentView
                        }
                        .buttonStyle(.borderedProminent).tint(.orange)
                    }
                    .padding(12)
                    .background(.orange.opacity(0.1))
                }
            }
        }
        .sheet(item: $editingRule) { rule in
            BreakpointRuleEditor(rule: rule, isNew: !appState.breakpointManager.rules.contains { $0.id == rule.id }) { saved in
                if appState.breakpointManager.rules.contains(where: { $0.id == saved.id }) {
                    appState.breakpointManager.updateRule(saved)
                } else {
                    appState.breakpointManager.addRule(saved)
                }
                editingRule = nil
            } onCancel: { editingRule = nil }
        }
    }
}

struct BreakpointRuleEditor: View {
    @State var rule: BreakpointRule
    let isNew: Bool
    let onSave: (BreakpointRule) -> Void
    let onCancel: () -> Void

    private let methods = ["*", "GET", "POST", "PUT", "DELETE", "PATCH"]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(isNew ? "New Breakpoint" : "Edit Breakpoint").font(.title2.bold())
                Spacer()
                Button("Cancel") { onCancel() }.keyboardShortcut(.cancelAction)
                Button("Save") { onSave(rule) }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }
            .padding().background(.bar)
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    LabeledField(label: "Name") { TextField("Breakpoint name", text: $rule.name).textFieldStyle(.roundedBorder) }
                    Toggle("Enabled", isOn: $rule.isEnabled)
                    LabeledField(label: "URL Pattern") { TextField("*/api/*", text: $rule.urlPattern).textFieldStyle(.roundedBorder).font(.body.monospaced()) }
                    LabeledField(label: "HTTP Method") {
                        Picker("", selection: $rule.httpMethod) {
                            ForEach(methods, id: \.self) { Text($0 == "*" ? "Any" : $0).tag($0) }
                        }.labelsHidden().frame(width: 150)
                    }
                    LabeledField(label: "Direction") {
                        Picker("", selection: $rule.direction) {
                            ForEach(BreakpointDirection.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                        }.labelsHidden().pickerStyle(.segmented)
                    }
                }
                .padding(20)
            }
        }
        .frame(minWidth: 500, minHeight: 400)
    }
}

/// Editor shown when a breakpoint fires — lets user edit the paused request
struct BreakpointEditorView: View {
    @Environment(AppState.self) private var appState
    @State private var edit: BreakpointEdit

    init(edit: BreakpointEdit) {
        _edit = State(initialValue: edit)
    }

    private let methods = ["GET", "POST", "PUT", "DELETE", "PATCH", "HEAD", "OPTIONS"]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "pause.circle.fill").foregroundStyle(.orange).font(.title2)
                Text("Breakpoint — Edit \(edit.direction.rawValue)").font(.title2.bold())
                Spacer()
                Button("Drop Request", role: .destructive) { appState.breakpointManager.drop() }
                    .buttonStyle(.bordered)
                Button("Continue") { appState.breakpointManager.resumeWith(edit: edit) }
                    .buttonStyle(.borderedProminent).tint(.green)
            }
            .padding().background(.orange.opacity(0.1))
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if edit.direction == .request || edit.direction == .both {
                        SectionHeader(title: "Request", icon: "arrow.up.circle")
                        LabeledField(label: "Method") {
                            Picker("", selection: $edit.method) {
                                ForEach(methods, id: \.self) { Text($0).tag($0) }
                            }.labelsHidden().frame(width: 150)
                        }
                        LabeledField(label: "URL") { TextField("URL", text: $edit.url).textFieldStyle(.roundedBorder).font(.body.monospaced()) }
                    }

                    if let statusCode = edit.statusCode {
                        SectionHeader(title: "Response", icon: "arrow.down.circle")
                        LabeledField(label: "Status Code") {
                            TextField("Status", value: Binding(get: { statusCode }, set: { edit.statusCode = $0 }), format: .number)
                                .textFieldStyle(.roundedBorder).frame(width: 100)
                        }
                    }

                    Divider()
                    SectionHeader(title: "Body", icon: "doc.text")
                    TextEditor(text: $edit.body)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 200)
                        .padding(4)
                        .background(Color(nsColor: .textBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.3)))
                }
                .padding(20)
            }
        }
        .frame(minWidth: 650, minHeight: 500)
    }
}
