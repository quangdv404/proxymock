import Foundation

/// Snapshot of all feature configurations — passed to ConnectionHandler for thread-safety
struct ProxyConfig: Sendable {
    let mockRules: [MockRule]
    let mapLocalRules: [MapLocalRule]
    let mapRemoteRules: [MapRemoteRule]
    let breakpointRules: [BreakpointRule]
    let throttleLatencyMs: Int
    let isThrottleEnabled: Bool
    let domainFilterRules: [DomainFilterRule]

    /// Determine how the proxy should handle a URL based on combined block + allow lists
    enum FilterAction {
        case process     // Full processing: log, apply rules, MITM
        case passthrough // Forward silently without logging or rules
        case block       // Drop the connection entirely
    }

    func filterAction(for url: String) -> FilterAction {
        let host = extractHost(from: url)
        let blockRules = domainFilterRules.filter { $0.isEnabled && $0.listType == .block }
        let allowRules = domainFilterRules.filter { $0.isEnabled && $0.listType == .allow }
        // 0. Block list always wins over allow — if host matches a block rule, drop it
        if !blockRules.isEmpty && matchesDomain(host: host, rules: blockRules) {
            return .block
        }

        // 1. If allow list has entries, only allow-listed hosts get full processing
        //    Non-matching hosts passthrough silently
        if !allowRules.isEmpty {
            return matchesDomain(host: host, rules: allowRules) ? .process : .passthrough
        }

        // 2. Default architecture: bypass everything (passthrough)
        return .passthrough
    }

    private func matchesDomain(host: String, rules: [DomainFilterRule]) -> Bool {
        let h = host.lowercased()
        return rules.contains { rule in
            let domain = rule.domain.lowercased()
            if h == domain { return true }
            if h.hasSuffix("." + domain) { return true }
            if domain.contains("*") {
                let escaped = NSRegularExpression.escapedPattern(for: domain)
                let pattern = "^" + escaped.replacingOccurrences(of: "\\*", with: ".*") + "$"
                return (try? Regex(pattern).firstMatch(in: h)) != nil
            }
            return false
        }
    }

    private func extractHost(from url: String) -> String {
        if !url.contains("://") && !url.hasPrefix("/") {
            return url.split(separator: ":").first.map(String.init) ?? url
        }
        return URL(string: url)?.host ?? url
    }
}
