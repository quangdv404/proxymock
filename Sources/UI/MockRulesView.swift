import SwiftUI

struct MockRulesView: View {
    @Environment(AppState.self) private var appState
    @State private var editingRule: MockRule?
    @State private var searchText = ""

    var filteredRules: [MockRule] {
        let all = appState.mockEngine.allRules
        if searchText.isEmpty { return all }
        return all.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.urlPattern.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack(spacing: 12) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search rules...", text: $searchText)
                        .textFieldStyle(.plain)
                }
                .padding(8)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 8))

                Button {
                    editingRule = MockRule()
                } label: {
                    Label("Add Rule", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)

                Text("\(filteredRules.count) rules")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .background(.bar)

            Divider()

            if filteredRules.isEmpty {
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("No mock rules defined")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                    Text("Create rules to intercept and mock API responses")
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                    Button("Create First Rule") {
                        editingRule = MockRule()
                    }
                    .buttonStyle(.borderedProminent)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                List {
                    ForEach(filteredRules) { rule in
                        MockRuleRow(rule: rule) {
                            appState.mockEngine.toggleRule(id: rule.id)
                            appState.saveRules()
                        } onEdit: {
                            editingRule = rule
                        } onDelete: {
                            appState.mockEngine.deleteRule(id: rule.id)
                            appState.saveRules()
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .sheet(item: $editingRule) { rule in
            MockRuleEditorView(
                rule: rule,
                isNew: !appState.mockEngine.allRules.contains(where: { $0.id == rule.id })
            ) { savedRule in
                if appState.mockEngine.allRules.contains(where: { $0.id == savedRule.id }) {
                    appState.mockEngine.updateRule(savedRule)
                } else {
                    appState.mockEngine.addRule(savedRule)
                }
                appState.saveRules()
                editingRule = nil
            } onCancel: {
                editingRule = nil
            }
        }
    }
}

struct MockRuleRow: View {
    let rule: MockRule
    let onToggle: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Enable toggle
            Button {
                onToggle()
            } label: {
                Image(systemName: rule.isEnabled ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(rule.isEnabled ? .green : .secondary)
                    .font(.title3)
            }
            .buttonStyle(.plain)

            // Rule info
            VStack(alignment: .leading, spacing: 4) {
                Text(rule.name)
                    .font(.headline)
                    .foregroundStyle(rule.isEnabled ? .primary : .secondary)

                HStack(spacing: 8) {
                    Text(rule.httpMethod)
                        .font(.caption.monospaced().bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(rule.httpMethod == "*" ? Color.gray : Color.blue)
                        .clipShape(RoundedRectangle(cornerRadius: 3))

                    Text(rule.urlPattern)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            // Status code badge
            Text("\(rule.responseStatusCode)")
                .font(.callout.monospaced().bold())
                .foregroundStyle(statusColor(rule.responseStatusCode))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(statusColor(rule.responseStatusCode).opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 6))

            if rule.delaySeconds > 0 {
                HStack(spacing: 2) {
                    Image(systemName: "clock")
                    Text("\(rule.delaySeconds, specifier: "%.1f")s")
                }
                .font(.caption)
                .foregroundStyle(.orange)
            }

            // Actions
            Button { onEdit() } label: {
                Image(systemName: "pencil")
            }
            .buttonStyle(.plain)
            .help("Edit rule")

            Button { onDelete() } label: {
                Image(systemName: "trash")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
            .help("Delete rule")
        }
        .padding(.vertical, 6)
        .opacity(rule.isEnabled ? 1.0 : 0.6)
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
