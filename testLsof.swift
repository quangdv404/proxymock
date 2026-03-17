import Foundation

func getAppNameFromClientPort(_ port: UInt16) -> String? {
    let process = Process()
    let pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
    // Use `-iTCP -sTCP:ESTABLISHED -n -P` to make it faster
    process.arguments = ["-iTCP", "-sTCP:ESTABLISHED", "-n", "-P"]
    process.standardOutput = pipe
    process.standardError = Pipe()
    
    do {
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        
        guard let output = String(data: data, encoding: .utf8) else { return nil }
        
        // Find line matching our port
        let lines = output.components(separatedBy: .newlines)
        for line in lines {
            if line.contains(":" + String(port) + "->") {
                // Typical line:
                // Teams 1234 user 12u IPv4 0x123 0t0 TCP 127.0.0.1:51234->127.0.0.1:9090 (ESTABLISHED)
                let parts = line.split(separator: " ", omittingEmptySubsequences: true)
                if let appName = parts.first {
                    return String(appName)
                }
            }
        }
    } catch {
        print("Error:", error)
    }
    return nil
}

let start = Date()
let app = getAppNameFromClientPort(51234)
print("Time:", Date().timeIntervalSince(start))
print("App:", app ?? "nil")
