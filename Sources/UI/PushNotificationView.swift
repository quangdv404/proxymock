import SwiftUI
import UniformTypeIdentifiers

// Default template shown in the JSON editor
private let defaultPayload = "{\n  \"title\": \"\",\n  \"body\": \"\"\n}"

struct PushNotificationView: View {
    @Environment(AppState.self) private var appState
    @State private var selectedTab: PushPlatform = .apns

    var body: some View {
        VStack(spacing: 0) {
            Picker("Platform", selection: $selectedTab) {
                ForEach(PushPlatform.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding()

            Divider()

            ScrollView {
                if selectedTab == .apns {
                    APNsComposerView(engine: appState.pushEngine)
                } else {
                    FCMComposerView(engine: appState.pushEngine)
                }
            }
        }
        .navigationTitle("Push Notifications")
    }
}

// MARK: - APNs

struct APNsComposerView: View {
    var engine: PushNotificationEngine
    @State private var deviceToken = ""
    @State private var payloadJSON = defaultPayload
    @State private var showFilePicker = false
    @State private var p12FileName: String = ""
    @State private var jsonError: String? = nil
    @State private var savedPayloads: [PushCredentialStore.SavedPayload] = []
    @State private var showSavePrompt = false
    @State private var saveName = ""

    var body: some View {
        @Bindable var eng = engine
        Form {
            // ----- Credentials -----
            Section("Credentials") {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("P12 Certificate").font(.caption).foregroundStyle(.secondary)
                        HStack(spacing: 6) {
                            Image(systemName: "lock.doc.fill")
                                .foregroundColor(eng.apnsCredential.p12Base64.isEmpty ? Color.secondary : Color.blue)
                            Text(p12FileName.isEmpty ? "No file loaded" : p12FileName)
                                .font(.body)
                                .foregroundStyle(p12FileName.isEmpty ? .secondary : .primary)
                        }
                    }
                    Spacer()
                    Button("Load .p12…") { showFilePicker = true }
                        .fileImporter(
                            isPresented: $showFilePicker,
                            allowedContentTypes: [
                                .init(filenameExtension: "p12") ?? .data,
                                .init(filenameExtension: "pfx") ?? .data
                            ]
                        ) { result in
                            if let url = try? result.get(), let data = try? Data(contentsOf: url) {
                                engine.apnsCredential.p12Base64 = data.base64EncodedString()
                                p12FileName = url.lastPathComponent
                                PushCredentialStore.saveAPNs(engine.apnsCredential)
                            }
                        }
                }

                SecureField("P12 Password (leave empty if none)", text: $eng.apnsCredential.p12Password)
                    .font(.body.monospaced())
                    .onChange(of: eng.apnsCredential.p12Password) { _, _ in
                        PushCredentialStore.saveAPNs(engine.apnsCredential)
                    }

                TextField("Bundle ID  (e.g. com.yourapp.ios)", text: $eng.apnsCredential.bundleID)
                    .font(.body.monospaced())
                    .onChange(of: eng.apnsCredential.bundleID) { _, _ in
                        PushCredentialStore.saveAPNs(engine.apnsCredential)
                    }

                Picker("Environment", selection: $eng.apnsCredential.environment) {
                    ForEach(APNsEnvironment.allCases, id: \.self) { Text($0.rawValue) }
                }
                .onChange(of: eng.apnsCredential.environment) { _, _ in
                    PushCredentialStore.saveAPNs(engine.apnsCredential)
                }

                Button("Save Credentials") {
                    PushCredentialStore.saveAPNs(engine.apnsCredential)
                }
            }

            // ----- Message -----
            Section("Message") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Device Tokens (comma or newline separated)").font(.caption).foregroundStyle(.secondary)
                    TextEditor(text: $deviceToken)
                        .font(.caption.monospaced())
                        .frame(minHeight: 60, maxHeight: 120)
                        .scrollContentBackground(.hidden)
                        .background(Color(.textBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(.separatorColor)))
                        .onChange(of: deviceToken) { _, _ in saveMessageCache() }
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Payload JSON").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("Save") { showSavePrompt = true }
                            .font(.caption).buttonStyle(.plain).foregroundStyle(.green)
                        Button("Reset") { payloadJSON = defaultPayload }
                            .font(.caption).buttonStyle(.plain).foregroundStyle(.secondary)
                    }
                    PrettyJSONView(text: $payloadJSON, minHeight: 200)
                        .onChange(of: payloadJSON) { _, _ in
                            validateJSON()
                            saveMessageCache()
                        }
                    Text("Payload is sent verbatim to APNs. Must be valid JSON.")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }

            // ----- Send -----
            Section {
                HStack {
                    Button(action: send) {
                        Label(engine.isSending ? "Sending…" : "Send to iOS", systemImage: "paperplane.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(engine.isSending || deviceToken.isEmpty
                              || engine.apnsCredential.p12Base64.isEmpty
                              || jsonError != nil)

                    if let err = engine.lastError {
                        Text(err).font(.caption).foregroundStyle(.red).lineLimit(2)
                    }
                }
            }

            // ----- Saved Payloads -----
            if !savedPayloads.isEmpty {
                Section {
                    SavedPayloadPanel(payloads: $savedPayloads, onSelect: { p in
                        payloadJSON = p.json
                    })
                } header: {
                    Text("Saved Payloads")
                }
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showSavePrompt) {
            VStack(spacing: 16) {
                Text("Save Payload").font(.headline)
                TextField("Name (optional)", text: $saveName)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Button("Cancel") { showSavePrompt = false }
                    Spacer()
                    Button("Save") {
                        let name = saveName.trimmingCharacters(in: .whitespaces)
                        let autoName = name.isEmpty ? (titleFromJSON(payloadJSON) ?? "Payload \(Date().formatted(.dateTime.hour().minute().second()))") : name
                        let p = PushCredentialStore.SavedPayload(
                            name: autoName, json: payloadJSON, savedAt: Date(), isAutoSaved: false)
                        PushCredentialStore.addPayload(p)
                        savedPayloads = PushCredentialStore.loadSavedPayloads()
                        saveName = ""
                        showSavePrompt = false
                    }.buttonStyle(.borderedProminent)
                }
            }
            .padding()
            .frame(width: 320)
        }
        .onAppear {
            engine.apnsCredential = PushCredentialStore.loadAPNs()
            let cached = PushCredentialStore.loadAPNsMessage()
            deviceToken = cached.deviceToken
            payloadJSON = cached.payloadJSON.isEmpty ? defaultPayload : cached.payloadJSON
            savedPayloads = PushCredentialStore.loadSavedPayloads()
            validateJSON()
        }
    }

    private func validateJSON() {
        guard let data = payloadJSON.data(using: .utf8),
              (try? JSONSerialization.jsonObject(with: data)) != nil else {
            jsonError = "Invalid JSON"
            return
        }
        jsonError = nil
    }

    private func saveMessageCache() {
        PushCredentialStore.saveAPNsMessage(.init(deviceToken: deviceToken, payloadJSON: payloadJSON))
    }



    private func send() {
        guard !payloadJSON.trimmingCharacters(in: .whitespaces).isEmpty else {
            engine.lastError = "Payload JSON is empty"
            return
        }
        
        let tokens = deviceToken
            .components(separatedBy: CharacterSet(charactersIn: ",\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            
        guard !tokens.isEmpty else {
            engine.lastError = "Provide at least one device token"
            return
        }
        
        Task { await engine.sendAPNs(deviceTokens: tokens, payloadJSON: payloadJSON) }
    }

    private func titleFromJSON(_ json: String) -> String? {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return obj["title"] as? String
            ?? (obj["aps"] as? [String: Any]).flatMap { ($0["alert"] as? [String: Any])?["title"] as? String }
    }
}

// MARK: - FCM

struct FCMComposerView: View {
    var engine: PushNotificationEngine
    @State private var deviceToken = ""
    @State private var payloadJSON = defaultPayload
    @State private var showFilePicker = false
    @State private var jsonError: String? = nil
    @State private var savedPayloads: [PushCredentialStore.SavedPayload] = []
    @State private var showSavePrompt = false
    @State private var saveName = ""

    var body: some View {
        @Bindable var eng = engine
        Form {
            // ----- Credentials -----
            Section("Credentials") {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Service Account JSON").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("Load File") { showFilePicker = true }
                            .fileImporter(isPresented: $showFilePicker, allowedContentTypes: [.json]) { result in
                                if let url = try? result.get(), let text = try? String(contentsOf: url) {
                                    engine.fcmCredential.serviceAccountJSON = text
                                    PushCredentialStore.saveFCM(engine.fcmCredential)
                                }
                            }
                    }
                    TextEditor(text: $eng.fcmCredential.serviceAccountJSON)
                        .font(.caption.monospaced())
                        .frame(minHeight: 90, maxHeight: 130)
                        .scrollContentBackground(.hidden)
                        .background(Color(.textBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(.separatorColor)))
                        .onChange(of: eng.fcmCredential.serviceAccountJSON) { _, _ in
                            PushCredentialStore.saveFCM(engine.fcmCredential)
                        }
                }
                Button("Save Credentials") {
                    PushCredentialStore.saveFCM(engine.fcmCredential)
                }
            }

            // ----- Message -----
            Section("Message") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("FCM Device Tokens (comma or newline separated)").font(.caption).foregroundStyle(.secondary)
                    TextEditor(text: $deviceToken)
                        .font(.caption.monospaced())
                        .frame(minHeight: 60, maxHeight: 120)
                        .scrollContentBackground(.hidden)
                        .background(Color(.textBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(.separatorColor)))
                        .onChange(of: deviceToken) { _, _ in saveMessageCache() }
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Payload JSON").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("Save") { showSavePrompt = true }
                            .font(.caption).buttonStyle(.plain).foregroundStyle(.green)
                        Button("Reset") { payloadJSON = defaultPayload }
                            .font(.caption).buttonStyle(.plain).foregroundStyle(.secondary)
                    }
                    PrettyJSONView(text: $payloadJSON, minHeight: 200)
                        .onChange(of: payloadJSON) { _, _ in
                            validateJSON()
                            saveMessageCache()
                        }
                    Text("Payload is sent verbatim to FCM. Must be valid JSON.")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }

            // ----- Send -----
            Section {
                HStack {
                    Button(action: send) {
                        Label(engine.isSending ? "Sending…" : "Send to Android", systemImage: "paperplane.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .disabled(engine.isSending || deviceToken.isEmpty
                              || engine.fcmCredential.serviceAccountJSON.isEmpty
                              || jsonError != nil)

                    if let err = engine.lastError {
                        Text(err).font(.caption).foregroundStyle(.red).lineLimit(2)
                    }
                }
            }

            // ----- Saved Payloads -----
            if !savedPayloads.isEmpty {
                Section {
                    SavedPayloadPanel(payloads: $savedPayloads, onSelect: { p in
                        payloadJSON = p.json
                    })
                } header: {
                    Text("Saved Payloads")
                }
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showSavePrompt) {
            VStack(spacing: 16) {
                Text("Save Payload").font(.headline)
                TextField("Name (optional)", text: $saveName)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Button("Cancel") { showSavePrompt = false }
                    Spacer()
                    Button("Save") {
                        let name = saveName.trimmingCharacters(in: .whitespaces)
                        let autoName = name.isEmpty ? (titleFromJSON(payloadJSON) ?? "Payload \(Date().formatted(.dateTime.hour().minute().second()))") : name
                        let p = PushCredentialStore.SavedPayload(
                            name: autoName, json: payloadJSON, savedAt: Date(), isAutoSaved: false)
                        PushCredentialStore.addPayload(p)
                        savedPayloads = PushCredentialStore.loadSavedPayloads()
                        saveName = ""
                        showSavePrompt = false
                    }.buttonStyle(.borderedProminent)
                }
            }
            .padding()
            .frame(width: 320)
        }
        .onAppear {
            engine.fcmCredential = PushCredentialStore.loadFCM()
            let cached = PushCredentialStore.loadFCMMessage()
            deviceToken = cached.deviceToken
            payloadJSON = cached.payloadJSON.isEmpty ? defaultPayload : cached.payloadJSON
            savedPayloads = PushCredentialStore.loadSavedPayloads()
            validateJSON()
        }
    }

    private func validateJSON() {
        guard let data = payloadJSON.data(using: .utf8),
              (try? JSONSerialization.jsonObject(with: data)) != nil else {
            jsonError = "Invalid JSON"
            return
        }
        jsonError = nil
    }

    private func saveMessageCache() {
        PushCredentialStore.saveFCMMessage(.init(deviceToken: deviceToken, payloadJSON: payloadJSON))
    }



    private func send() {
        guard !payloadJSON.trimmingCharacters(in: .whitespaces).isEmpty else {
            engine.lastError = "Payload JSON is empty"
            return
        }
        
        let tokens = deviceToken
            .components(separatedBy: CharacterSet(charactersIn: ",\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            
        guard !tokens.isEmpty else {
            engine.lastError = "Provide at least one device token"
            return
        }
        
        Task { await engine.sendFCM(deviceTokens: tokens, payloadJSON: payloadJSON) }
    }

    private func titleFromJSON(_ json: String) -> String? {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return obj["title"] as? String
    }
}

// MARK: - Saved Payload Panel

struct SavedPayloadPanel: View {
    @Binding var payloads: [PushCredentialStore.SavedPayload]
    let onSelect: (PushCredentialStore.SavedPayload) -> Void

    private static let dateFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        VStack(spacing: 0) {
            ForEach(payloads) { payload in
                HStack(spacing: 8) {
                    Image(systemName: payload.isAutoSaved ? "clock.arrow.circlepath" : "bookmark.fill")
                        .foregroundColor(payload.isAutoSaved ? Color.secondary : Color.blue)
                        .font(.caption)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(payload.name)
                            .font(.caption)
                            .lineLimit(1)
                        Text(Self.dateFmt.string(from: payload.savedAt))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                    Button {
                        onSelect(payload)
                    } label: {
                        Image(systemName: "arrow.up.doc.on.clipboard")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.blue)
                    .help("Load this payload")

                    Button {
                        PushCredentialStore.deletePayload(id: payload.id)
                        payloads = PushCredentialStore.loadSavedPayloads()
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.red)
                    .help("Delete")
                }
                .padding(.vertical, 4)
                if payload.id != payloads.last?.id { Divider() }
            }
        }
    }
}

