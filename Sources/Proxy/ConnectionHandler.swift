import Foundation
import os.log
import Security

/// URLSession config that bypasses system proxy to prevent forwarding loops
private let noProxyConfig: URLSessionConfiguration = {
    let config = URLSessionConfiguration.ephemeral
    config.connectionProxyDictionary = [:]
    config.timeoutIntervalForRequest = 30
    config.timeoutIntervalForResource = 60
    return config
}()

/// Shared URLSession that bypasses system proxies
private let sharedNoProxySession = URLSession(configuration: noProxyConfig)

/// Wraps the socket file descriptor and any leftover bytes (like TLS ClientHello) 
/// so SecureTransport can consume them before blocking on the socket.
final class SSLConnectionContext {
    let fd: Int32
    var overflowData: Data
    
    init(fd: Int32, overflowData: Data) {
        self.fd = fd
        self.overflowData = overflowData
    }
}

/// Handles an individual proxy connection using POSIX sockets.
/// Supports MITM HTTPS interception via SecureTransport.
final class ConnectionHandler: @unchecked Sendable {
    let clientFd: Int32
    let mockEngine: MockEngine
    let config: ProxyConfig
    let mitmEnabled: Bool
    let onLog: @Sendable (NetworkLog) -> Void

    init(
        clientFd: Int32,
        mockEngine: MockEngine,
        config: ProxyConfig,
        mitmEnabled: Bool,
        onLog: @escaping @Sendable (NetworkLog) -> Void
    ) {
        self.clientFd = clientFd
        self.mockEngine = mockEngine
        self.config = config
        self.mitmEnabled = mitmEnabled
        self.onLog = onLog
    }

    /// Main entry point — reads request, routes to handler
    func handle() {
        defer { Darwin.close(clientFd) }
        Logger(subsystem: "ProxyMock", category: "ProxyMock.Lock").error("fire")
        guard let requestData = readFullHTTPRequest(fd: clientFd),
              let request = HTTPParser.parseRequest(from: requestData.completeData) else {
            return
        }
        Logger(subsystem: "ProxyMock", category: "ProxyMock.Lock").error("url path \(request.url, privacy: .public)")

        let overflowData = requestData.overflowData

        // 1. Check if this is a request for the Root CA certificate (Bypass filters)
        let isInternalHost = request.host.hasPrefix("192.168.") || request.host.hasPrefix("10.") || request.host.hasPrefix("172.") || request.host.hasPrefix("127.")
        if !request.isConnect && (request.url.contains("/cert") || request.fullURL.lowercased().contains("proxy.mock/cert") || (request.fullURL.lowercased().contains("/cert") && isInternalHost)) {
            serveCertificate(request: request)
            return
        }

        // 2. Domain filter check — block/allow list
        let checkURL: String
        if request.isConnect {
            checkURL = request.url  // "host:port" format
        } else {
            checkURL = request.fullURL
        }
        let filterAction = config.filterAction(for: checkURL)

        switch filterAction {
        case .block:
            // Drop connection entirely (Block List matched)
            return
        case .passthrough:
            // Forward without logging or applying rules (Allow List non-match)
            if request.isConnect {
                handleConnectTunnel(request: request, overflowData: overflowData, startTime: Date())
            } else {
                forwardHTTPRequest(request: request, targetURL: request.fullURL, startTime: Date())
            }
            return
        case .process:
            break // Continue to full processing below
        }

        let startTime = Date()

        if request.isConnect {
            if mitmEnabled {
                handleMITM(request: request, overflowData: overflowData, startTime: startTime)
            } else {
                handleConnectTunnel(request: request, overflowData: overflowData, startTime: startTime)
            }
        } else {
            handleHTTPRequest(request: request, startTime: startTime)
        }
    }

    // MARK: - MITM HTTPS Interception

    private func handleMITM(request: ParsedHTTPRequest, overflowData: Data, startTime: Date) {
        let host = request.host
        let port = request.port

        // 1. Get/generate certificate for this host
        guard let p12Path = CertPaths.getP12Path(for: host),
              let identity = CertPaths.loadIdentity(from: p12Path) else {
            print("[MITM] Failed to get cert for \(host), falling back to tunnel")
            handleConnectTunnel(request: request, overflowData: overflowData, startTime: startTime)
            return
        }

        // 2. Send 200 Connection Established
        let response200 = "HTTP/1.1 200 Connection Established\r\n\r\n"
        _ = writeToSocket(clientFd, string: response200)

        // 3. Create SSL context (server side — we act as the HTTPS server to the client)
        guard let sslContext = SSLCreateContext(nil, .serverSide, .streamType) else {
            print("[MITM] Failed to create SSL context")
            return
        }
        defer { SSLClose(sslContext) }

        // Set up SSL I/O callbacks (read/write from the client socket)
        let sslConnCtx = SSLConnectionContext(fd: clientFd, overflowData: overflowData)
        let ctxPtr = Unmanaged.passRetained(sslConnCtx)
        defer { ctxPtr.release() }

        SSLSetIOFuncs(sslContext, sslReadFunc, sslWriteFunc)
        SSLSetConnection(sslContext, ctxPtr.toOpaque())

        // Set certificate
        let certs = [identity] as CFArray
        SSLSetCertificate(sslContext, certs)

        // Perform TLS handshake with the client
        var handshakeStatus = SSLHandshake(sslContext)
        while handshakeStatus == errSSLWouldBlock {
            Thread.sleep(forTimeInterval: 0.01)
            handshakeStatus = SSLHandshake(sslContext)
        }

        if handshakeStatus != noErr {
            print("[MITM] TLS handshake failed for \(host): \(handshakeStatus)")
            return
        }

        // 4. Read the decrypted HTTP request from the client
        guard let decryptedResult = readFullHTTPRequest(sslContext: sslContext),
              let httpRequest = HTTPParser.parseRequest(from: decryptedResult.completeData) else {
            print("[MITM] Failed to parse decrypted HTTP request for \(host)")
            return
        }

        // 5. Build the full HTTPS URL
        let path = httpRequest.url.hasPrefix("/") ? httpRequest.url : "/\(httpRequest.url)"
        let fullURL = "https://\(host)\(port != 443 ? ":\(port)" : "")\(path)"

        // 6. Check Map Local rules
        if let mapLocal = matchMapLocal(method: httpRequest.method, url: fullURL, requestBody: httpRequest.body.loggableString) {
            if mapLocal.delaySeconds > 0 {
                Thread.sleep(forTimeInterval: mapLocal.delaySeconds)
            }
            let responseBody = loadLocalResponse(rule: mapLocal)
            let headers = ["Content-Type": mapLocal.contentType, "X-ProxyMock-MapLocal": "true"]
            let log = NetworkLog(
                method: httpRequest.method, url: fullURL,
                requestHeaders: httpRequest.headersDict,
                requestBody: httpRequest.body.loggableString,
                responseStatusCode: mapLocal.statusCode,
                responseHeaders: headers, responseBody: responseBody.loggableString,
                duration: Date().timeIntervalSince(startTime), isMocked: true, isHTTPS: true
            )
            onLog(log)
            let httpResponse = buildHTTPResponse(statusCode: mapLocal.statusCode, headers: headers, body: responseBody)
            sslWrite(sslContext, data: httpResponse)
            return
        }

        // 7. Check Mock rules
        if let mockRule = mockEngine.matchRule(method: httpRequest.method, url: fullURL, rules: config.mockRules) {
            let log = NetworkLog(
                method: httpRequest.method, url: fullURL,
                requestHeaders: httpRequest.headersDict,
                requestBody: httpRequest.body.loggableString,
                responseStatusCode: mockRule.responseStatusCode,
                responseHeaders: mockRule.responseHeaders, responseBody: mockRule.responseBody,
                duration: Date().timeIntervalSince(startTime), isMocked: true, isHTTPS: true
            )
            onLog(log)
            let responseBodyData = mockRule.responseBody.data(using: .utf8) ?? Data()
            let httpResponse = buildHTTPResponse(statusCode: mockRule.responseStatusCode, headers: mockRule.responseHeaders, body: responseBodyData)
            sslWrite(sslContext, data: httpResponse)
            return
        }

        // 8. Forward to the real server via URLSession
        let semaphore = DispatchSemaphore(value: 0)
        var responseLog: NetworkLog?
        var responseHTTP: Data?

        // Apply map remote if matched
        let targetURL = applyMapRemote(method: httpRequest.method, url: fullURL) ?? fullURL

        guard let url = URL(string: targetURL) else { return }
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = httpRequest.method
        for (key, value) in httpRequest.headers {
            let lk = key.lowercased()
            if lk == "proxy-connection" || lk == "proxy-authorization" || lk == "host" { continue }
            urlRequest.setValue(value, forHTTPHeaderField: key)
        }
        urlRequest.setValue(host, forHTTPHeaderField: "Host")
        if !httpRequest.body.isEmpty { urlRequest.httpBody = httpRequest.body }
        urlRequest.timeoutInterval = 30

        // Add throttle delay
        if config.isThrottleEnabled && config.throttleLatencyMs > 0 {
            Thread.sleep(forTimeInterval: Double(config.throttleLatencyMs) / 1000.0)
        }

        let session = sharedNoProxySession
        session.dataTask(with: urlRequest) { data, response, error in
            let httpResponse = response as? HTTPURLResponse
            let statusCode = httpResponse?.statusCode ?? (error != nil ? 502 : 200)
            var respHeaders: [String: String] = [:]
            if let headersDict = httpResponse?.allHeaderFields as? [String: String] {
                respHeaders = headersDict
            } else if let headersDict = httpResponse?.allHeaderFields {
                for (k, v) in headersDict {
                    if let kStr = k as? String, let vStr = v as? String {
                        respHeaders[kStr] = vStr
                    } else {
                        respHeaders[String(describing: k)] = String(describing: v)
                    }
                }
            }
            let bodyData = data ?? Data()
            let bodyString = bodyData.loggableString

            let log = NetworkLog(
                method: httpRequest.method, url: fullURL,
                requestHeaders: httpRequest.headersDict,
                requestBody: httpRequest.body.loggableString,
                responseStatusCode: statusCode, responseHeaders: respHeaders,
                responseBody: error != nil ? "Error: \(error!.localizedDescription)" : bodyString,
                duration: Date().timeIntervalSince(startTime), isHTTPS: true
            )
            responseLog = log
            let finalBodyData = error != nil ? ("Error: \(error!.localizedDescription)".data(using: .utf8) ?? Data()) : bodyData
            responseHTTP = self.buildHTTPResponse(statusCode: statusCode, headers: respHeaders, body: finalBodyData)
            semaphore.signal()
        }.resume()

        semaphore.wait()

        if let log = responseLog { onLog(log) }
        if let httpResp = responseHTTP { sslWrite(sslContext, data: httpResp) }
    }

    private func sslWrite(_ ctx: SSLContext, data: Data) {
        data.withUnsafeBytes { rawBuffer in
            guard let ptr = rawBuffer.baseAddress else { return }
            var written = 0
            var remaining = data.count
            var offset = 0
            while remaining > 0 {
                let status = SSLWrite(ctx, ptr.advanced(by: offset), remaining, &written)
                if status != noErr { break }
                offset += written
                remaining -= written
            }
        }
    }

    // MARK: - CONNECT Tunnel (fallback when MITM disabled)

    private func handleConnectTunnel(request: ParsedHTTPRequest, overflowData: Data, startTime: Date) {
        let host = request.host
        let port = request.port

        let log = NetworkLog(
            method: "CONNECT", url: "https://\(request.url)",
            requestHeaders: request.headersDict,
            requestBody: "CONNECT \(request.url) HTTP/1.1",
            responseStatusCode: 200,
            responseHeaders: ["Connection": "Established"],
            responseBody: "🔒 HTTPS Tunnel (MITM disabled)\nHost: \(host)\nPort: \(port)\n\nEnable 'SSL Proxying' to see decrypted content.",
            duration: Date().timeIntervalSince(startTime), isHTTPS: true
        )
        onLog(log)

        // Send 200 Connection Established
        _ = writeToSocket(clientFd, string: "HTTP/1.1 200 Connection Established\r\n\r\n")

        // Tunnel: connect to real server and relay bytes
        guard let serverFd = connectToServer(host: host, port: port) else { return }
        defer { Darwin.close(serverFd) }

        // Send any overflow data we accidentally read from client to the server first
        if !overflowData.isEmpty {
            _ = writeToSocket(serverFd, data: overflowData)
        }

        relayBidirectional(fd1: clientFd, fd2: serverFd)
    }

    // MARK: - HTTP Request (non-HTTPS)

    private func handleHTTPRequest(request: ParsedHTTPRequest, startTime: Date) {
        
        // Check Map Local
        if let mapLocal = matchMapLocal(method: request.method, url: request.fullURL, requestBody: request.body.loggableString) {
            if mapLocal.delaySeconds > 0 {
                Thread.sleep(forTimeInterval: mapLocal.delaySeconds)
            }
            let body = loadLocalResponse(rule: mapLocal)
            let headers = ["Content-Type": mapLocal.contentType]
            let log = NetworkLog(method: request.method, url: request.fullURL,
                                 requestHeaders: request.headersDict,
                                 requestBody: request.body.loggableString,
                                 responseStatusCode: mapLocal.statusCode, responseHeaders: headers,
                                 responseBody: body.loggableString, duration: Date().timeIntervalSince(startTime), isMocked: true)
            onLog(log)
            let resp = HTTPParser.buildResponse(statusCode: mapLocal.statusCode, headers: headers, body: body)
            _ = writeToSocket(clientFd, data: resp)
            return
        }

        // Check Mock rules
        if let mockRule = mockEngine.matchRule(method: request.method, url: request.fullURL, rules: config.mockRules) {
            handleMockedResponse(request: request, rule: mockRule, startTime: startTime)
            return
        }

        // Apply Map Remote
        let targetURL = applyMapRemote(method: request.method, url: request.fullURL) ?? request.fullURL

        // Throttle delay
        if config.isThrottleEnabled && config.throttleLatencyMs > 0 {
            Thread.sleep(forTimeInterval: Double(config.throttleLatencyMs) / 1000.0)
        }

        // Forward
        forwardHTTPRequest(request: request, targetURL: targetURL, startTime: startTime)
    }

    private func handleMockedResponse(request: ParsedHTTPRequest, rule: MockRule, startTime: Date) {
        if rule.delaySeconds > 0 {
            Thread.sleep(forTimeInterval: rule.delaySeconds)
        }

        let log = NetworkLog(
            method: request.method, url: request.fullURL,
            requestHeaders: request.headersDict,
            requestBody: request.body.loggableString,
            responseStatusCode: rule.responseStatusCode,
            responseHeaders: rule.responseHeaders, responseBody: rule.responseBody,
            duration: Date().timeIntervalSince(startTime), isMocked: true
        )
        onLog(log)

        let respData = rule.responseBody.data(using: .utf8) ?? Data()
        let resp = HTTPParser.buildResponse(statusCode: rule.responseStatusCode, headers: rule.responseHeaders, body: respData)
        _ = writeToSocket(clientFd, data: resp)
    }

    private func forwardHTTPRequest(request: ParsedHTTPRequest, targetURL: String, startTime: Date) {
        guard let url = URL(string: targetURL) else {
            let errorBody = "Bad Gateway: Invalid URL".data(using: .utf8) ?? Data()
            let resp = HTTPParser.buildResponse(statusCode: 502, headers: ["Content-Type": "text/plain"], body: errorBody)
            _ = writeToSocket(clientFd, data: resp)
            return
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = request.method
        for (key, value) in request.headers {
            let lk = key.lowercased()
            if lk == "proxy-connection" || lk == "proxy-authorization" { continue }
            urlRequest.setValue(value, forHTTPHeaderField: key)
        }
        if !request.body.isEmpty { urlRequest.httpBody = request.body }
        urlRequest.timeoutInterval = 30

        let semaphore = DispatchSemaphore(value: 0)
        var responseData: Data?

        let session = sharedNoProxySession
        session.dataTask(with: urlRequest) { [self] data, response, error in
            let httpResponse = response as? HTTPURLResponse
            let statusCode = httpResponse?.statusCode ?? (error != nil ? 502 : 200)
            var headers: [String: String] = [:]
            if let headersDict = httpResponse?.allHeaderFields as? [String: String] {
                headers = headersDict
            } else if let headersDict = httpResponse?.allHeaderFields {
                for (k, v) in headersDict {
                    if let kStr = k as? String, let vStr = v as? String {
                        headers[kStr] = vStr
                    } else {
                        headers[String(describing: k)] = String(describing: v)
                    }
                }
            }
            let bodyData = data ?? Data()
            let bodyString = bodyData.loggableString

            let log = NetworkLog(
                method: request.method, url: request.fullURL,
                requestHeaders: request.headersDict,
                requestBody: request.body.loggableString,
                responseStatusCode: statusCode, responseHeaders: headers,
                responseBody: error != nil ? "Error: \(error!.localizedDescription)" : bodyString,
                duration: Date().timeIntervalSince(startTime)
            )
            onLog(log)

            let finalBodyData = error != nil ? ("Error: \(error!.localizedDescription)".data(using: .utf8) ?? Data()) : bodyData
            responseData = HTTPParser.buildResponse(statusCode: statusCode, headers: headers, body: finalBodyData)
            semaphore.signal()
        }.resume()

        semaphore.wait()
        if let resp = responseData { _ = writeToSocket(clientFd, data: resp) }
    }

    // MARK: - Helpers

    private func matchMapLocal(method: String, url: String, requestBody: String) -> MapLocalRule? {
        for rule in config.mapLocalRules where rule.isEnabled {
            if rule.httpMethod != "*" && rule.httpMethod.uppercased() != method.uppercased() { continue }
            if matchesWildcard(url: url, pattern: rule.urlPattern) {
                // If the rule specifies a request body match, check if it's present in the actual body
                if !rule.inlineRequestMatch.isEmpty {
                    if !requestBody.contains(rule.inlineRequestMatch) {
                        continue
                    }
                }
                return rule
            }
        }
        return nil
    }

    private func loadLocalResponse(rule: MapLocalRule) -> Data {
        switch rule.source {
        case .inline:
            return rule.inlineBody.data(using: .utf8) ?? Data()
        case .file:
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: rule.localFilePath)) else {
                return "Error: File not found at \(rule.localFilePath)".data(using: .utf8) ?? Data()
            }
            return data
        }
    }

    private func applyMapRemote(method: String, url: String) -> String? {
        for rule in config.mapRemoteRules where rule.isEnabled {
            if rule.httpMethod != "*" && rule.httpMethod.uppercased() != method.uppercased() { continue }
            if matchesWildcard(url: url, pattern: rule.sourcePattern) {
                if rule.preservePath, let originalURL = URL(string: url) {
                    return rule.destinationURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                        + originalURL.path + (originalURL.query.map { "?\($0)" } ?? "")
                }
                return rule.destinationURL
            }
        }
        return nil
    }

    private func matchesWildcard(url: String, pattern: String) -> Bool {
        return RegexCache.shared.matchesPattern(url: url, pattern: pattern)
    }

    private func buildHTTPResponse(statusCode: Int, headers: [String: String], body: Data) -> Data {
        HTTPParser.buildResponse(statusCode: statusCode, headers: headers, body: body)
    }

    // MARK: - Socket I/O

    private func readFullHTTPRequest(fd: Int32? = nil, sslContext: SSLContext? = nil) -> (completeData: Data, overflowData: Data)? {
        var completeData = Data()
        var overflowData = Data()
        var expectedContentLength: Int? = nil
        var headersParsed = false
        var bodyStartOffset = 0
        var isConnectMethod = false
        
        var buffer = [UInt8](repeating: 0, count: 65536)
        
        while true {
            var bytesRead = 0
            if let ctx = sslContext {
                let status = SSLRead(ctx, &buffer, buffer.count, &bytesRead)
                if status == errSSLClosedGraceful && bytesRead == 0 {
                    break // Client gracefully closed the TLS session (EOF)
                }
                if status != noErr && status != errSSLClosedGraceful {
                    if bytesRead == 0 {
                        if status == errSSLWouldBlock {
                            Thread.sleep(forTimeInterval: 0.01)
                            continue
                        }
                        return completeData.isEmpty ? nil : (completeData, overflowData)
                    }
                }
            } else if let clientFd = fd {
                let n = Darwin.read(clientFd, &buffer, buffer.count)
                if n <= 0 {
                    return completeData.isEmpty ? nil : (completeData, overflowData)
                }
                bytesRead = n
            } else {
                return nil
            }
            
            if bytesRead > 0 {
                completeData.append(buffer, count: bytesRead)
            }
            
            if !headersParsed {
                if let headerEnd = findHeaderEnd(in: completeData) {
                    headersParsed = true
                    bodyStartOffset = headerEnd + 4
                    
                    if let request = HTTPParser.parseRequest(from: completeData) {
                        isConnectMethod = request.isConnect
                        if isConnectMethod {
                            // If it's CONNECT, we don't have a body payload from the client yet,
                            // we just stop reading and chunk the rest into overflow.
                            if completeData.count > bodyStartOffset {
                                overflowData = completeData.subdata(in: bodyStartOffset..<completeData.count)
                                completeData = completeData.subdata(in: 0..<bodyStartOffset)
                            }
                            break
                        }

                        for (key, value) in request.headers {
                            if key.lowercased() == "content-length", let cl = Int(value) {
                                expectedContentLength = cl
                                break
                            }
                        }
                    }
                }
            }
            
            if headersParsed {
            
                if let cl = expectedContentLength {
                    if completeData.count - bodyStartOffset >= cl {
                        if completeData.count - bodyStartOffset > cl {
                            let end = bodyStartOffset + cl
                            overflowData = completeData.subdata(in: end..<completeData.count)
                            completeData = completeData.subdata(in: 0..<end)
                        }
                        break
                    }
                } else {
                    break
                }
            }
        }
        
        return completeData.isEmpty ? nil : (completeData, overflowData)
    }

    private func findHeaderEnd(in data: Data) -> Int? {
        let bytes = [UInt8](data)
        guard bytes.count >= 4 else { return nil }
        for i in 0..<(bytes.count - 3) {
            if bytes[i] == 13 && bytes[i+1] == 10 && bytes[i+2] == 13 && bytes[i+3] == 10 {
                return i
            }
        }
        return nil
    }

    @discardableResult
    private func writeToSocket(_ fd: Int32, data: Data) -> Bool {
        data.withUnsafeBytes { rawBuffer in
            guard let ptr = rawBuffer.baseAddress else { return false }
            var written = 0
            var remaining = data.count
            while remaining > 0 {
                let n = Darwin.write(fd, ptr.advanced(by: written), remaining)
                if n <= 0 { return false }
                written += n
                remaining -= n
            }
            return true
        }
    }

    @discardableResult
    private func writeToSocket(_ fd: Int32, string: String) -> Bool {
        guard let data = string.data(using: .utf8) else { return false }
        return writeToSocket(fd, data: data)
    }

    private func connectToServer(host: String, port: Int) -> Int32? {
        guard let hostEntry = gethostbyname(host) else { return nil }

        let serverFd = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard serverFd >= 0 else { return nil }
        
        guard let addrListPtr = hostEntry.pointee.h_addr_list.pointee else {
            Darwin.close(serverFd)
            return nil
        }

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = UInt16(port).bigEndian
        memcpy(&addr.sin_addr, addrListPtr, Int(hostEntry.pointee.h_length))

        let result = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                Darwin.connect(serverFd, sockPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }

        if result != 0 {
            Darwin.close(serverFd)
            return nil
        }
        return serverFd
    }

    private func relayBidirectional(fd1: Int32, fd2: Int32) {
        let group = DispatchGroup()

        group.enter()
        DispatchQueue.global().async {
            self.relayOneWay(from: fd1, to: fd2)
            group.leave()
        }

        group.enter()
        DispatchQueue.global().async {
            self.relayOneWay(from: fd2, to: fd1)
            group.leave()
        }

        group.wait()
    }

    private func relayOneWay(from src: Int32, to dst: Int32) {
        let bufferSize = 32768
        let buffer = UnsafeMutableRawBufferPointer.allocate(byteCount: bufferSize, alignment: 8)
        defer { buffer.deallocate() }

        while true {
            let n = Darwin.read(src, buffer.baseAddress, bufferSize)
            if n <= 0 { break }
            var written = 0
            while written < n {
                let w = Darwin.write(dst, buffer.baseAddress!.advanced(by: written), n - written)
                if w <= 0 { return }
                written += w
            }
        }
    }

    // MARK: - Certificate Serving
    
    private func serveCertificate(request: ParsedHTTPRequest) {
        do {
            let certData = try Data(contentsOf: CertPaths.caCertDERURL)
            Logger(subsystem: "ProxyMock", category: "ProxyMock.Lock").error("serveCertificate ca path \(CertPaths.caCertDERURL, privacy: .public)")
            let headers = [
                "Content-Type": "application/x-x509-ca-cert",
                "Content-Disposition": "attachment; filename=\"ProxyMock-Root-CA.cer\"",
                "Content-Length": "\(certData.count)"
            ]
            let resp = HTTPParser.buildResponse(statusCode: 200, headers: headers, body: certData)
            _ = writeToSocket(clientFd, data: resp)
            
            let log = NetworkLog(method: "GET", url: "http://proxy.mock/cert", requestHeaders: request.headersDict, requestBody: "", responseStatusCode: 200, responseHeaders: headers, responseBody: "Downloaded Root Certificate (\(certData.count) bytes)", duration: 0.01, isMocked: true)
            onLog(log)
        } catch {
            
            let errorLog = "Certificate error. Path: \(CertPaths.caCertDERURL.path). Error: \(error.localizedDescription)"
            print("[Proxy] \(errorLog)")
            Logger(subsystem: "ProxyMock", category: "ProxyMock.Lock").error("serveCertificate error \(errorLog, privacy: .public)")
            let errorBody = "Certificate not found. Please activate SSL Proxying in ProxyMock first.\n\nDebug Info: \(errorLog)".data(using: .utf8) ?? Data()
            let resp = HTTPParser.buildResponse(statusCode: 404, headers: ["Content-Type": "text/plain"], body: errorBody)
            _ = writeToSocket(clientFd, data: resp)
        }
    }
}

// MARK: - SecureTransport SSL Callbacks

/// Read callback for SSLSetIOFuncs — reads from the client socket FD
private func sslReadFunc(
    connection: SSLConnectionRef,
    data: UnsafeMutableRawPointer,
    dataLength: UnsafeMutablePointer<Int>
) -> OSStatus {
    let ctx = Unmanaged<SSLConnectionContext>.fromOpaque(connection).takeUnretainedValue()
    let fd = ctx.fd
    let requested = dataLength.pointee
    
    var bytesRead = 0
    let dstBuffer = data.assumingMemoryBound(to: UInt8.self)
    
    // 1. Drain overflowData first
    if !ctx.overflowData.isEmpty {
        let toCopy = min(requested, ctx.overflowData.count)
        ctx.overflowData.copyBytes(to: dstBuffer, count: toCopy)
        ctx.overflowData.removeFirst(toCopy)
        bytesRead += toCopy
        
        if bytesRead == requested {
            dataLength.pointee = bytesRead
            return noErr
        }
    }
    
    // 2. Read remainder from socket
    let remainingToRead = requested - bytesRead
    let n = Darwin.read(fd, dstBuffer.advanced(by: bytesRead), remainingToRead)
    
    if n == 0 {
        dataLength.pointee = bytesRead
        // If we read something from overflow, return noErr so the caller processes it
        return bytesRead > 0 ? noErr : errSSLClosedGraceful
    }
    if n < 0 {
        dataLength.pointee = bytesRead
        if bytesRead > 0 {
            return noErr
        }
        if errno == EWOULDBLOCK || errno == EAGAIN {
            return errSSLWouldBlock
        }
        return errSSLClosedAbort
    }
    
    dataLength.pointee = bytesRead + n
    return noErr
}

/// Write callback for SSLSetIOFuncs — writes to the client socket FD
private func sslWriteFunc(
    connection: SSLConnectionRef,
    data: UnsafeRawPointer,
    dataLength: UnsafeMutablePointer<Int>
) -> OSStatus {
    let ctx = Unmanaged<SSLConnectionContext>.fromOpaque(connection).takeUnretainedValue()
    let fd = ctx.fd
    let requested = dataLength.pointee
    let n = Darwin.write(fd, data, requested)
    if n <= 0 {
        dataLength.pointee = 0
        if errno == EWOULDBLOCK || errno == EAGAIN {
            return errSSLWouldBlock
        }
        return errSSLClosedAbort
    }
    dataLength.pointee = n
    return noErr
}
