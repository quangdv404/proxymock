@preconcurrency import Foundation
@preconcurrency import Security

// MARK: - Models

enum PushPlatform: String, Codable, CaseIterable {
    case apns = "iOS (APNs)"
    case fcm  = "Android (FCM)"
}

enum APNsEnvironment: String, Codable, CaseIterable {
    case sandbox    = "Sandbox"
    case production = "Production"
}

struct APNsCredential: Codable {
    var p12Base64: String = ""   // Base64-encoded .p12 file content
    var p12Password: String = ""
    var bundleID: String = ""
    var environment: APNsEnvironment = .sandbox
}

struct FCMCredential: Codable {
    var serviceAccountJSON: String = ""  // Raw JSON string from Firebase console
}



// MARK: - Engine

@MainActor
@Observable
final class PushNotificationEngine {
    var apnsCredential = APNsCredential()
    var fcmCredential  = FCMCredential()
    var isSending = false
    var lastError: String?

    // MARK: - APNs

    /// Send a push via APNs to one or more device tokens.
    /// `payloadJSON` is sent verbatim as the request body — you control the full structure.
    /// Errors per-token are aggregated and surfaced via `lastError`.
    func sendAPNs(deviceTokens: [String], payloadJSON: String) async {
        isSending = true
        lastError = nil
        defer { isSending = false }

        let cred = apnsCredential
        guard !cred.p12Base64.isEmpty, !cred.bundleID.isEmpty else {
            lastError = "Incomplete credentials"
            return
        }

        guard let payloadData = payloadJSON.data(using: .utf8) else {
            lastError = "Invalid JSON payload"
            return
        }

        let identity: SecIdentity
        do {
            identity = try loadIdentity(p12Base64: cred.p12Base64, password: cred.p12Password)
        } catch {
            lastError = error.localizedDescription
            return
        }

        let host = cred.environment == .sandbox
            ? "https://api.sandbox.push.apple.com"
            : "https://api.push.apple.com"

        var failures: [(token: String, reason: String)] = []

        for token in deviceTokens {
            let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            guard let url = URL(string: "\(host)/3/device/\(trimmed)") else {
                failures.append((trimmed, PushError.invalidURL.localizedDescription ?? "Invalid URL"))
                continue
            }

            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue(cred.bundleID, forHTTPHeaderField: "apns-topic")
            req.setValue("alert",       forHTTPHeaderField: "apns-push-type")
            req.setValue("10",          forHTTPHeaderField: "apns-priority")
            req.setValue("application/json", forHTTPHeaderField: "content-type")
            req.httpBody = payloadData

            do {
                let delegate = APNsSessionDelegate(identity: identity)
                let session  = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)
                let (_, response) = try await session.data(for: req)
                session.finishTasksAndInvalidate()

                let http = response as? HTTPURLResponse
                let code = http?.statusCode ?? 0
                if !(200..<300).contains(code) {
                    let reason = http?.value(forHTTPHeaderField: "apns-id") ?? "HTTP \(code)"
                    failures.append((trimmed, reason))
                }
            } catch {
                failures.append((trimmed, error.localizedDescription))
            }
        }

        if !failures.isEmpty {
            let total = deviceTokens.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count
            let summary = failures.map { "\($0.token.prefix(8))… – \($0.reason)" }.joined(separator: "\n")
            lastError = "\(failures.count)/\(total) failed:\n\(summary)"
        }
    }

    /// Extract a SecIdentity from a base64-encoded P12 file
    private func loadIdentity(p12Base64: String, password: String) throws -> SecIdentity {
        guard let p12Data = Data(base64Encoded: p12Base64) else {
            throw PushError.invalidCredential("Cannot decode P12 data")
        }
        let options: [String: Any] = [kSecImportExportPassphrase as String: password]
        var items: CFArray?
        let status = SecPKCS12Import(p12Data as CFData, options as CFDictionary, &items)
        guard status == errSecSuccess,
              let array = items as? [[String: Any]],
              let first = array.first,
              let identity = first[kSecImportItemIdentity as String] else {
            throw PushError.invalidCredential("P12 import failed (status \(status)). Check the password.")
        }
        // swiftlint:disable:next force_cast
        return (identity as! SecIdentity)
    }

    // MARK: - FCM v1

    /// Send a push via FCM HTTP v1 using a Service Account JSON for OAuth2.
    /// `payloadJSON` top-level keys "title" and "body" are used for FCM notification + history;
    /// the entire dict is also forwarded as the FCM `data` field so the app receives everything.
    func sendFCM(deviceTokens: [String], payloadJSON: String) async {
        isSending = true
        lastError = nil
        defer { isSending = false }

        let topLevel = (try? JSONSerialization.jsonObject(with: Data(payloadJSON.utf8))) as? [String: Any]
        let title = topLevel?["title"] as? String ?? ""
        let body  = topLevel?["body"]  as? String ?? ""

        guard !fcmCredential.serviceAccountJSON.isEmpty else {
            lastError = "No service account JSON"
            return
        }

        let sa: FCMServiceAccount
        let accessToken: String
        do {
            guard let jsonData = fcmCredential.serviceAccountJSON.data(using: .utf8),
                  let parsed = try? JSONDecoder().decode(FCMServiceAccount.self, from: jsonData) else {
                throw PushError.invalidCredential("Cannot parse service account JSON")
            }
            sa = parsed
            accessToken = try await getFCMAccessToken(sa: sa)
        } catch {
            lastError = error.localizedDescription
            return
        }

        let urlStr = "https://fcm.googleapis.com/v1/projects/\(sa.projectID)/messages:send"
        guard let url = URL(string: urlStr) else {
            lastError = PushError.invalidURL.localizedDescription
            return
        }

        // Convert payload JSON to [String: String] for FCM data field
        var dataDict: [String: String] = [:]
        if let dict = topLevel {
            for (k, v) in dict { dataDict[k] = (v as? String) ?? "\(v)" }
        }

        var failures: [(token: String, reason: String)] = []

        for token in deviceTokens {
            let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            let message: [String: Any] = [
                "token": trimmed,
                "notification": ["title": title, "body": body],
                "data": dataDict
            ]

            do {
                let reqBody = try JSONSerialization.data(withJSONObject: ["message": message])
                var req = URLRequest(url: url)
                req.httpMethod = "POST"
                req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
                req.setValue("application/json",      forHTTPHeaderField: "Content-Type")
                req.httpBody = reqBody

                let (respData, response) = try await URLSession.shared.data(for: req)
                let http = response as? HTTPURLResponse
                let code = http?.statusCode ?? 0
                if !(200..<300).contains(code) {
                    let reason = String(data: respData, encoding: .utf8) ?? "HTTP \(code)"
                    failures.append((trimmed, reason))
                }
            } catch {
                failures.append((trimmed, error.localizedDescription))
            }
        }

        if !failures.isEmpty {
            let total = deviceTokens.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count
            let summary = failures.map { "\($0.token.prefix(8))… – \($0.reason)" }.joined(separator: "\n")
            lastError = "\(failures.count)/\(total) failed:\n\(summary)"
        }
    }

    // MARK: - Private helpers


    private func jsonBase64url(_ dict: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: dict)
        return data.base64url
    }

    /// Exchange service account JSON for a short-lived OAuth2 access token
    private func getFCMAccessToken(sa: FCMServiceAccount) async throws -> String {
        let now = Int(Date().timeIntervalSince1970)
        let expiry = now + 3600
        let audience = sa.tokenURI

        // Build JWT
        let header = try jsonBase64url(["alg": "RS256", "typ": "JWT"])
        let claims = try jsonBase64url([
            "iss": sa.clientEmail,
            "scope": "https://www.googleapis.com/auth/firebase.messaging",
            "aud": audience,
            "exp": expiry,
            "iat": now
        ])
        let signingInput = "\(header).\(claims)"
        guard let signingData = signingInput.data(using: String.Encoding.utf8) else {
            throw PushError.invalidCredential("JWT signing input encoding failed")
        }

        // Parse RSA private key from PKCS#8 PEM using Security framework
        let pemStripped = sa.privateKey
            .components(separatedBy: "\n")
            .filter { !$0.hasPrefix("-----") && !$0.isEmpty }
            .joined()
        guard let pkcs8Data = Data(base64Encoded: pemStripped) else {
            throw PushError.invalidCredential("Failed to decode RSA private key")
        }
        let sig = try rsaSHA256Sign(data: signingData, pkcs8DER: pkcs8Data)
        let jwt = "\(signingInput).\(sig.base64url)"

        // Exchange JWT for access token
        guard let tokenURL = URL(string: audience) else { throw PushError.invalidURL }
        var req = URLRequest(url: tokenURL)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = "grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Ajwt-bearer&assertion=\(jwt)"
        req.httpBody = Data(body.utf8)

        let (data, _) = try await URLSession.shared.data(for: req)
        guard let json = try? JSONDecoder().decode(FCMTokenResponse.self, from: data),
              !json.accessToken.isEmpty else {
            let raw = String(data: data, encoding: .utf8) ?? "Unknown"
            throw PushError.invalidCredential("Token exchange failed: \(raw)")
        }
        return json.accessToken
    }

    /// RSA-SHA256 PKCS1v1.5 signing using the Security framework
    private func rsaSHA256Sign(data: Data, pkcs8DER: Data) throws -> Data {
        // Import the PKCS#8 key
        let attrs: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String: kSecAttrKeyClassPrivate
        ]
        var error: Unmanaged<CFError>?
        guard let secKey = SecKeyCreateWithData(pkcs8DER as CFData, attrs as CFDictionary, &error) else {
            let desc = error?.takeRetainedValue().localizedDescription ?? "Unknown SecKey error"
            throw PushError.invalidCredential(desc)
        }
        let algorithm = SecKeyAlgorithm.rsaSignatureMessagePKCS1v15SHA256
        guard SecKeyIsAlgorithmSupported(secKey, .sign, algorithm) else {
            throw PushError.invalidCredential("RSA signing algorithm not supported")
        }
        guard let signature = SecKeyCreateSignature(secKey, algorithm, data as CFData, &error) else {
            let desc = error?.takeRetainedValue().localizedDescription ?? "Signing failed"
            throw PushError.invalidCredential(desc)
        }
        return signature as Data
    }
}

// MARK: - APNs URLSession Delegate (P12 client certificate)

private final class APNsSessionDelegate: NSObject, URLSessionDelegate {
    private let identity: SecIdentity

    init(identity: SecIdentity) {
        self.identity = identity
    }

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodClientCertificate else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        // Build credential from the P12 identity
        var certRef: SecCertificate?
        SecIdentityCopyCertificate(identity, &certRef)
        let certs: [SecCertificate] = certRef.map { [$0] } ?? []
        let credential = URLCredential(identity: identity, certificates: certs, persistence: .forSession)
        completionHandler(.useCredential, credential)
    }
}

// MARK: - Supporting Codable types

private struct FCMServiceAccount: Codable {
    let projectID: String
    let privateKey: String
    let clientEmail: String
    let tokenURI: String

    enum CodingKeys: String, CodingKey {
        case projectID   = "project_id"
        case privateKey  = "private_key"
        case clientEmail = "client_email"
        case tokenURI    = "token_uri"
    }
}

private struct FCMTokenResponse: Codable {
    let accessToken: String
    enum CodingKeys: String, CodingKey { case accessToken = "access_token" }
}

// MARK: - Errors

enum PushError: LocalizedError {
    case invalidURL
    case invalidCredential(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid push endpoint URL"
        case .invalidCredential(let msg): return "Credential error: \(msg)"
        }
    }
}

// MARK: - Data helpers

private extension Data {
    var base64url: String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
