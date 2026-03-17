import Foundation

/// Direction for breakpoint interception
enum BreakpointDirection: String, Codable, CaseIterable, Sendable {
    case request = "Request"
    case response = "Response"
    case both = "Both"
}

/// A rule that determines when to pause a request for editing
struct BreakpointRule: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var name: String
    var isEnabled: Bool
    var urlPattern: String
    var httpMethod: String
    var direction: BreakpointDirection

    init(
        id: UUID = UUID(),
        name: String = "New Breakpoint",
        isEnabled: Bool = true,
        urlPattern: String = "*",
        httpMethod: String = "*",
        direction: BreakpointDirection = .request
    ) {
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
        self.urlPattern = urlPattern
        self.httpMethod = httpMethod
        self.direction = direction
    }
}

/// Editable request/response that the breakpoint editor works with
struct BreakpointEdit: Sendable {
    let id: UUID
    let direction: BreakpointDirection
    var method: String
    var url: String
    var headers: [String: String]
    var body: String
    var statusCode: Int?

    init(id: UUID = UUID(), direction: BreakpointDirection, method: String, url: String, headers: [String: String], body: String, statusCode: Int? = nil) {
        self.id = id
        self.direction = direction
        self.method = method
        self.url = url
        self.headers = headers
        self.body = body
        self.statusCode = statusCode
    }
}

/// Outcome of a breakpoint decision
enum BreakpointAction: Sendable {
    case continueWith(BreakpointEdit)
    case drop
}

/// Manages breakpoint rules and pending breakpoints
@MainActor
@Observable
final class BreakpointManager {
    var rules: [BreakpointRule] = []
    var pendingEdit: BreakpointEdit?
    var continuation: CheckedContinuation<BreakpointAction, Never>?

    var hasPending: Bool { pendingEdit != nil }

    func addRule(_ rule: BreakpointRule) {
        rules.append(rule)
        save()
    }

    func updateRule(_ rule: BreakpointRule) {
        if let i = rules.firstIndex(where: { $0.id == rule.id }) {
            rules[i] = rule
            save()
        }
    }

    func deleteRule(id: UUID) {
        rules.removeAll { $0.id == id }
        save()
    }

    func toggleRule(id: UUID) {
        if let i = rules.firstIndex(where: { $0.id == id }) {
            rules[i].isEnabled.toggle()
            save()
        }
    }

    /// Check if a request should hit a breakpoint (called from proxy thread)
    nonisolated func shouldBreak(method: String, url: String, direction: BreakpointDirection, rules: [BreakpointRule]) -> Bool {
        for rule in rules where rule.isEnabled {
            if rule.httpMethod != "*" && rule.httpMethod.uppercased() != method.uppercased() {
                continue
            }
            if rule.direction != .both && rule.direction != direction {
                continue
            }
            // Wildcard match
            let escaped = NSRegularExpression.escapedPattern(for: rule.urlPattern)
            let pattern = "^" + escaped.replacingOccurrences(of: "\\*", with: ".*") + "$"
            if (try? Regex(pattern).firstMatch(in: url)) != nil {
                return true
            }
        }
        return false
    }

    /// Present a breakpoint edit to the user and wait for their decision
    func waitForDecision(edit: BreakpointEdit) async -> BreakpointAction {
        return await withCheckedContinuation { cont in
            self.pendingEdit = edit
            self.continuation = cont
        }
    }

    /// User chose to continue (with possibly edited data)
    func resumeWith(edit: BreakpointEdit) {
        let cont = continuation
        continuation = nil
        pendingEdit = nil
        cont?.resume(returning: .continueWith(edit))
    }

    /// User chose to drop the request
    func drop() {
        let cont = continuation
        continuation = nil
        pendingEdit = nil
        cont?.resume(returning: .drop)
    }

    private static var storeURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("ProxyMock", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("breakpoints.json")
    }

    func load() {
        guard let data = try? Data(contentsOf: Self.storeURL) else { return }
        rules = (try? JSONDecoder().decode([BreakpointRule].self, from: data)) ?? []
    }

    func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        guard let data = try? encoder.encode(rules) else { return }
        try? data.write(to: Self.storeURL, options: .atomic)
    }
}
