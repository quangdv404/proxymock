import SwiftUI

struct ThrottleView: View {
    @Environment(AppState.self) private var appState
    @State private var customLatency: Int = 200
    @State private var customBandwidth: Int = 1000

    var body: some View {
        @Bindable var state = appState

        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("Network Throttle").font(.headline)
                Spacer()
                Toggle("Enabled", isOn: $state.isThrottleEnabled).toggleStyle(.switch)
            }
            .padding(12).background(.bar)
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Status
                    HStack(spacing: 8) {
                        Image(systemName: appState.isThrottleEnabled ? "speedometer" : "speedometer")
                            .font(.title2)
                            .foregroundStyle(appState.isThrottleEnabled ? .orange : .secondary)
                        if appState.isThrottleEnabled {
                            VStack(alignment: .leading) {
                                Text("Throttle Active: \(appState.throttleProfile.name)")
                                    .font(.callout.bold()).foregroundStyle(.orange)
                                Text("Latency: \(appState.throttleProfile.latencyMs)ms, Bandwidth: \(formatBandwidth(appState.throttleProfile.bandwidthKbps))")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        } else {
                            Text("Throttling disabled — network at full speed")
                                .font(.callout).foregroundStyle(.secondary)
                        }
                    }
                    .padding(12).background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                    Divider()

                    // Presets
                    SectionHeader(title: "Presets", icon: "list.bullet")
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 200))], spacing: 12) {
                        ForEach(ThrottleProfile.presets) { profile in
                            Button {
                                appState.throttleProfile = profile
                            } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Text(profile.name).font(.callout.bold())
                                        Spacer()
                                        if appState.throttleProfile.id == profile.id {
                                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                                        }
                                    }
                                    HStack(spacing: 16) {
                                        Label("\(profile.latencyMs)ms", systemImage: "clock")
                                            .font(.caption).foregroundStyle(.secondary)
                                        Label(formatBandwidth(profile.bandwidthKbps), systemImage: "arrow.down.circle")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                .padding(12)
                                .background(appState.throttleProfile.id == profile.id ? Color.accentColor.opacity(0.1) : Color(nsColor: .controlBackgroundColor))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(appState.throttleProfile.id == profile.id ? Color.accentColor : Color.gray.opacity(0.2), lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Divider()

                    // Custom settings
                    SectionHeader(title: "Custom Profile", icon: "slider.horizontal.3")
                    VStack(alignment: .leading, spacing: 12) {
                        LabeledField(label: "Added Latency (ms)") {
                            HStack {
                                Slider(value: Binding(
                                    get: { Double(customLatency) },
                                    set: { customLatency = Int($0) }
                                ), in: 0...5000, step: 50)
                                Text("\(customLatency)ms").font(.callout.monospaced()).frame(width: 65)
                            }
                        }
                        LabeledField(label: "Bandwidth Limit (kbps)") {
                            HStack {
                                Slider(value: Binding(
                                    get: { Double(customBandwidth) },
                                    set: { customBandwidth = Int($0) }
                                ), in: 0...50000, step: 100)
                                Text(formatBandwidth(customBandwidth)).font(.callout.monospaced()).frame(width: 80)
                            }
                        }
                        Button("Apply Custom") {
                            appState.throttleProfile = ThrottleProfile(name: "Custom", latencyMs: customLatency, bandwidthKbps: customBandwidth)
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(12).background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .padding(20)
            }
        }
    }

    func formatBandwidth(_ kbps: Int) -> String {
        if kbps == 0 { return "∞" }
        if kbps >= 1000 { return String(format: "%.1f Mbps", Double(kbps) / 1000.0) }
        return "\(kbps) kbps"
    }
}
