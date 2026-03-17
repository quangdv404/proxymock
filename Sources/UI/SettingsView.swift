import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var portString: String = ""
    @State private var showRestartAlert = false

    var body: some View {
        @Bindable var state = appState

        Form {
            Section("Proxy Configuration") {
                HStack {
                    Text("Port")
                    TextField("Port", text: $portString)
                        .font(.body.monospaced())
                        .frame(width: 100)
                        .onAppear { portString = "\(appState.port)" }
                    Button("Apply") {
                        if let newPort = UInt16(portString) {
                            appState.port = newPort
                            if appState.isRunning {
                                showRestartAlert = true
                            }
                        }
                    }
                    .disabled(UInt16(portString) == nil || UInt16(portString) == appState.port)
                }

                LabeledContent("Status") {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(appState.isRunning ? Color.green : Color.red.opacity(0.6))
                            .frame(width: 8, height: 8)
                        Text(appState.isRunning ? "Running on port \(appState.port)" : "Stopped")
                            .font(.callout)
                    }
                }
            }

            Section("SSL Proxying (HTTPS Decryption)") {
                VStack(alignment: .leading, spacing: 12) {
                    // Status indicators
                    HStack(spacing: 12) {
                        StatusIndicator(
                            label: "CA Certificate",
                            isOK: appState.certManager.isCAGenerated,
                            okText: "Generated",
                            failText: "Not Generated"
                        )
                        StatusIndicator(
                            label: "Trusted",
                            isOK: appState.certManager.isCAInstalled,
                            okText: "Installed & Trusted",
                            failText: "Not Installed"
                        )
                    }

                    // Action buttons
                    HStack(spacing: 12) {
                        if !appState.certManager.isCAGenerated {
                            Button("Generate Root CA") {
                                _ = appState.certManager.generateCA()
                            }
                            .buttonStyle(.borderedProminent)
                        }

                        if appState.certManager.isCAGenerated && !appState.certManager.isCAInstalled {
                            Button("Install & Trust CA") {
                                _ = appState.certManager.installCA()
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.orange)
                        }

                        if appState.certManager.isCAGenerated && appState.certManager.isCAInstalled {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundStyle(.green)
                                .font(.title2)
                            Text("Ready for HTTPS interception!")
                                .font(.callout.bold())
                                .foregroundStyle(.green)
                        }
                    }

                    // MITM Toggle
                    Toggle("Enable SSL Proxying", isOn: Binding(
                        get: { appState.mitmEnabled },
                        set: { appState.setMITM($0) }
                    ))
                        .disabled(!appState.certManager.isCAGenerated || !appState.certManager.isCAInstalled)

                    Text("When enabled, HTTPS traffic is decrypted using the trusted CA certificate so you can inspect request/response bodies. The CA must be generated and trusted first.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            Section("System Proxy (Mac + Simulator)") {
                Toggle("Enable System Proxy", isOn: Binding(
                    get: { appState.isSystemProxyEnabled },
                    set: { newValue in
                        if newValue { appState.enableSystemProxy() } else { appState.disableSystemProxy() }
                    }
                ))
                .disabled(!appState.isRunning)

                Text("Routes all Mac traffic (including iOS Simulator) through ProxyMock. Auto-disabled when proxy stops.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Network Info") {
                LabeledContent("Local IP Address") {
                    HStack {
                        Text(appState.localIPAddress)
                            .font(.callout.monospaced())
                            .textSelection(.enabled)
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(appState.localIPAddress, forType: .string)
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                        .buttonStyle(.plain)
                        .help("Copy to clipboard")
                    }
                }

                LabeledContent("Proxy URL") {
                    let proxyURL = "\(appState.localIPAddress):\(appState.port)"
                    HStack {
                        Text(proxyURL)
                            .font(.callout.monospaced())
                            .textSelection(.enabled)
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(proxyURL, forType: .string)
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                        .buttonStyle(.plain)
                        .help("Copy to clipboard")
                    }
                }
            }

            Section("iOS Device Setup Instructions") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("To route your iOS device traffic through ProxyMock:")
                        .font(.callout.bold())

                    Group {
                        Text("1. Ensure both this Mac and your iOS device are on the **same Wi-Fi network**")
                        Text("2. On your iOS device, go to **Settings → Wi-Fi**")
                        Text("3. Tap the **(i)** button next to your connected network")
                        Text("4. Scroll down and tap **Configure Proxy → Manual**")
                        Text("5. Set **Server** to: `\(appState.localIPAddress)`")
                        Text("6. Set **Port** to: `\(appState.port)`")
                        Text("7. Tap **Save**")
                    }
                    .font(.callout)
                }
                .padding(.vertical, 4)
            }

            Section("Data Management") {
                HStack {
                    Button("Clear All Logs") {
                        appState.clearLogs()
                    }
                    .foregroundStyle(.red)

                    Text("(\(appState.logs.count) entries)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Button("Export Rules") {
                        exportRules()
                    }
                    Button("Import Rules") {
                        importRules()
                    }
                }
            }

            Section("About") {
                LabeledContent("Version") { Text("1.0.0") }
                LabeledContent("Build") { Text("Swift 6.2, macOS 15+") }
                LabeledContent("") {
                    Text("ProxyMock — API Proxy Mocking for iOS Development")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .alert("Restart Proxy?", isPresented: $showRestartAlert) {
            Button("Restart") {
                do {
                    try appState.proxyServer.restart(port: appState.port)
                } catch {
                    print("Failed to restart: \(error)")
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The proxy is currently running. Would you like to restart it on port \(appState.port)?")
        }
    }

    private func exportRules() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "proxy_mock_rules.json"
        panel.begin { response in
            if response == .OK, let url = panel.url {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                if let data = try? encoder.encode(appState.mockEngine.allRules) {
                    try? data.write(to: url, options: .atomic)
                }
            }
        }
    }

    private func importRules() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.begin { response in
            if response == .OK, let url = panel.url {
                if let data = try? Data(contentsOf: url),
                   let rules = try? JSONDecoder().decode([MockRule].self, from: data) {
                    for rule in rules {
                        appState.mockEngine.addRule(rule)
                    }
                    appState.saveRules()
                }
            }
        }
    }
}
