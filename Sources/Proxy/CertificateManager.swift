import Foundation
import Security

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
        print("[CertMgr] CA generated: \(isCAGenerated)")
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
    static var baseDir: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("ProxyMock/Certs", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static var hostsDir: URL {
        let dir = baseDir.appendingPathComponent("hosts", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static var caKeyPath: String { baseDir.appendingPathComponent("ca-key.pem").path }
    static var caCertPath: String { baseDir.appendingPathComponent("ca.pem").path }
    static var caCertDERPath: String { baseDir.appendingPathComponent("ca.cer").path }
    static var caCertURL: URL { baseDir.appendingPathComponent("ca.pem") }
    static var caCertDERURL: URL { baseDir.appendingPathComponent("ca.cer") }

    /// Get or generate a PKCS12 certificate for a hostname (thread-safe)
    static func getP12Path(for host: String) -> String? {
        let hostDir = hostsDir.appendingPathComponent(host)
        let p12Path = hostDir.appendingPathComponent("cert.p12").path
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
            print("[CertMgr] Generated cert for \(host)")
            return p12Path
        }
        print("[CertMgr] ❌ Failed to generate cert for \(host)")
        return nil
    }

    /// Load a SecIdentity from a PKCS12 file
    static func loadIdentity(from p12Path: String) -> SecIdentity? {
        guard let p12Data = try? Data(contentsOf: URL(fileURLWithPath: p12Path)) else { return nil }
        var importedItems: CFArray?
        let options = [kSecImportExportPassphrase: "proxymock"] as CFDictionary
        let status = SecPKCS12Import(p12Data as CFData, options, &importedItems)
        guard status == errSecSuccess,
              let items = importedItems as? [[String: Any]],
              let firstItem = items.first,
              let identity = firstItem[kSecImportItemIdentity as String] else { return nil }
        return (identity as! SecIdentity)
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
