import Foundation

/// A rule for mapping a URL pattern to a local response (file or inline text)
struct MapLocalRule: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var name: String
    var isEnabled: Bool
    var group: String
    var urlPattern: String
    var httpMethod: String
    
    enum DataSource: String, Codable, Sendable {
        case file
        case inline
    }
    var source: DataSource
    var localFilePath: String
    var inlineBody: String
    var inlineRequestMatch: String
    
    var contentType: String
    var statusCode: Int

    init(
        id: UUID = UUID(),
        name: String = "New Map Local",
        isEnabled: Bool = true,
        group: String = "",
        urlPattern: String = "*",
        httpMethod: String = "*",
        source: DataSource = .inline,
        localFilePath: String = "",
        inlineBody: String = "{\n  \"message\": \"success\"\n}",
        inlineRequestMatch: String = "",
        contentType: String = "application/json",
        statusCode: Int = 200
    ) {
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
        self.group = group
        self.urlPattern = urlPattern
        self.httpMethod = httpMethod
        self.source = source
        self.localFilePath = localFilePath
        self.inlineBody = inlineBody
        self.inlineRequestMatch = inlineRequestMatch
        self.contentType = contentType
        self.statusCode = statusCode
    }
}

/// A rule for redirecting requests to a different URL
struct MapRemoteRule: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var name: String
    var isEnabled: Bool
    var sourcePattern: String
    var destinationURL: String
    var httpMethod: String
    var preservePath: Bool

    init(
        id: UUID = UUID(),
        name: String = "New Map Remote",
        isEnabled: Bool = true,
        sourcePattern: String = "*",
        destinationURL: String = "http://localhost:3000",
        httpMethod: String = "*",
        preservePath: Bool = true
    ) {
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
        self.sourcePattern = sourcePattern
        self.destinationURL = destinationURL
        self.httpMethod = httpMethod
        self.preservePath = preservePath
    }
}

/// A domain filter rule for Block/Allow list
struct DomainFilterRule: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var domain: String
    var isEnabled: Bool
    var listType: ListType

    enum ListType: String, Codable, Sendable {
        case block
        case allow
        case bypass
    }

    init(id: UUID = UUID(), domain: String = "", isEnabled: Bool = true, listType: ListType = .block) {
        self.id = id
        self.domain = domain
        self.isEnabled = isEnabled
        self.listType = listType
    }
}

/// Kept for backward compat but no longer drives filtering logic
enum DomainFilterMode: String, Codable, CaseIterable, Sendable {
    case disabled = "Disabled"
    case allowList = "Allow List"
    case blockList = "Block List"
}

/// Network throttle profile
struct ThrottleProfile: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var name: String
    var latencyMs: Int
    var bandwidthKbps: Int

    init(id: UUID = UUID(), name: String, latencyMs: Int, bandwidthKbps: Int) {
        self.id = id
        self.name = name
        self.latencyMs = latencyMs
        self.bandwidthKbps = bandwidthKbps
    }

    static let presets: [ThrottleProfile] = [
        ThrottleProfile(name: "No Throttle", latencyMs: 0, bandwidthKbps: 0),
        ThrottleProfile(name: "3G (750 kbps)", latencyMs: 300, bandwidthKbps: 750),
        ThrottleProfile(name: "4G/LTE (12 Mbps)", latencyMs: 50, bandwidthKbps: 12000),
        ThrottleProfile(name: "Slow Wi-Fi (2 Mbps)", latencyMs: 100, bandwidthKbps: 2000),
        ThrottleProfile(name: "Edge (240 kbps)", latencyMs: 500, bandwidthKbps: 240),
        ThrottleProfile(name: "Offline Simulation", latencyMs: 5000, bandwidthKbps: 0),
    ]
}
