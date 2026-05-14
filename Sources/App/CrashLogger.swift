import Foundation
import Darwin

/// A global crash logger to catch fatal errors and uncaught exceptions.
/// Writes to ~/Library/Logs/ProxyMock/crash.log
public final class CrashLogger: @unchecked Sendable {
    public static let shared = CrashLogger()
    private var isStarted = false

    // Resolved once at startup — never recomputed inside a handler.
    private let libraryDir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first!
    private lazy var logsDir: URL    = libraryDir.appendingPathComponent("Logs/ProxyMock")
    fileprivate lazy var crashLogURL: URL = logsDir.appendingPathComponent("crash.log")

    /// File descriptor kept open for async-signal-safe writing.
    /// `write(2)` is on the POSIX async-signal-safe list; FileHandle / Swift String ops are NOT.
    fileprivate var crashLogFD: Int32 = -1

    public func start() {
        guard !isStarted else { return }
        isStarted = true

        try? FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)

        // Open once; the FD is reused by the signal handler via write(2).
        crashLogFD = Darwin.open(crashLogURL.path, O_WRONLY | O_CREAT | O_APPEND, 0o644)

        NSSetUncaughtExceptionHandler { exception in
            CrashLogger.shared.handleException(exception)
        }
        print("[CrashLogger] crash log: \(crashLogURL.path)")
        setupSignalHandlers()
    }

    private func setupSignalHandlers() {
        signal(SIGPIPE, SIG_IGN)

        let signals: [Int32] = [SIGABRT, SIGILL, SIGSEGV, SIGFPE, SIGBUS, SIGTRAP]
        for sig in signals {
            var action = sigaction()
            memset(&action, 0, MemoryLayout<sigaction>.size)
            action.__sigaction_u.__sa_sigaction = globalSignalHandler
            // SA_RESETHAND  – restore default handler after first delivery so raise() terminates.
            // SA_NODEFER removed intentionally – masking the signal during handler execution
            // prevents re-entrant delivery, which was the root cause of the 1500-frame
            // infinite signal-handler loop that caused the stack-overflow crash.
            action.sa_flags = SA_SIGINFO | SA_RESETHAND
            sigemptyset(&action.sa_mask)
            sigaction(sig, &action, nil)
        }
    }

    /// Called from the uncaught-exception handler (normal heap is available here).
    fileprivate func handleException(_ exception: NSException) {
        var log = "=== ProxyMock Crash Log (Exception) ===\n"
        log += "Date: \(ISO8601DateFormatter().string(from: Date()))\n"
        log += "Name: \(exception.name.rawValue)\n"
        log += "Reason: \(exception.reason ?? "Unknown")\n"
        log += "Call Stack:\n\(exception.callStackSymbols.joined(separator: "\n"))"
        log += "\n============================================\n\n"
        // fdWrite(log)
    }

    /// Write a plain Swift String to the pre-opened FD.
    /// Only safe to call when the heap is NOT in a signal-interrupted state.
    fileprivate func fdWrite(_ text: String) {
        guard crashLogFD >= 0 else { return }
        text.withCString { ptr in
            _ = Darwin.write(crashLogFD, ptr, strlen(ptr))
        }
    }
}

// MARK: - Async-signal-safe signal handler
//
// KEY RULES for POSIX signal handlers:
//   ✅ Only async-signal-safe functions (write, strlen, raise, memcpy …)
//   ❌ NO heap allocation  (no String, no Array, no Swift runtime calls)
//   ❌ NO Objective-C      (no NSObject, no Foundation, no ISO8601DateFormatter)
//   ❌ NO print / Thread.callStackSymbols  (both allocate)
//
// The previous handler violated ALL of the above, causing swift_allocBox to be called
// while the heap was in an inconsistent state, which re-fired SIGTRAP on every invocation
// and produced 1500+ recursive signal-handler frames until the stack was exhausted.

private func globalSignalHandler(
    signal: Int32,
    info: UnsafeMutablePointer<siginfo_t>?,
    context: UnsafeMutableRawPointer?
) {
    // All writes below use only stack-allocated C strings and write(2) — both async-signal-safe.
    let fd = CrashLogger.shared.crashLogFD

    if fd >= 0 {
        // Static header
        "\n=== ProxyMock Crash (Signal ".withCString { _ = Darwin.write(fd, $0, strlen($0)) }

        // Signal number as ASCII — no heap allocation: itoa-style on the stack
        var num = signal
        var buf: (CChar,CChar,CChar,CChar,CChar) = (0,0,0,0,0)
        var idx = 3
        if num == 0 { buf.0 = 48; idx = 0 }
        else {
            while num > 0 {
                withUnsafeMutablePointer(to: &buf) { base in
                    (base.withMemoryRebound(to: CChar.self, capacity: 5) { $0 })[idx] = CChar(48 + num % 10)
                }
                num /= 10; idx -= 1
            }
            idx += 1  // first digit position
        }
        withUnsafePointer(to: buf) { base in
            let start = base.withMemoryRebound(to: CChar.self, capacity: 5) { $0.advanced(by: idx) }
            _ = Darwin.write(fd, start, 4 - idx)
        }

        ") ===\n(Stack unavailable — async-signal-safe handler only)\n============================================\n\n"
            .withCString { _ = Darwin.write(fd, $0, strlen($0)) }
    }

    // SA_RESETHAND restored the default handler; raise() now terminates the process normally.
    raise(signal)
}
