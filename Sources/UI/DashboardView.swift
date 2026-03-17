import SwiftUI

struct DashboardView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("ProxyMock")
                            .font(.largeTitle.bold())
                        Text("API Proxy & Mock Server for iOS Development")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()

                    // Start/Stop button
                    Button {
                        if appState.isRunning {
                            appState.stopProxy()
                        } else {
                            appState.startProxy()
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: appState.isRunning ? "stop.fill" : "play.fill")
                            Text(appState.isRunning ? "Stop Proxy" : "Start Proxy")
                                .fontWeight(.semibold)
                        }
                        .frame(width: 140)
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(appState.isRunning ? .red : .green)
                    .controlSize(.large)

                    // System Proxy toggle
                    Button {
                        appState.toggleSystemProxy()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: appState.isSystemProxyEnabled ? "globe.badge.chevron.backward" : "globe")
                            Text(appState.isSystemProxyEnabled ? "Proxy On" : "System Proxy")
                                .fontWeight(.medium)
                        }
                        .padding(.vertical, 10)
                        .padding(.horizontal, 12)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(appState.isSystemProxyEnabled ? .purple : .secondary)
                    .controlSize(.large)
                    .disabled(!appState.isRunning)
                    .help("Route all Mac + iOS Simulator traffic through ProxyMock")
                }
                .padding(.horizontal)

                // Stats cards
                HStack(spacing: 16) {
                    StatCard(
                        title: "Status",
                        value: appState.isRunning ? "Running" : "Stopped",
                        icon: "antenna.radiowaves.left.and.right",
                        color: appState.isRunning ? .green : .gray,
                        subtitle: "Port \(appState.port)"
                    )

                    StatCard(
                        title: "Total Requests",
                        value: "\(appState.totalRequests)",
                        icon: "arrow.up.arrow.down.circle",
                        color: .blue,
                        subtitle: "\(appState.proxyServer.connectionCount) connections"
                    )

                    StatCard(
                        title: "Mocked",
                        value: "\(appState.mockedRequests)",
                        icon: "doc.text.magnifyingglass",
                        color: .orange,
                        subtitle: "\(appState.mockEngine.enabledRuleCount) rules active"
                    )

                    StatCard(
                        title: "System Proxy",
                        value: appState.isSystemProxyEnabled ? "Active" : "Off",
                        icon: appState.isSystemProxyEnabled ? "checkmark.shield.fill" : "shield.slash",
                        color: appState.isSystemProxyEnabled ? .purple : .gray,
                        subtitle: appState.isSystemProxyEnabled ? "Simulator + Mac traffic" : "Tap to enable"
                    )
                }
                .padding(.horizontal)

                // iOS Simulator Setup
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("iOS Simulator", systemImage: "iphone.gen3")
                            .font(.headline)

                        VStack(alignment: .leading, spacing: 8) {
                            SetupStep(number: 1, text: "Start the proxy (click Start Proxy above)")
                            SetupStep(number: 2, text: "Click \"System Proxy\" to route Mac traffic through ProxyMock")
                            SetupStep(number: 3, text: "Run your app in the iOS Simulator — all network calls will appear in the Logs tab")
                            SetupStep(number: 4, text: "When done, click System Proxy again to disable, or stop the proxy (auto-disables)")
                        }

                        if appState.isSystemProxyEnabled {
                            HStack(spacing: 6) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                Text("System proxy is active — Simulator traffic is being captured")
                                    .font(.callout.bold())
                                    .foregroundStyle(.green)
                            }
                            .padding(8)
                            .background(.green.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                    .padding(8)
                }
                .padding(.horizontal)

                // iOS Device Setup guide
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Physical iOS Device", systemImage: "iphone")
                            .font(.headline)

                        VStack(alignment: .leading, spacing: 8) {
                            SetupStep(number: 1, text: "Connect your iOS device to the same Wi-Fi network as this Mac")
                            SetupStep(number: 2, text: "Go to Settings → Wi-Fi → tap the (i) icon on your network")
                            SetupStep(number: 3, text: "Scroll down and tap \"Configure Proxy\" → select \"Manual\"")
                            SetupStep(number: 4, text: "Set Server to \(appState.localIPAddress)")
                            SetupStep(number: 5, text: "Set Port to \(appState.port)")
                            SetupStep(number: 6, text: "Tap Save — all HTTP traffic will now flow through ProxyMock")
                        }
                    }
                    .padding(8)
                }
                .padding(.horizontal)

                // Recent logs preview
                if !appState.logs.isEmpty {
                    GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Label("Recent Activity", systemImage: "clock")
                                    .font(.headline)
                                Spacer()
                                Button("View All") {
                                    appState.selectedSidebarItem = .logs
                                }
                                .buttonStyle(.link)
                            }

                            ForEach(appState.logs.prefix(5)) { log in
                                HStack(spacing: 12) {
                                    Text(log.method)
                                        .font(.caption.monospaced().bold())
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(methodColor(log.method))
                                        .clipShape(RoundedRectangle(cornerRadius: 4))

                                    Text(log.url)
                                        .font(.caption.monospaced())
                                        .lineLimit(1)
                                        .truncationMode(.middle)

                                    Spacer()

                                    if let statusCode = log.responseStatusCode {
                                        Text("\(statusCode)")
                                            .font(.caption.monospaced())
                                            .foregroundStyle(statusColor(statusCode))
                                    }

                                    if log.isMocked {
                                        Text("MOCK")
                                            .font(.caption2.bold())
                                            .foregroundStyle(.orange)
                                            .padding(.horizontal, 4)
                                            .padding(.vertical, 1)
                                            .background(.orange.opacity(0.15))
                                            .clipShape(RoundedRectangle(cornerRadius: 3))
                                    }

                                    Text(String(format: "%.0fms", log.duration * 1000))
                                        .font(.caption.monospaced())
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 2)
                            }
                        }
                        .padding(8)
                    }
                    .padding(.horizontal)
                }

                Spacer()
            }
            .padding(.vertical)
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .alert(
            "Proxy Failed to Start",
            isPresented: Bindable(appState).showProxyError
        ) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(appState.proxyErrorMessage)
        }
    }

    private func methodColor(_ method: String) -> Color {
        switch method.uppercased() {
        case "GET": return .blue
        case "POST": return .green
        case "PUT": return .orange
        case "DELETE": return .red
        case "PATCH": return .purple
        case "CONNECT": return .gray
        default: return .gray
        }
    }

    private func statusColor(_ code: Int) -> Color {
        switch code {
        case 200..<300: return .green
        case 300..<400: return .orange
        case 400..<500: return .red
        case 500...: return .red
        default: return .secondary
        }
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(color)
                Spacer()
            }
            Text(value)
                .font(.title2.bold().monospaced())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(title)
                .font(.subheadline.weight(.medium))
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.05), radius: 2, y: 1)
    }
}

struct SetupStep: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)")
                .font(.caption.bold())
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Circle().fill(.blue))
            Text(text)
                .font(.callout)
        }
    }
}
