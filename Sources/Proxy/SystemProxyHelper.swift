import Foundation

/// Manages macOS system HTTP proxy settings via `networksetup`
/// This allows ProxyMock to intercept traffic from the iOS Simulator,
/// which shares the Mac's network stack.
struct SystemProxyHelper: Sendable {

    /// Get the active network service name (usually "Wi-Fi")
    static func activeNetworkService() -> String {
        // Try common service names
        let services = ["Wi-Fi", "Ethernet", "USB 10/100/1000 LAN"]
        for service in services {
            let result = shell("networksetup -getwebproxy \"\(service)\"")
            if !result.contains("** Error") {
                return service
            }
        }
        return "Wi-Fi" // fallback
    }

    /// Enable system HTTP proxy pointing to localhost on the given port
    static func enableProxy(port: UInt16) -> Bool {
        let service = activeNetworkService()
        let host = "127.0.0.1"

        // Set HTTP proxy
        let httpResult = shell("networksetup -setwebproxy \"\(service)\" \(host) \(port)")
        let httpOnResult = shell("networksetup -setwebproxystate \"\(service)\" on")

        // Set HTTPS proxy
        let httpsResult = shell("networksetup -setsecurewebproxy \"\(service)\" \(host) \(port)")
        let httpsOnResult = shell("networksetup -setsecurewebproxystate \"\(service)\" on")

        let success = !httpResult.contains("Error") && !httpsResult.contains("Error")

        if success {
            print("[SystemProxy] Enabled system proxy → \(host):\(port) on \(service)")
        } else {
            print("[SystemProxy] Failed to enable: HTTP=\(httpResult) HTTPS=\(httpsResult)")
            print("[SystemProxy] HTTP on=\(httpOnResult), HTTPS on=\(httpsOnResult)")
        }

        return success
    }

    /// Disable system HTTP proxy
    static func disableProxy() -> Bool {
        let service = activeNetworkService()

        let httpResult = shell("networksetup -setwebproxystate \"\(service)\" off")
        let httpsResult = shell("networksetup -setsecurewebproxystate \"\(service)\" off")

        let success = !httpResult.contains("Error") && !httpsResult.contains("Error")

        if success {
            print("[SystemProxy] Disabled system proxy on \(service)")
        } else {
            print("[SystemProxy] Failed to disable: HTTP=\(httpResult) HTTPS=\(httpsResult)")
        }

        return success
    }

    /// Check if system proxy is currently set to our port
    static func isProxyEnabled(port: UInt16) -> Bool {
        let service = activeNetworkService()
        let result = shell("networksetup -getwebproxy \"\(service)\"")
        return result.contains("Enabled: Yes") && result.contains("Port: \(port)")
    }

    // MARK: - Private

    private static func shell(_ command: String) -> String {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", command]
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        } catch {
            return "Error: \(error.localizedDescription)"
        }
    }
}
