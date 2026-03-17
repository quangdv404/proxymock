import Foundation

struct MockRule: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var name: String
    var isEnabled: Bool
    var urlPattern: String       // Wildcard or regex pattern
    var httpMethod: String       // GET, POST, PUT, DELETE, * for any
    var responseStatusCode: Int
    var responseHeaders: [String: String]
    var responseBody: String
    var delaySeconds: Double     // Optional delay before responding

    init(
        id: UUID = UUID(),
        name: String = "New Rule",
        isEnabled: Bool = true,
        urlPattern: String = "*",
        httpMethod: String = "*",
        responseStatusCode: Int = 200,
        responseHeaders: [String: String] = ["Content-Type": "application/json"],
        responseBody: String = "{}",
        delaySeconds: Double = 0
    ) {
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
        self.urlPattern = urlPattern
        self.httpMethod = httpMethod
        self.responseStatusCode = responseStatusCode
        self.responseHeaders = responseHeaders
        self.responseBody = responseBody
        self.delaySeconds = delaySeconds
    }
}
