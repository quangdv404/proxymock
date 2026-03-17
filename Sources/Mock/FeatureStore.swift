import Foundation

/// Persistence for all feature rules (Map Local, Map Remote, Domain Filter, Throttle)
struct FeatureStore: Sendable {
    private static var baseDir: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("ProxyMock", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - Map Local
    static func loadMapLocal() -> [MapLocalRule] {
        load(filename: "map_local.json")
    }
    static func saveMapLocal(_ rules: [MapLocalRule]) {
        save(rules, filename: "map_local.json")
    }

    // MARK: - Map Remote
    static func loadMapRemote() -> [MapRemoteRule] {
        load(filename: "map_remote.json")
    }
    static func saveMapRemote(_ rules: [MapRemoteRule]) {
        save(rules, filename: "map_remote.json")
    }

    // MARK: - Domain Filter
    static func loadDomainFilters() -> [DomainFilterRule] {
        load(filename: "domain_filters.json")
    }
    static func saveDomainFilters(_ rules: [DomainFilterRule]) {
        save(rules, filename: "domain_filters.json")
    }

    static func loadDomainFilterMode() -> DomainFilterMode {
        guard let data = try? Data(contentsOf: baseDir.appendingPathComponent("domain_filter_mode.json")),
              let mode = try? JSONDecoder().decode(DomainFilterMode.self, from: data) else {
            return .disabled
        }
        return mode
    }
    static func saveDomainFilterMode(_ mode: DomainFilterMode) {
        guard let data = try? JSONEncoder().encode(mode) else { return }
        try? data.write(to: baseDir.appendingPathComponent("domain_filter_mode.json"), options: .atomic)
    }

    // MARK: - Generic
    private static func load<T: Codable>(filename: String) -> [T] {
        let url = baseDir.appendingPathComponent(filename)
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([T].self, from: data)) ?? []
    }

    private static func save<T: Codable>(_ items: [T], filename: String) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        guard let data = try? encoder.encode(items) else { return }
        let url = baseDir.appendingPathComponent(filename)
        try? data.write(to: url, options: .atomic)
    }
}
