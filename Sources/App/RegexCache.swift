import Foundation

/// A high-performance thread-safe regex cache to bypass severe CPU overhead in tight networking loops.
public final class RegexCache: @unchecked Sendable {
    public static let shared = RegexCache()
    
    private var cache: [String: NSRegularExpression] = [:]
    private let lock = NSLock()

    private init() {}

    /// Evaluates a wildcard pattern (e.g. `*.com/*`) or a forced regex pattern (`regex:.*`) against a URL.
    /// Uses an internal locked dictionary to skip compilation penalties on repeated evaluations.
    public func matchesPattern(url: String, pattern: String) -> Bool {
        let regexStr: String
        if pattern.hasPrefix("regex:") {
            regexStr = String(pattern.dropFirst(6))
        } else {
            let escaped = NSRegularExpression.escapedPattern(for: pattern)
            regexStr = "^" + escaped.replacingOccurrences(of: "\\*", with: ".*") + "$"
        }

        guard let regex = getRegex(for: regexStr) else { return false }
        let range = NSRange(url.startIndex..., in: url)
        return regex.firstMatch(in: url, options: [], range: range) != nil
    }

    private func getRegex(for pattern: String) -> NSRegularExpression? {
        lock.lock()
        if let cached = cache[pattern] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        guard let compiled = try? NSRegularExpression(pattern: pattern) else { return nil }
        
        lock.lock()
        cache[pattern] = compiled
        lock.unlock()
        
        return compiled
    }
}
