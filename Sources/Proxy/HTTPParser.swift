import Foundation

/// Represents a parsed HTTP request
struct ParsedHTTPRequest: Sendable {
    let method: String
    let url: String
    let httpVersion: String
    let headers: [(String, String)]
    let body: Data
    let rawData: Data
    /// Set by Map Remote to redirect to a different URL
    var remappedURL: String?

    var host: String {
        var rawHost = ""
        for (key, value) in headers {
            if key.lowercased() == "host" { 
                rawHost = value 
                break
            }
        }
        if rawHost.isEmpty, let comps = URLComponents(string: url) {
            rawHost = comps.host ?? ""
        }
        // Strip out port if it exists (e.g. "config.teams.microsoft.com:443")
        return rawHost.split(separator: ":").first.map(String.init) ?? rawHost
    }

    var port: Int {
        if let comps = URLComponents(string: url), let p = comps.port {
            return p
        }
        // For CONNECT method, parse from URL "host:port"
        if method == "CONNECT" {
            let parts = url.split(separator: ":")
            if parts.count == 2, let p = Int(parts[1]) {
                return p
            }
        }
        return url.lowercased().hasPrefix("https") ? 443 : 80
    }

    var isConnect: Bool { method.uppercased() == "CONNECT" }

    /// The full URL for forwarding. If the URL is relative (proxy style), prepend host.
    var fullURL: String {
        if url.lowercased().hasPrefix("http://") || url.lowercased().hasPrefix("https://") {
            return url
        }
        return "http://\(host)\(url)"
    }

    var headersDict: [String: String] {
        var dict: [String: String] = [:]
        for (k, v) in headers { dict[k] = v }
        return dict
    }
}

/// Represents a parsed HTTP response
struct ParsedHTTPResponse: Sendable {
    let statusCode: Int
    let statusMessage: String
    let headers: [(String, String)]
    let body: Data

    var headersDict: [String: String] {
        var dict: [String: String] = [:]
        for (k, v) in headers { dict[k] = v }
        return dict
    }

    var bodyString: String {
        String(data: body, encoding: .utf8) ?? "<binary data: \(body.count) bytes>"
    }
}

/// HTTP Parser: Parses raw bytes into structured HTTP requests/responses
enum HTTPParser {

    /// Parse an HTTP request from raw data
    static func parseRequest(from data: Data) -> ParsedHTTPRequest? {
        guard let headerEnd = findHeaderEnd(in: data) else { return nil }

        let headerData = data.prefix(headerEnd)
        guard let headerString = String(data: headerData, encoding: .utf8) else { return nil }

        let lines = headerString.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }

        let requestParts = requestLine.split(separator: " ", maxSplits: 2).map(String.init)
        guard requestParts.count >= 2 else { return nil }

        let method = requestParts[0]
        let url = requestParts[1]
        let httpVersion = requestParts.count > 2 ? requestParts[2] : "HTTP/1.1"

        var headers: [(String, String)] = []
        for line in lines.dropFirst() {
            if line.isEmpty { break }
            if let colonIndex = line.firstIndex(of: ":") {
                let key = String(line[line.startIndex..<colonIndex]).trimmingCharacters(in: .whitespaces)
                let value = String(line[line.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)
                headers.append((key, value))
            }
        }

        let bodyStart = headerEnd + 4  // Skip \r\n\r\n
        // IMPORTANT: data.suffix(from:) returns a slice with non-zero startIndex.
        // We MUST copy into a fresh Data to reset startIndex to 0, otherwise
        // URLRequest.httpBody's NSData bridge silently drops the body bytes.
        let body: Data
        if bodyStart < data.count {
            body = Data(data[bodyStart...])
        } else {
            body = Data()
        }

        return ParsedHTTPRequest(
            method: method,
            url: url,
            httpVersion: httpVersion,
            headers: headers,
            body: body,
            rawData: data
        )
    }

    /// Parse an HTTP response from raw data
    static func parseResponse(from data: Data) -> ParsedHTTPResponse? {
        guard let headerEnd = findHeaderEnd(in: data) else {
            // If we can't find headers, treat entire data as body with unknown status
            return nil
        }

        let headerData = data.prefix(headerEnd)
        guard let headerString = String(data: headerData, encoding: .utf8) else { return nil }

        let lines = headerString.components(separatedBy: "\r\n")
        guard let statusLine = lines.first else { return nil }

        let statusParts = statusLine.split(separator: " ", maxSplits: 2).map(String.init)
        guard statusParts.count >= 2, let statusCode = Int(statusParts[1]) else { return nil }

        let statusMessage = statusParts.count > 2 ? statusParts[2] : ""

        var headers: [(String, String)] = []
        for line in lines.dropFirst() {
            if line.isEmpty { break }
            if let colonIndex = line.firstIndex(of: ":") {
                let key = String(line[line.startIndex..<colonIndex]).trimmingCharacters(in: .whitespaces)
                let value = String(line[line.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)
                headers.append((key, value))
            }
        }

        let bodyStart = headerEnd + 4
        let body = bodyStart < data.count ? data.suffix(from: bodyStart) : Data()

        return ParsedHTTPResponse(
            statusCode: statusCode,
            statusMessage: statusMessage,
            headers: headers,
            body: body
        )
    }

    static func buildResponse(statusCode: Int, headers: [String: String], body: Data) -> Data {
        let statusMessage = httpStatusMessage(for: statusCode)
        var response = "HTTP/1.1 \(statusCode) \(statusMessage)\r\n"

        var finalHeaders: [String: String] = [:]
        for (key, value) in headers {
            let lower = key.lowercased()
            // URLSession automatically decompresses gzip/deflate and reassembles chunked data.
            // We must strip these headers, otherwise the client tries to decompress already decompressed plaintext data (NSURLErrorDomain Code=-1015).
            if lower == "content-encoding" || lower == "transfer-encoding" || lower == "content-length" {
                continue
            }
            finalHeaders[key] = value
        }
        
        // Add the correct content length for the decompressed body
        finalHeaders["Content-Length"] = "\(body.count)"

        for (key, value) in finalHeaders {
            response += "\(key): \(value)\r\n"
        }
        response += "\r\n"

        var responseData = response.data(using: .utf8) ?? Data()
        responseData.append(body)
        return responseData
    }

    /// Build the CONNECT 200 response for HTTPS tunneling
    static func buildConnectResponse() -> Data {
        "HTTP/1.1 200 Connection Established\r\n\r\n".data(using: .utf8) ?? Data()
    }

    // MARK: - Private helpers

    private static func findHeaderEnd(in data: Data) -> Int? {
        let separator: [UInt8] = [0x0D, 0x0A, 0x0D, 0x0A] // \r\n\r\n
        let bytes = [UInt8](data)
        for i in 0..<(bytes.count - 3) {
            if bytes[i] == separator[0] &&
               bytes[i+1] == separator[1] &&
               bytes[i+2] == separator[2] &&
               bytes[i+3] == separator[3] {
                return i
            }
        }
        return nil
    }

    private static func httpStatusMessage(for code: Int) -> String {
        switch code {
        case 200: return "OK"
        case 201: return "Created"
        case 204: return "No Content"
        case 301: return "Moved Permanently"
        case 302: return "Found"
        case 304: return "Not Modified"
        case 400: return "Bad Request"
        case 401: return "Unauthorized"
        case 403: return "Forbidden"
        case 404: return "Not Found"
        case 405: return "Method Not Allowed"
        case 500: return "Internal Server Error"
        case 502: return "Bad Gateway"
        case 503: return "Service Unavailable"
        default: return "Unknown"
        }
    }
}
