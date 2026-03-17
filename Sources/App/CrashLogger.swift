import Foundation
import Darwin

/// A global crash logger to catch fatal errors and uncaught exceptions.
/// Writes to ~/Library/Logs/ProxyMock/crash.log
public final class CrashLogger: @unchecked Sendable {
    public static let shared = CrashLogger()
    private var isStarted = false
    
    private let libraryDir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first!
    private var logsDir: URL { libraryDir.appendingPathComponent("Logs/ProxyMock") }
    fileprivate var crashLogURL: URL { logsDir.appendingPathComponent("crash.log") }

    public func start() {
        guard !isStarted else { return }
        isStarted = true
        
        try? FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true, attributes: nil)
        
        NSSetUncaughtExceptionHandler { exception in
            CrashLogger.shared.handleException(exception)
        }
        print(crashLogURL.absoluteString)
        setupSignalHandlers()
    }
    
    private func setupSignalHandlers() {
        signal(SIGPIPE, SIG_IGN) // Prevent the app from crashing with exit code 13 when writing to closed sockets
        
        let signals: [Int32] = [SIGABRT, SIGILL, SIGSEGV, SIGFPE, SIGBUS, SIGTRAP]
        
        for sig in signals {
            var action = sigaction()
            memset(&action, 0, MemoryLayout<sigaction>.size)
            action.__sigaction_u.__sa_sigaction = globalSignalHandler
            action.sa_flags = SA_SIGINFO | SA_NODEFER | SA_RESETHAND
            sigemptyset(&action.sa_mask)
            
            var oldAction = sigaction()
            sigaction(sig, &action, &oldAction)
        }
    }
    
    fileprivate func handleException(_ exception: NSException) {
        let date = ISO8601DateFormatter().string(from: Date())
        var log = "=== ProxyMock Crash Log (Exception) ===\n"
        log += "Date: \(date)\n"
        log += "Name: \(exception.name.rawValue)\n"
        log += "Reason: \(exception.reason ?? "Unknown")\n"
        log += "Call Stack Symbols:\n"
        log += exception.callStackSymbols.joined(separator: "\n")
        log += "\n============================================\n\n"
        print(log)
        writeLog(log)
    }
    
    fileprivate func writeLog(_ text: String) {
        guard let data = text.data(using: .utf8) else { return }
        if FileManager.default.fileExists(atPath: crashLogURL.path) {
            if let fileHandle = try? FileHandle(forWritingTo: crashLogURL) {
                fileHandle.seekToEndOfFile()
                fileHandle.write(data)
                fileHandle.closeFile()
            }
        } else {
            try? data.write(to: crashLogURL, options: .atomic)
        }
    }
}

private func globalSignalHandler(signal: Int32, info: UnsafeMutablePointer<siginfo_t>?, context: UnsafeMutableRawPointer?) {
    let date = ISO8601DateFormatter().string(from: Date())
    var log = "=== ProxyMock Crash Log (Signal) ===\n"
    log += "Date: \(date)\n"
    log += "Signal: \(signal)\n"
    log += "Call Stack Symbols:\n"
    log += Thread.callStackSymbols.joined(separator: "\n")
    log += "\n============================================\n\n"
    
    CrashLogger.shared.writeLog(log)
    
    // We used SA_RESETHAND, so raising the signal again will trigger the default crash behavior
    raise(signal)
}
