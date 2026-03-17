import SwiftUI

struct DomainFilterView: View {
    @Environment(AppState.self) private var appState
    @State private var newBlockDomain = ""
    @State private var newAllowDomain = ""

    private let commonBlockDomains: [(category: String, domains: [String])] = [
        ("Analytics", ["*.google-analytics.com", "*.crashlytics.com", "*.mixpanel.com", "*.amplitude.com", "*.segment.com"]),
        ("Ads", ["*.doubleclick.net", "*.googlesyndication.com", "*.admob.com"]),
        ("Apple", ["*.apple.com", "*.icloud.com", "*.mzstatic.com"]),
    ]

    var blockRules: [DomainFilterRule] {
        appState.domainFilterRules.filter { $0.listType == .block }
    }
    var allowRules: [DomainFilterRule] {
        appState.domainFilterRules.filter { $0.listType == .allow }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Domain Filters").font(.headline)
                Spacer()
                // Summary badges
                HStack(spacing: 8) {
                    if !blockRules.isEmpty {
                        Label("\(blockRules.filter(\.isEnabled).count) blocked", systemImage: "xmark.shield")
                            .font(.caption).foregroundStyle(.red)
                    }
                    if !allowRules.isEmpty {
                        Label("\(allowRules.filter(\.isEnabled).count) allowed", systemImage: "checkmark.shield")
                            .font(.caption).foregroundStyle(.green)
                    }
                }
            }
            .padding(12).background(.bar)
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // How it works
                    GroupBox {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("How filtering works:").font(.callout.bold())
                            Label("**Block List** — matching domains are dropped entirely", systemImage: "xmark.circle")
                                .font(.caption).foregroundStyle(.red)
                            Label("**Allow List** — only matching domains are captured & logged, everything else bypasses MITM", systemImage: "checkmark.circle")
                                .font(.caption).foregroundStyle(.green)
                            Text("By default, all proxy traffic is passed-through silently. You MUST add domains to the Allow List to mock, map, or inspect them.")
                                .font(.caption).foregroundStyle(.secondary).padding(.top, 2)
                        }.padding(4)
                    }

                    // ═══════ ALLOW LIST ═══════
                    GroupBox {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("Allow List", systemImage: "checkmark.shield.fill")
                                .font(.headline).foregroundStyle(.green)
                            Text("Only these domains will be intercepted, logged, and have rules applied. Everything else passes through silently.")
                                .font(.caption).foregroundStyle(.secondary)

                            HStack {
                                TextField("e.g. api.myapp.com", text: $newAllowDomain)
                                    .textFieldStyle(.roundedBorder).font(.body.monospaced())
                                    .onSubmit { addDomain(newAllowDomain, type: .allow); newAllowDomain = "" }
                                Button("Add") { addDomain(newAllowDomain, type: .allow); newAllowDomain = "" }
                                    .buttonStyle(.borderedProminent).tint(.green)
                                    .disabled(newAllowDomain.isEmpty)
                            }

                            if allowRules.isEmpty {
                                Text("No allow rules — all traffic is captured")
                                    .font(.caption).foregroundStyle(.secondary).italic()
                                    .frame(maxWidth: .infinity).padding(.vertical, 8)
                            } else {
                                DomainRulesList(rules: allowRules, appState: appState, tint: .green)
                            }
                        }.padding(4)
                    }


                    // ═══════ BLOCK LIST ═══════
                    GroupBox {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("Block List", systemImage: "xmark.shield.fill")
                                .font(.headline).foregroundStyle(.red)
                            Text("These domains will be blocked — connections dropped entirely.")
                                .font(.caption).foregroundStyle(.secondary)

                            HStack {
                                TextField("e.g. *.analytics.com", text: $newBlockDomain)
                                    .textFieldStyle(.roundedBorder).font(.body.monospaced())
                                    .onSubmit { addDomain(newBlockDomain, type: .block); newBlockDomain = "" }
                                Button("Add") { addDomain(newBlockDomain, type: .block); newBlockDomain = "" }
                                    .buttonStyle(.borderedProminent).tint(.red)
                                    .disabled(newBlockDomain.isEmpty)
                            }

                            // Quick-block presets
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Quick add:").font(.caption.bold()).foregroundStyle(.secondary)
                                ForEach(commonBlockDomains, id: \.category) { group in
                                    HStack(alignment: .top, spacing: 6) {
                                        Text(group.category).font(.caption).foregroundStyle(.secondary).frame(width: 60, alignment: .trailing)
                                        FlowLayout(spacing: 4) {
                                            ForEach(group.domains, id: \.self) { domain in
                                                let exists = appState.domainFilterRules.contains { $0.domain == domain }
                                                Button {
                                                    addDomain(domain, type: .block)
                                                } label: {
                                                    HStack(spacing: 3) {
                                                        Image(systemName: exists ? "checkmark" : "plus")
                                                        Text(domain).font(.caption2.monospaced())
                                                    }
                                                }
                                                .buttonStyle(.bordered).controlSize(.mini).disabled(exists)
                                            }
                                        }
                                    }
                                }
                            }

                            if blockRules.isEmpty {
                                Text("No block rules — nothing is blocked")
                                    .font(.caption).foregroundStyle(.secondary).italic()
                                    .frame(maxWidth: .infinity).padding(.vertical, 8)
                            } else {
                                DomainRulesList(rules: blockRules, appState: appState, tint: .red)
                            }
                        }.padding(4)
                    }
                }
                .padding(20)
            }
        }
    }

    private func addDomain(_ domain: String, type: DomainFilterRule.ListType) {
        var d = domain.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Strip scheme (http://, https://)
        if let schemeRange = d.range(of: "://") {
            d = String(d[schemeRange.upperBound...])
        }
        
        // Strip path (/endpoint)
        if let pathRange = d.range(of: "/") {
            d = String(d[..<pathRange.lowerBound])
        }
        
        // Strip port (:443)
        if let portRange = d.range(of: ":") {
            d = String(d[..<portRange.lowerBound])
        }

        guard !d.isEmpty else { return }
        guard !appState.domainFilterRules.contains(where: { $0.domain == d && $0.listType == type }) else { return }
        appState.domainFilterRules.append(DomainFilterRule(domain: d, listType: type))
        appState.saveDomainFilters()
    }
}

/// Reusable list of domain rules with toggle and delete
struct DomainRulesList: View {
    let rules: [DomainFilterRule]
    let appState: AppState
    let tint: Color

    var body: some View {
        VStack(spacing: 0) {
            ForEach(rules) { rule in
                HStack(spacing: 10) {
                    Toggle("", isOn: Binding(
                        get: { rule.isEnabled },
                        set: { enabled in
                            if let i = appState.domainFilterRules.firstIndex(where: { $0.id == rule.id }) {
                                appState.domainFilterRules[i].isEnabled = enabled
                                appState.saveDomainFilters()
                            }
                        }
                    )).labelsHidden().tint(tint)

                    Text(rule.domain).font(.body.monospaced())
                        .foregroundStyle(rule.isEnabled ? .primary : .secondary)
                    Spacer()
                    Button {
                        appState.domainFilterRules.removeAll { $0.id == rule.id }
                        appState.saveDomainFilters()
                    } label: {
                        Image(systemName: "trash").foregroundStyle(.red.opacity(0.7))
                    }.buttonStyle(.plain)
                }
                .padding(.vertical, 5)
                if rule.id != rules.last?.id { Divider() }
            }
        }
    }
}

/// Simple wrapping layout for tag buttons
struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            x += size.width + spacing; rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth, height: y + rowHeight)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX && x > bounds.minX { x = bounds.minX; y += rowHeight + spacing; rowHeight = 0 }
            subview.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += size.width + spacing; rowHeight = max(rowHeight, size.height)
        }
    }
}
