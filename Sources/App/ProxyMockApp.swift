import SwiftUI

@main
struct ProxyMockApp: App {
    @State private var appState = AppState()
    #if os(macOS)
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    #endif

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .frame(minWidth: 900, minHeight: 600)
                .onAppear {
                    CrashLogger.shared.start()
                    // Give the app delegate a reference to the app state so it can clean up
                    #if os(macOS)
                    appDelegate.appState = appState
                    #endif
                }
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1100, height: 700)
    }
}

#if os(macOS)
class AppDelegate: NSObject, NSApplicationDelegate {
    var appState: AppState?

    func applicationWillTerminate(_ notification: Notification) {
        // Ensure we don't leave the system proxy pointing to a dead server
        if let state = appState, state.isSystemProxyEnabled {
            print("[App] Terminating: Disabling system proxy...")
            state.disableSystemProxy()
        } else {
            // Fallback safety in case appState wasn't wired up
            print("[App] Terminating: Forcing system proxy off...")
            _ = SystemProxyHelper.disableProxy()
        }
    }
}
#endif
