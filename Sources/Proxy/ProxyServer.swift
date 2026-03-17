import Foundation
import Network

/// TCP proxy server using POSIX sockets for full connection control (needed for MITM TLS)
@MainActor
@Observable
final class ProxyServer {
    private var serverFd: Int32 = -1
    private var acceptQueue: DispatchQueue?
    private let mockEngine: MockEngine
    private(set) var isRunning: Bool = false
    private(set) var port: UInt16 = 9090
    private(set) var connectionCount: Int = 0

    var onLog: (@Sendable (NetworkLog) -> Void)?
    var breakpointManager: BreakpointManager?
    var certManager: CertificateManager?
    var configProvider: (@MainActor () -> ProxyConfig)?
    var mitmEnabled: Bool = false

    init(mockEngine: MockEngine) {
        self.mockEngine = mockEngine
    }

    func start(port: UInt16 = 9090) throws {
        self.port = port

        // Create TCP socket
        serverFd = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard serverFd >= 0 else {
            throw ProxyError.socketCreationFailed
        }

        // Set socket options
        var opt: Int32 = 1
        setsockopt(serverFd, SOL_SOCKET, SO_REUSEADDR, &opt, socklen_t(MemoryLayout<Int32>.size))
        setsockopt(serverFd, SOL_SOCKET, SO_REUSEPORT, &opt, socklen_t(MemoryLayout<Int32>.size))

        // Bind to port
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr.s_addr = INADDR_ANY

        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                Darwin.bind(serverFd, sockPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else {
            Darwin.close(serverFd)
            serverFd = -1
            throw ProxyError.bindFailed(port: port)
        }

        // Listen
        guard Darwin.listen(serverFd, 128) == 0 else {
            Darwin.close(serverFd)
            serverFd = -1
            throw ProxyError.listenFailed
        }

        isRunning = true
        print("[Proxy] Server started on port \(port)")

        // Accept loop on background queue
        let fd = serverFd
        acceptQueue = DispatchQueue(label: "proxymock.accept", qos: .userInitiated)
        acceptQueue?.async { [weak self] in
            self?.acceptLoop(serverFd: fd)
        }
    }

    private func acceptLoop(serverFd: Int32) {
        while true {
            let clientFd = Darwin.accept(serverFd, nil, nil)
            if clientFd < 0 {
                // Server was closed
                break
            }

            Task { @MainActor [weak self] in
                self?.connectionCount += 1
            }

            // Snapshot config on main actor, then handle on background
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                let config = self.configProvider?() ?? ProxyConfig(
                    mockRules: self.mockEngine.allRules,
                    mapLocalRules: [], mapRemoteRules: [],
                    breakpointRules: [], throttleLatencyMs: 0, isThrottleEnabled: false,
                    domainFilterRules: []
                )
                let logHandler = self.onLog ?? { _ in }
                let engine = self.mockEngine
                let mitmOn = self.mitmEnabled

                DispatchQueue.global(qos: .userInitiated).async {
                    let handler = ConnectionHandler(
                        clientFd: clientFd,
                        mockEngine: engine,
                        config: config,
                        mitmEnabled: mitmOn,
                        onLog: logHandler
                    )
                    handler.handle()
                }
            }
        }
    }

    func stop() {
        if serverFd >= 0 {
            Darwin.close(serverFd)
            serverFd = -1
        }
        isRunning = false
        connectionCount = 0
        print("[Proxy] Server stopped")
    }

    func restart(port: UInt16) throws {
        stop()
        try start(port: port)
    }
}

enum ProxyError: LocalizedError {
    case socketCreationFailed
    case bindFailed(port: UInt16)
    case listenFailed

    var errorDescription: String? {
        switch self {
        case .socketCreationFailed: return "Failed to create socket"
        case .bindFailed(let port): return "Failed to bind to port \(port) — is it already in use?"
        case .listenFailed: return "Failed to listen on socket"
        }
    }
}
