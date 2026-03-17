import SwiftUI

struct ConnectDeviceView: View {
    @Environment(\.dismiss) private var dismiss
    let proxyPort: UInt16
    
    private let localIP = NetworkInfo.getLocalIPAddress()

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "iphone.gen1")
                    .font(.title2)
                    .foregroundStyle(.blue)
                Text("Connect Mobile Device")
                    .font(.title2.bold())
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(20)
            .background(.bar)
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    
                    // Connection Info
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Connection Details")
                            .font(.headline)
                        
                        HStack(spacing: 20) {
                            InfoBox(title: "Server (Local IP)", value: localIP)
                            InfoBox(title: "Port", value: "\(proxyPort)")
                        }
                        
                        Text("Ensure your mobile device is connected to the same Wi-Fi network as this Mac.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.top, 4)
                    }
                    
                    Divider()
                    
                    // Android Instructions
                    VStack(alignment: .leading, spacing: 16) {
                        Text("How to connect an Android Device:")
                            .font(.headline)
                        
                        InstructionStep(number: 1, title: "Configure Proxy", description: "Open Android Settings → Wi-Fi. Long-press your current network, select 'Modify network', expand 'Advanced options', set Proxy to Manual, and enter the IP and Port shown above.")
                        
                        InstructionStep(number: 2, title: "Download Root Certificate", description: "Open Chrome or any browser on your Android device and visit: \nhttp://\(localIP):\(proxyPort)/cert")
                            .contextMenu {
                                Button("Copy URL") {
                                    let pb = NSPasteboard.general
                                    pb.clearContents()
                                    pb.setString("http://\(localIP):\(proxyPort)/cert", forType: .string)
                                }
                            }
                        
                        InstructionStep(number: 3, title: "Trust Certificate", description: "Once the 'ProxyMock-Root-CA.crt' file downloads, open Android Settings → Security → Encryption & credentials → Install a certificate → CA certificate. Select the file and tap 'Install Anyway'.")
                            .padding(.bottom, 8)
                    }
                    
                    Divider()
                    
                    // iOS Instructions
                    VStack(alignment: .leading, spacing: 16) {
                        Text("How to connect an iOS Device:")
                            .font(.headline)
                        
                        InstructionStep(number: 1, title: "Configure Proxy", description: "Open iOS Settings → Wi-Fi. Tap the 'i' next to your network, scroll down to 'Configure Proxy', set to Manual, and enter the Server IP and Port shown above.")
                        
                        InstructionStep(number: 2, title: "Download Root Certificate", description: "Open Safari on your iOS device and visit: \nhttp://\(localIP):\(proxyPort)/cert")
                        
                        InstructionStep(number: 3, title: "Install Profile", description: "A prompt will ask to download a profile. Allow it, then open iOS Settings → Profile Downloaded → Install.")
                        
                        InstructionStep(number: 4, title: "Trust Certificate", description: "Open iOS Settings → General → About → Certificate Trust Settings. Toggle 'ProxyMock Root CA' to true.")
                    }
                }
                .padding(24)
            }
        }
        .frame(width: 550, height: 680)
    }
}

private struct InfoBox: View {
    let title: String
    let value: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.monospaced())
                .textSelection(.enabled)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
    }
}

private struct InstructionStep: View {
    let number: Int
    let title: String
    let description: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.headline)
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(Circle().fill(Color.blue))
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.bold())
                Text(description)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 2)
        }
    }
}
