import Foundation

/// Persists APNs and FCM credentials + last-used message state to UserDefaults
final class PushCredentialStore {
    private static let apnsKey         = "proxymock.push.apns"
    private static let fcmKey          = "proxymock.push.fcm"
    private static let apnsMsgKey      = "proxymock.push.apns.msg"
    private static let fcmMsgKey       = "proxymock.push.fcm.msg"
    private static let savedPayloadsKey = "proxymock.push.saved_payloads"

    static let maxSavedPayloads = 50

    // MARK: - Credentials

    static func saveAPNs(_ cred: APNsCredential) {
        if let data = try? JSONEncoder().encode(cred) {
            UserDefaults.standard.set(data, forKey: apnsKey)
        }
    }

    static func loadAPNs() -> APNsCredential {
        guard let data = UserDefaults.standard.data(forKey: apnsKey),
              let cred = try? JSONDecoder().decode(APNsCredential.self, from: data) else {
            return APNsCredential()
        }
        return cred
    }

    static func saveFCM(_ cred: FCMCredential) {
        if let data = try? JSONEncoder().encode(cred) {
            UserDefaults.standard.set(data, forKey: fcmKey)
        }
    }

    static func loadFCM() -> FCMCredential {
        guard let data = UserDefaults.standard.data(forKey: fcmKey),
              let cred = try? JSONDecoder().decode(FCMCredential.self, from: data) else {
            return FCMCredential()
        }
        return cred
    }

    // MARK: - Message cache

    struct MessageCache: Codable {
        var deviceToken: String = ""
        /// JSON string: { "title": "...", "body": "...", ... }
        var payloadJSON: String = "{\n  \"title\": \"\",\n  \"body\": \"\"\n}"
    }

    static func saveAPNsMessage(_ cache: MessageCache) {
        if let data = try? JSONEncoder().encode(cache) {
            UserDefaults.standard.set(data, forKey: apnsMsgKey)
        }
    }

    static func loadAPNsMessage() -> MessageCache {
        guard let data = UserDefaults.standard.data(forKey: apnsMsgKey),
              let cache = try? JSONDecoder().decode(MessageCache.self, from: data) else {
            return MessageCache()
        }
        return cache
    }

    static func saveFCMMessage(_ cache: MessageCache) {
        if let data = try? JSONEncoder().encode(cache) {
            UserDefaults.standard.set(data, forKey: fcmMsgKey)
        }
    }

    static func loadFCMMessage() -> MessageCache {
        guard let data = UserDefaults.standard.data(forKey: fcmMsgKey),
              let cache = try? JSONDecoder().decode(MessageCache.self, from: data) else {
            return MessageCache()
        }
        return cache
    }

    // MARK: - Saved Payloads

    struct SavedPayload: Codable, Identifiable {
        var id: UUID = UUID()
        /// User-provided name or auto-generated from title
        var name: String
        var json: String
        var savedAt: Date
        var isAutoSaved: Bool   // true = saved on send; false = manually saved
    }

    static func loadSavedPayloads() -> [SavedPayload] {
        guard let data = UserDefaults.standard.data(forKey: savedPayloadsKey),
              let list = try? JSONDecoder().decode([SavedPayload].self, from: data) else {
            return []
        }
        return list
    }

    static func addPayload(_ payload: SavedPayload) {
        var list = loadSavedPayloads()
        // Deduplicate identical JSON
        list.removeAll { $0.json == payload.json && $0.isAutoSaved == payload.isAutoSaved }
        list.insert(payload, at: 0)
        if list.count > maxSavedPayloads { list = Array(list.prefix(maxSavedPayloads)) }
        if let data = try? JSONEncoder().encode(list) {
            UserDefaults.standard.set(data, forKey: savedPayloadsKey)
        }
    }

    static func deletePayload(id: UUID) {
        var list = loadSavedPayloads()
        list.removeAll { $0.id == id }
        if let data = try? JSONEncoder().encode(list) {
            UserDefaults.standard.set(data, forKey: savedPayloadsKey)
        }
    }

    static func clearAutoSaved() {
        var list = loadSavedPayloads()
        list.removeAll { $0.isAutoSaved }
        if let data = try? JSONEncoder().encode(list) {
            UserDefaults.standard.set(data, forKey: savedPayloadsKey)
        }
    }
}

