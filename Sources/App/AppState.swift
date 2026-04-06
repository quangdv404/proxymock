import Foundation
import SwiftUI

/// Global application state — observable by all views
@MainActor
@Observable
final class AppState {
    var proxyServer: ProxyServer
    var mockEngine: MockEngine
    var breakpointManager: BreakpointManager
    var certManager: CertificateManager
    var pushEngine = PushNotificationEngine()
    var logs: [NetworkLog] = []
    var port: UInt16 = 9090
    var autoStart: Bool = false
    var isSystemProxyEnabled: Bool = false
    var selectedSidebarItem: SidebarItem = .dashboard

    // Map Local / Map Remote
    var mapLocalRules: [MapLocalRule] = []
    var mapRemoteRules: [MapRemoteRule] = []
    var draftMapLocalRule: MapLocalRule?

    // Domain filter
    var domainFilterMode: DomainFilterMode = .disabled
    var domainFilterRules: [DomainFilterRule] = []
    
    // Log View search state
    var logSearchText: String = ""
    var logMethodFilter: String = "ALL"
    
    // Log batching
    nonisolated(unsafe) private var pendingLogs: [NetworkLog] = []
    private let pendingLogsLock = NSLock()
    private var logUpdateTimer: Timer?
    
    // Throttle
    var throttleProfile: ThrottleProfile = ThrottleProfile.presets[0]
    var isThrottleEnabled: Bool = false

    // Compose request
    var showComposeSheet: Bool = false
    var composeFromLog: NetworkLog?
    var mitmEnabled: Bool = true

    // Error state
    var showProxyError: Bool = false
    var proxyErrorMessage: String = ""

    func setMITM(_ enabled: Bool) {
        mitmEnabled = enabled
        proxyServer.mitmEnabled = enabled
    }

    enum SidebarItem: String, CaseIterable, Identifiable {
        case dashboard = "Dashboard"
        case logs = "Network Logs"
        case mockRules = "Mock Rules"
        case breakpoints = "Breakpoints"
        case mapLocal = "Map Local"
        case mapRemote = "Map Remote"
        case domainFilter = "Block/Allow"
        case throttle = "Throttle"
        case compose = "Compose"
        case push = "Push Notifications"
        case settings = "Settings"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .dashboard: return "gauge.with.dots.needle.33percent"
            case .logs: return "list.bullet.rectangle"
            case .mockRules: return "doc.text.magnifyingglass"
            case .breakpoints: return "pause.circle"
            case .mapLocal: return "doc.on.doc"
            case .mapRemote: return "arrow.triangle.branch"
            case .domainFilter: return "shield.lefthalf.filled"
            case .throttle: return "speedometer"
            case .compose: return "paperplane"
            case .push: return "bell.badge"
            case .settings: return "gear"
            }
        }
    }

    init() {
        let engine = MockEngine()
        let bpManager = BreakpointManager()
        let certMgr = CertificateManager()
        self.mockEngine = engine
        self.breakpointManager = bpManager
        self.certManager = certMgr
        self.proxyServer = ProxyServer(mockEngine: engine)

        // Load saved data
        engine.setRules(MockRuleStore.load())
        bpManager.load()
        mapLocalRules = FeatureStore.loadMapLocal()
        mapRemoteRules = FeatureStore.loadMapRemote()
        domainFilterRules = FeatureStore.loadDomainFilters()
        domainFilterMode = FeatureStore.loadDomainFilterMode()

        // Wire up proxy server features
        proxyServer.breakpointManager = bpManager
        proxyServer.certManager = certMgr
        proxyServer.configProvider = { [weak self] in
            guard let self = self else {
                return ProxyConfig(mockRules: [], mapLocalRules: [], mapRemoteRules: [],
                                   breakpointRules: [], throttleLatencyMs: 0, isThrottleEnabled: false,
                                   domainFilterRules: [])
            }
            return ProxyConfig(
                mockRules: self.mockEngine.allRules,
                mapLocalRules: self.mapLocalRules.filter(\.isEnabled),
                mapRemoteRules: self.mapRemoteRules.filter(\.isEnabled),
                breakpointRules: self.breakpointManager.rules.filter(\.isEnabled),
                throttleLatencyMs: self.throttleProfile.latencyMs,
                isThrottleEnabled: self.isThrottleEnabled,
                domainFilterRules: self.domainFilterRules
            )
        }

        // Start log batching timer
        Task { @MainActor [weak self] in
            self?.logUpdateTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
                Task { @MainActor in
                    self?.flushLogBuffer()
                }
            }
        }

        // Wire up logging
        proxyServer.onLog = { [weak self] log in
            guard let self = self else { return }
            self.pendingLogsLock.lock()
            self.pendingLogs.append(log)
            self.pendingLogsLock.unlock()
        }
    }

    @MainActor
    private func flushLogBuffer() {
        pendingLogsLock.lock()
        let toProcess = pendingLogs
        pendingLogs.removeAll()
        pendingLogsLock.unlock()
        
        guard !toProcess.isEmpty else { return }
        
        var newLogs = self.logs
        for log in toProcess {
            if let index = newLogs.firstIndex(where: { $0.id == log.id }) {
                newLogs[index] = log
            } else {
                newLogs.insert(log, at: 0)
            }
        }
        if newLogs.count > 100 {
            newLogs = Array(newLogs.prefix(100))
        }
        self.logs = newLogs
    }

    var isRunning: Bool { proxyServer.isRunning }
    var totalRequests: Int { logs.count }
    var mockedRequests: Int { logs.filter(\.isMocked).count }

    func startProxy() {
        do {
            proxyServer.mitmEnabled = mitmEnabled
            try proxyServer.start(port: port)
        } catch {
            print("[App] Failed to start proxy: \(error)")
            proxyErrorMessage = error.localizedDescription
            if let proxyError = error as? ProxyError, case .bindFailed = proxyError {
                proxyErrorMessage += "\n\nIf you copied this app from another Mac, your macOS Application Firewall might be blocking it because the ad-hoc signature is invalid on this machine. Run the distribute script to fix this."
            }
            showProxyError = true
        }
    }

    func stopProxy() {
        disableSystemProxy()
        proxyServer.stop()
    }

    func toggleSystemProxy() {
        if isSystemProxyEnabled { disableSystemProxy() } else { enableSystemProxy() }
    }

    func enableSystemProxy() {
        if SystemProxyHelper.enableProxy(port: port) { isSystemProxyEnabled = true }
    }

    func disableSystemProxy() {
        if isSystemProxyEnabled {
            _ = SystemProxyHelper.disableProxy()
            isSystemProxyEnabled = false
        }
    }

    func clearLogs() { logs.removeAll() }

    func saveRules() { MockRuleStore.save(mockEngine.allRules) }

    // MARK: - Map Local
    func saveMapLocalRules() { FeatureStore.saveMapLocal(mapLocalRules) }
    func addMapLocalRule(_ rule: MapLocalRule) { mapLocalRules.append(rule); saveMapLocalRules() }
    func addMapLocalRules(_ rules: [MapLocalRule]) { mapLocalRules.append(contentsOf: rules); saveMapLocalRules() }
    func deleteMapLocalRule(id: UUID) { mapLocalRules.removeAll { $0.id == id }; saveMapLocalRules() }
    func updateMapLocalRule(_ rule: MapLocalRule) {
        if let i = mapLocalRules.firstIndex(where: { $0.id == rule.id }) { mapLocalRules[i] = rule; saveMapLocalRules() }
    }

    // MARK: - Map Remote
    func saveMapRemoteRules() { FeatureStore.saveMapRemote(mapRemoteRules) }
    func addMapRemoteRule(_ rule: MapRemoteRule) { mapRemoteRules.append(rule); saveMapRemoteRules() }
    func deleteMapRemoteRule(id: UUID) { mapRemoteRules.removeAll { $0.id == id }; saveMapRemoteRules() }
    func updateMapRemoteRule(_ rule: MapRemoteRule) {
        if let i = mapRemoteRules.firstIndex(where: { $0.id == rule.id }) { mapRemoteRules[i] = rule; saveMapRemoteRules() }
    }

    // MARK: - Domain Filter
    func saveDomainFilters() {
        FeatureStore.saveDomainFilters(domainFilterRules)
        FeatureStore.saveDomainFilterMode(domainFilterMode)
    }

    /// Check if a URL should be filtered (blocked) by domain rules
    func shouldFilter(url: String) -> Bool {
        guard domainFilterMode != .disabled else { return false }
        let host = URL(string: url)?.host ?? url
        let matched = domainFilterRules.filter(\.isEnabled).contains { rule in
            host.localizedCaseInsensitiveContains(rule.domain) ||
            matchWildcard(input: host, pattern: rule.domain)
        }
        return domainFilterMode == .blockList ? matched : !matched
    }

    private func matchWildcard(input: String, pattern: String) -> Bool {
        return RegexCache.shared.matchesPattern(url: input, pattern: pattern)
    }

    // MARK: - Compose Request

    func sendComposedRequest(method: String, url: String, headers: [String: String], body: String) {
        guard let targetURL = URL(string: url) else { return }
        var request = URLRequest(url: targetURL)
        request.httpMethod = method
        for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
        if !body.isEmpty { request.httpBody = body.data(using: .utf8) }
        request.timeoutInterval = 30

        let startTime = Date()
        let noProxyCfg = URLSessionConfiguration.ephemeral
        noProxyCfg.connectionProxyDictionary = [:]
        let session = URLSession(configuration: noProxyCfg, delegate: ComposeSessionDelegate(), delegateQueue: nil)
        
        session.dataTask(with: request) { [weak self] data, response, error in
            defer { session.finishTasksAndInvalidate() }
            let httpResponse = response as? HTTPURLResponse
            let statusCode = httpResponse?.statusCode ?? (error != nil ? 0 : 200)
            var responseHeaders: [String: String] = [:]
            if let headersDict = httpResponse?.allHeaderFields as? [String: String] {
                responseHeaders = headersDict
            } else if let headersDict = httpResponse?.allHeaderFields {
                for (k, v) in headersDict {
                    if let kStr = k as? String, let vStr = v as? String {
                        responseHeaders[kStr] = vStr
                    } else {
                        responseHeaders[String(describing: k)] = String(describing: v)
                    }
                }
            }
            let bodyData = data ?? Data()
            let bodyString = bodyData.loggableString

            let log = NetworkLog(
                method: method,
                url: url,
                requestHeaders: headers,
                requestBody: body,
                responseStatusCode: statusCode,
                responseHeaders: responseHeaders,
                responseBody: error != nil ? "Error: \(error!.localizedDescription)" : bodyString,
                duration: Date().timeIntervalSince(startTime)
            )
            self?.pendingLogsLock.lock()
            self?.pendingLogs.append(log)
            self?.pendingLogsLock.unlock()
        }.resume()
    }

    // MARK: - Local IP
    var localIPAddress: String {
        var address = "Unknown"
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return address }
        defer { freeifaddrs(ifaddr) }
        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let interface = ptr.pointee
            if interface.ifa_addr.pointee.sa_family == UInt8(AF_INET) {
                let name = String(cString: interface.ifa_name)
                if name == "en0" {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(interface.ifa_addr, socklen_t(interface.ifa_addr.pointee.sa_len),
                                &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST)
                    address = hostname.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
                }
            }
        }
        return address
    }
}

private final class ComposeSessionDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
