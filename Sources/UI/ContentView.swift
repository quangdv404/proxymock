import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var appState
    @State private var showConnectDevice = false

    var body: some View {
        @Bindable var state = appState

        NavigationSplitView {
            VStack(spacing: 0) {
                List(AppState.SidebarItem.allCases, selection: $state.selectedSidebarItem) { item in
                    Label(item.rawValue, systemImage: item.icon)
                        .tag(item)
                }
                .listStyle(.sidebar)

                Divider()

                // Connect Device Button
                Button {
                    showConnectDevice = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "iphone.gen1")
                        Text("Connect Device...")
                        Spacer()
                    }
                    .font(.caption)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.blue)
                
                // Proxy status badge
                HStack(spacing: 8) {
                    Circle()
                        .fill(appState.isRunning ? Color.green : Color.red.opacity(0.6))
                        .frame(width: 10, height: 10)
                        .shadow(color: appState.isRunning ? .green.opacity(0.6) : .clear, radius: 4)
                    Text(appState.isRunning ? "Proxy Active" : "Proxy Off")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(":\(appState.port)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 210, max: 260)
        } detail: {
            switch appState.selectedSidebarItem {
            case .dashboard:
                DashboardView()
            case .logs:
                LogListView()
            case .mockRules:
                MockRulesView()
            case .breakpoints:
                BreakpointsView()
            case .mapLocal:
                MapLocalView()
            case .mapRemote:
                MapRemoteView()
            case .domainFilter:
                DomainFilterView()
            case .throttle:
                ThrottleView()
            case .compose:
                ComposeView()
            case .settings:
                SettingsView()
            }
        }
        // Breakpoint editor overlay
        .sheet(isPresented: Binding(
            get: { appState.breakpointManager.hasPending },
            set: { if !$0 { appState.breakpointManager.drop() } }
        )) {
            if let edit = appState.breakpointManager.pendingEdit {
                BreakpointEditorView(edit: edit)
            }
        }
        .sheet(isPresented: $showConnectDevice) {
            ConnectDeviceView(proxyPort: appState.port)
        }
    }
}
