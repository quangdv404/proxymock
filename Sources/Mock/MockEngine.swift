import Foundation

@MainActor
@Observable
final class MockEngine {
    var rules: [MockRule] = []

    var enabledRuleCount: Int {
        rules.filter(\.isEnabled).count
    }

    var allRules: [MockRule] { rules }

    func setRules(_ newRules: [MockRule]) {
        self.rules = newRules
    }

    func addRule(_ rule: MockRule) {
        rules.append(rule)
    }

    func updateRule(_ rule: MockRule) {
        if let index = rules.firstIndex(where: { $0.id == rule.id }) {
            rules[index] = rule
        }
    }

    func deleteRule(id: UUID) {
        rules.removeAll { $0.id == id }
    }

    func toggleRule(id: UUID) {
        if let index = rules.firstIndex(where: { $0.id == id }) {
            rules[index].isEnabled.toggle()
        }
    }

    /// Returns the first matching enabled rule for a given request method and URL
    nonisolated func matchRule(method: String, url: String, rules: [MockRule]) -> MockRule? {
        for rule in rules where rule.isEnabled {
            if rule.httpMethod != "*" && rule.httpMethod.uppercased() != method.uppercased() {
                continue
            }
            if matchesPattern(url: url, pattern: rule.urlPattern) {
                return rule
            }
        }
        return nil
    }

    /// Simple wildcard and regex pattern matching
    nonisolated func matchesPattern(url: String, pattern: String) -> Bool {
        if pattern.hasPrefix("regex:") {
            let regexPattern = String(pattern.dropFirst(6))
            return (try? Regex(regexPattern).firstMatch(in: url)) != nil
        }

        let escaped = NSRegularExpression.escapedPattern(for: pattern)
        let wildcardPattern = "^" + escaped.replacingOccurrences(of: "\\*", with: ".*") + "$"
        return (try? Regex(wildcardPattern).firstMatch(in: url)) != nil
    }
}
