import Foundation

func extractHost(from url: String) -> String {
    if !url.contains("://") && !url.hasPrefix("/") {
        return url.split(separator: ":").first.map(String.init) ?? url
    }
    return URL(string: url)?.host ?? url
}

func matchesDomain(host: String, domainRule: String) -> Bool {
    let h = host.lowercased()
    let domain = domainRule.lowercased()
    if h == domain { return true }
    if h.hasSuffix("." + domain) { return true }
    if domain.contains("*") {
        let escaped = NSRegularExpression.escapedPattern(for: domain)
        let pattern = "^" + escaped.replacingOccurrences(of: "\\*", with: ".*") + "$"
        return (try? Regex(pattern).firstMatch(in: h)) != nil
    }
    return false
}

let host = extractHost(from: "config.teams.microsoft.com:443")
print("Extracted:", host)
print("Matches *.microsoft.com:", matchesDomain(host: host, domainRule: "*.microsoft.com"))
print("Matches *.teams.microsoft.com:", matchesDomain(host: host, domainRule: "*.teams.microsoft.com"))

