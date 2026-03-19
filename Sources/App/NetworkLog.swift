import Foundation

/// A logged network call
struct NetworkLog: Identifiable, Sendable, Hashable {
    let id: UUID
    let timestamp: Date
    let method: String
    let url: String
    let requestHeaders: [String: String]
    let requestBody: String
    let responseStatusCode: Int?
    let responseHeaders: [String: String]
    let responseBody: String
    let duration: TimeInterval
    let isMocked: Bool
    let isHTTPS: Bool
    let isPending: Bool

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        method: String,
        url: String,
        requestHeaders: [String: String] = [:],
        requestBody: String = "",
        responseStatusCode: Int? = nil,
        responseHeaders: [String: String] = [:],
        responseBody: String = "",
        duration: TimeInterval = 0,
        isMocked: Bool = false,
        isHTTPS: Bool = false,
        isPending: Bool = false
    ) {
        self.id = id
        self.timestamp = timestamp
        self.method = method
        self.url = url
        self.requestHeaders = requestHeaders
        self.requestBody = requestBody
        self.responseStatusCode = responseStatusCode
        self.responseHeaders = responseHeaders
        self.responseBody = responseBody
        self.duration = duration
        self.isMocked = isMocked
        self.isHTTPS = isHTTPS
        self.isPending = isPending
    }
}

extension Data {
    /// Safely converts Data to String for logging. Truncated if over 1 MB to prevent RAM exhaustion.
    var loggableString: String {
        let maxBytes = 1_048_576 // 1 MB
        if self.count > maxBytes {
            return "<huge payload truncated: \(self.count) bytes>"
        }
        return String(data: self, encoding: .utf8) ?? "<binary \(self.count) bytes>"
    }
}
