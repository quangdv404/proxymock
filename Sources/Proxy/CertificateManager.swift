import Foundation
import Security
import os.log

private let certLog = Logger(subsystem: "ProxyMock", category: "CertMgr")

/// Manages CA and per-host certificates for HTTPS MITM interception.
/// Uses the `openssl` CLI (available as LibreSSL on macOS) for cert generation.
@MainActor
@Observable
final class CertificateManager {
    private(set) var isCAGenerated: Bool = false
    private(set) var isCAInstalled: Bool = false

    var caCertURL: URL { CertPaths.caCertURL }

    init() {
        isCAGenerated = FileManager.default.fileExists(atPath: CertPaths.caCertPath)
        if isCAGenerated { checkCAInstalled() }
    }

    // MARK: - CA Management

    func generateCA() -> Bool {
        _ = CertPaths.shell("/usr/bin/openssl genrsa -out \"\(CertPaths.caKeyPath)\" 2048 2>&1")
        _ = CertPaths.shell("""
            /usr/bin/openssl req -x509 -new -nodes -key "\(CertPaths.caKeyPath)" -sha256 -days 3650 \
            -out "\(CertPaths.caCertPath)" -subj "/CN=ProxyMock Root CA/O=ProxyMock/OU=Development" \
            -addext "basicConstraints=critical,CA:TRUE" \
            -addext "keyUsage=critical,keyCertSign,cRLSign" 2>&1
            """)
        _ = CertPaths.shell("""
            /usr/bin/openssl x509 -in "\(CertPaths.caCertPath)" -outform der -out "\(CertPaths.caCertDERPath)" 2>&1
            """)
        isCAGenerated = FileManager.default.fileExists(atPath: CertPaths.caCertPath) && FileManager.default.fileExists(atPath: CertPaths.caCertDERPath)
        let generated = isCAGenerated
        certLog.info("CA generated: \(generated)")
        return isCAGenerated
    }

    func installCA() -> Bool {
        guard isCAGenerated else { return false }
        _ = CertPaths.shell("""
            /usr/bin/security add-trusted-cert -r trustRoot -k ~/Library/Keychains/login.keychain-db "\(CertPaths.caCertPath)" 2>&1
            """)
        checkCAInstalled()
        return isCAInstalled
    }

    private func checkCAInstalled() {
        let result = CertPaths.shell("/usr/bin/security find-certificate -c \"ProxyMock Root CA\" 2>&1")
        isCAInstalled = result.contains("ProxyMock Root CA")
    }
}

/// Thread-safe certificate path and generation helpers (can be called from any thread)
enum CertPaths: Sendable {
    // Computed once at first access (safe: Swift static let is lazily initialized under a lock).
    // Previously these were computed `var` properties that called FileManager.urls(for:) on every
    // access — including from hundreds of concurrent background proxy threads — which triggered a
    // SIGTRAP inside Foundation's _DarwinSearchPaths and caused an infinite signal-handler loop.
    static let baseDir: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("ProxyMock/Certs", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    static let hostsDir: URL = {
        let dir = baseDir.appendingPathComponent("hosts", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    static let caKeyPath: String = baseDir.appendingPathComponent("ca-key.pem").path
    static let caCertPath: String = baseDir.appendingPathComponent("ca.pem").path
    static let caCertDERPath: String = baseDir.appendingPathComponent("ca.cer").path
    static let caCertURL: URL = baseDir.appendingPathComponent("ca.pem")
    static let caCertDERURL: URL = baseDir.appendingPathComponent("ca.cer")

    // MARK: - Identity Cache
    // SecPKCS12Import is NOT thread-safe under concurrent load — calling it from hundreds of
    // simultaneous proxy threads causes _CFRuntimeCreateInstance to crash inside the Security
    // framework. We cache the loaded SecIdentity per-hostname under a lock so the expensive
    // (and non-reentrant) import path is only executed once per host.
    private static let identityLock = NSLock()
    // nonisolated(unsafe): manually protected by identityLock above
    private nonisolated(unsafe) static var identityCache: [String: SecIdentity] = [:]

    /// Get or generate a PKCS12 certificate for a hostname (thread-safe).
    /// Serialized under identityLock to prevent concurrent generateHostCert calls for
    /// the same host (which would race on openssl output files and corrupt the P12).
    static func getP12Path(for host: String) -> String? {
        let hostDir = hostsDir.appendingPathComponent(host)
        let p12Path = hostDir.appendingPathComponent("cert.p12").path

        // Fast path: cert already exists — no lock needed for read-only file check
        if FileManager.default.fileExists(atPath: p12Path) { return p12Path }

        // Slow path: generate under lock so only one thread generates per host at a time
        identityLock.lock()
        defer { identityLock.unlock() }
        // Re-check — another thread may have generated it while we waited
        if FileManager.default.fileExists(atPath: p12Path) { return p12Path }
        return generateHostCert(for: host)
    }

    static func generateHostCert(for host: String) -> String? {
        let hostDir = hostsDir.appendingPathComponent(host)
        try? FileManager.default.createDirectory(at: hostDir, withIntermediateDirectories: true)

        let keyPath = hostDir.appendingPathComponent("key.pem").path
        let csrPath = hostDir.appendingPathComponent("cert.csr").path
        let certPath = hostDir.appendingPathComponent("cert.pem").path
        let p12Path = hostDir.appendingPathComponent("cert.p12").path
        let extPath = hostDir.appendingPathComponent("ext.cnf").path

        try? "subjectAltName = DNS:\(host)".write(toFile: extPath, atomically: true, encoding: .utf8)

        _ = shell("/usr/bin/openssl genrsa -out \"\(keyPath)\" 2048 2>&1")
        _ = shell("/usr/bin/openssl req -new -key \"\(keyPath)\" -out \"\(csrPath)\" -subj \"/CN=\(host)\" 2>&1")
        _ = shell("""
            /usr/bin/openssl x509 -req -in "\(csrPath)" -CA "\(caCertPath)" -CAkey "\(caKeyPath)" \
            -CAcreateserial -out "\(certPath)" -days 365 -sha256 \
            -extfile "\(extPath)" 2>&1
            """)
        _ = shell("""
            /usr/bin/openssl pkcs12 -export -out "\(p12Path)" -inkey "\(keyPath)" -in "\(certPath)" \
            -certfile "\(caCertPath)" -passout pass:proxymock 2>&1
            """)

        if FileManager.default.fileExists(atPath: p12Path) {
            certLog.info("Generated cert for \(host, privacy: .public)")
            // Evict stale cache entry so the new cert gets loaded fresh next time
            identityLock.lock()
            identityCache.removeValue(forKey: p12Path)
            identityLock.unlock()
            return p12Path
        }
        certLog.error("❌ Failed to generate cert for \(host, privacy: .public)")
        return nil
    }

    /// Load a SecIdentity from a PKCS12 file — cached and serialized to prevent concurrent
    /// SecPKCS12Import calls which crash inside the Security framework (_CFRuntimeCreateInstance).
    static func loadIdentity(from p12Path: String) -> SecIdentity? {
        // Fast path: return cached identity
        identityLock.lock()
        if let cached = identityCache[p12Path] {
            identityLock.unlock()
            return cached
        }
        identityLock.unlock()

        // Slow path: import under lock so only one thread calls SecPKCS12Import at a time
        identityLock.lock()
        defer { identityLock.unlock() }

        // Re-check after acquiring lock (another thread may have populated it)
        if let cached = identityCache[p12Path] { return cached }

        guard let p12Data = try? Data(contentsOf: URL(fileURLWithPath: p12Path)) else { return nil }
        var importedItems: CFArray?
        let options = [kSecImportExportPassphrase: "proxymock"] as CFDictionary
        let status = SecPKCS12Import(p12Data as CFData, options, &importedItems)
        guard status == errSecSuccess,
              let items = importedItems as? [[String: Any]],
              let firstItem = items.first,
              let identity = firstItem[kSecImportItemIdentity as String] else { return nil }
        let secIdentity = identity as! SecIdentity
        identityCache[p12Path] = secIdentity
        return secIdentity
    }

    static func shell(_ command: String) -> String {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", command]
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            process.waitUntilExit()
            return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        } catch {
            return "Error: \(error.localizedDescription)"
        }
    }
}
