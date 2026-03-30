import Foundation
import CryptoKit

// MARK: - Device Identity

private struct DeviceIdentity: Codable {
    let deviceId: String
    let privateKeyData: Data  // raw 32 bytes
    let publicKeyRaw: String  // base64url
}

private func base64URLEncode(_ data: Data) -> String {
    data.base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}

private let identityKeychainKey = "device-identity"
private let identityLegacyKey = "clawmo-identity"

private func getOrCreateIdentity() throws -> (DeviceIdentity, Curve25519.Signing.PrivateKey) {
    // Try Keychain first
    if let data = KeychainService.load(key: identityKeychainKey),
       let stored = try? JSONDecoder().decode(DeviceIdentity.self, from: data),
       let privateKey = try? Curve25519.Signing.PrivateKey(rawRepresentation: stored.privateKeyData) {
        return (stored, privateKey)
    }

    // Migrate from UserDefaults if exists
    if let data = UserDefaults.standard.data(forKey: identityLegacyKey),
       let stored = try? JSONDecoder().decode(DeviceIdentity.self, from: data),
       let privateKey = try? Curve25519.Signing.PrivateKey(rawRepresentation: stored.privateKeyData) {
        KeychainService.save(key: identityKeychainKey, data: data)
        UserDefaults.standard.removeObject(forKey: identityLegacyKey)
        NSLog("[identity] migrated device key from UserDefaults to Keychain")
        return (stored, privateKey)
    }

    // Create new identity
    let privateKey = Curve25519.Signing.PrivateKey()
    let publicKey = privateKey.publicKey
    let rawPublicBytes = publicKey.rawRepresentation

    let hash = SHA256.hash(data: rawPublicBytes)
    let deviceId = hash.map { String(format: "%02x", $0) }.joined()
    let publicKeyRaw = base64URLEncode(rawPublicBytes)

    let identity = DeviceIdentity(
        deviceId: deviceId,
        privateKeyData: privateKey.rawRepresentation,
        publicKeyRaw: publicKeyRaw
    )
    if let encoded = try? JSONEncoder().encode(identity) {
        KeychainService.save(key: identityKeychainKey, data: encoded)
    }
    return (identity, privateKey)
}

// MARK: - Gateway Message

struct GatewayMessage: Codable {
    let type: String?
    let id: String?
    let method: String?
    let ok: Bool?
    let payload: AnyCodable?
    let error: GatewayError?
    let event: String?
    let seq: Int?
}

struct GatewayError: Codable {
    let code: String
    let message: String
}

// MARK: - GatewayClient

typealias EventHandler = (String, [String: Any]) -> Void

@MainActor @Observable
final class GatewayClient {
    private(set) var isConnected = false
    private(set) var isConnecting = false

    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private var gatewayURL = ""
    private var gatewayToken = ""
    private var pendingRequests: [String: CheckedContinuation<[String: Any], Error>] = [:]
    private var eventHandlers: [EventHandler] = []
    private var suppressReconnect = false
    private var reconnectTask: Task<Void, Never>?
    private var pingTask: Task<Void, Never>?
    private var helloSnapshot: [String: Any]?
    private var identity: DeviceIdentity?
    private var privateKey: Curve25519.Signing.PrivateKey?

    func onEvent(_ handler: @escaping EventHandler) {
        eventHandlers.append(handler)
    }

    func connect(url: String, token: String) async throws {
        guard !isConnecting else { throw GatewayClientError.connectionFailed }
        isConnecting = true
        defer { isConnecting = false }
        disconnect()
        suppressReconnect = false
        gatewayURL = url
        gatewayToken = token

        guard let wsURL = URL(string: url),
              let scheme = wsURL.scheme?.lowercased(),
              scheme == "ws" || scheme == "wss" else {
            throw GatewayClientError.invalidURL
        }

        helloSnapshot = nil
        if identity == nil {
            let (id, key) = try getOrCreateIdentity()
            identity = id
            privateKey = key
        }
        urlSession = URLSession(configuration: .default)
        webSocketTask = urlSession?.webSocketTask(with: wsURL)
        NSLog("[GW] webSocketTask resume, url=\(url)")
        webSocketTask?.resume()

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            Task {
                // listenForHandshake handles all continuation resumes internally
                // Do not catch here — avoids double resume fatal error
                try? await self.listenForHandshake(continuation: continuation)
            }
        }

        // Start normal message loop and keepalive after connected
        startReceiving()
        startPing()
    }

    func disconnect() {
        suppressReconnect = true
        reconnectTask?.cancel()
        reconnectTask = nil
        pingTask?.cancel()
        pingTask = nil
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        urlSession = nil
        isConnected = false
        for (_, continuation) in pendingRequests {
            continuation.resume(throwing: GatewayClientError.disconnected)
        }
        pendingRequests.removeAll()
    }

    // MARK: - Requests

    func request(method: String, params: [String: Any] = [:]) async throws -> [String: Any] {
        guard isConnected else { throw GatewayClientError.notConnected }
        let id = UUID().uuidString
        let msg: [String: Any] = ["type": "req", "id": id, "method": method, "params": params]
        let data = try JSONSerialization.data(withJSONObject: msg)

        return try await withCheckedThrowingContinuation { continuation in
            pendingRequests[id] = continuation

            // Send task
            Task {
                do {
                    try await self.webSocketTask?.send(.data(data))
                } catch {
                    if let cont = self.pendingRequests.removeValue(forKey: id) {
                        cont.resume(throwing: error)
                    }
                }
            }

            // Independent timeout task
            Task {
                try? await Task.sleep(for: .seconds(30))
                if let cont = self.pendingRequests.removeValue(forKey: id) {
                    cont.resume(throwing: GatewayClientError.timeout)
                }
            }
        }
    }

    func listAgents() async throws -> [[String: Any]] {
        let result = try await request(method: "agents.list")
        return result["agents"] as? [[String: Any]] ?? []
    }

    func sendChat(sessionKey: String, message: String, attachments: [[String: Any]]? = nil) async throws {
        var params: [String: Any] = [
            "sessionKey": sessionKey,
            "message": message,
            "idempotencyKey": UUID().uuidString,
            "deliver": false
        ]
        if let attachments, !attachments.isEmpty {
            params["attachments"] = attachments
        }
        _ = try await request(method: "chat.send", params: params)
    }

    func abortChat(sessionKey: String) async throws {
        _ = try await request(method: "chat.abort", params: ["sessionKey": sessionKey])
    }

    func chatHistory(sessionKey: String, limit: Int = 50) async throws -> [String: Any] {
        try await request(method: "chat.history", params: ["sessionKey": sessionKey, "limit": limit])
    }

    func listSessions(agentId: String? = nil, limit: Int = 50, activeMinutes: Int? = nil) async throws -> [String: Any] {
        var params: [String: Any] = ["limit": limit]
        if let agentId { params["agentId"] = agentId }
        if let activeMinutes { params["activeMinutes"] = activeMinutes }
        return try await request(method: "sessions.list", params: params)
    }

    // MARK: - Private

    private var handshakeTimedOut = false

    private func listenForHandshake(continuation: CheckedContinuation<Void, Error>) async throws {
        NSLog("[GW] listenForHandshake started")
        handshakeTimedOut = false

        // Timeout: cancel the websocket so receive() returns nil — avoids double-resume
        let timeout = Task { [weak self] in
            try await Task.sleep(for: .seconds(15))
            NSLog("[GW] handshake TIMEOUT — cancelling socket")
            self?.handshakeTimedOut = true
            self?.webSocketTask?.cancel(with: .goingAway, reason: nil)
        }

        while !Task.isCancelled {
            guard let message = try? await webSocketTask?.receive() else {
                timeout.cancel()
                let error: GatewayClientError = handshakeTimedOut ? .timeout : .connectionFailed
                NSLog("[GW] receive() returned nil — \(error)")
                continuation.resume(throwing: error)
                return
            }

            guard let dict = parseMessage(message) else {
                NSLog("[GW] failed to parse message")
                continue
            }
            let event = dict["event"] as? String
            let type_ = dict["type"] as? String
            NSLog("[GW] recv type=\(type_ ?? "nil") event=\(event ?? "nil")")

            if event == "connect.challenge" {
                let payload = dict["payload"] as? [String: Any] ?? [:]
                NSLog("[GW] got challenge, responding...")
                try await handleChallenge(payload: payload)
                NSLog("[GW] challenge response sent")
                continue
            }

            if type_ == "res" {
                let payload = dict["payload"] as? [String: Any]
                NSLog("[GW] res payload type=\(payload?["type"] as? String ?? "nil")")
                if payload?["type"] as? String == "hello-ok" {
                    timeout.cancel()
                    helloSnapshot = payload?["snapshot"] as? [String: Any]
                    isConnected = true
                    NSLog("[GW] CONNECTED OK")
                    continuation.resume()
                    return
                }
                if let error = dict["error"] as? [String: Any] {
                    timeout.cancel()
                    let code = error["code"] as? String ?? ""
                    let msg = error["message"] as? String ?? "unknown error"
                    NSLog("[GW] auth error code=\(code) msg=\(msg)")
                    if code == "NOT_PAIRED" {
                        let requestId = error["requestId"] as? String ?? ""
                        let deviceId = identity?.deviceId ?? ""
                        continuation.resume(throwing: GatewayClientError.pairingRequired(deviceId: deviceId, requestId: requestId))
                    } else {
                        continuation.resume(throwing: GatewayClientError.authFailed(msg))
                    }
                    return
                }
            }
        }
    }

    private func startReceiving() {
        Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled, self.isConnected {
                guard let message = try? await self.webSocketTask?.receive() else {
                    self.isConnected = false
                    // Resume all pending requests so they fail immediately instead of waiting 30s
                    for (_, cont) in self.pendingRequests {
                        cont.resume(throwing: GatewayClientError.disconnected)
                    }
                    self.pendingRequests.removeAll()
                    if !self.suppressReconnect { self.scheduleReconnect() }
                    return
                }
                guard let dict = self.parseMessage(message) else { continue }
                self.handleMessage(dict)
            }
        }
    }

    private func handleMessage(_ dict: [String: Any]) {
        let type_ = dict["type"] as? String
        let id = dict["id"] as? String

        // Response to pending request
        if type_ == "res", let id, let continuation = pendingRequests.removeValue(forKey: id) {
            if dict["ok"] as? Bool == true {
                continuation.resume(returning: dict["payload"] as? [String: Any] ?? [:])
            } else {
                let msg = (dict["error"] as? [String: Any])?["message"] as? String ?? "request failed"
                continuation.resume(throwing: GatewayClientError.authFailed(msg))
            }
            return
        }

        // Events
        if type_ == "event", let event = dict["event"] as? String {
            let payload = dict["payload"] as? [String: Any] ?? [:]
            for handler in eventHandlers {
                handler(event, payload)
            }
        }
    }

    private func handleChallenge(payload: [String: Any]) async throws {
        guard let identity, let privateKey else { return }
        guard let nonce = payload["nonce"] as? String else { return }

        let signedAt = Int(Date().timeIntervalSince1970 * 1000)
        let scopes = ["operator.read", "operator.write", "operator.admin"]
        let sigPayload = [
            "v3",
            identity.deviceId,
            "gateway-client",
            "backend",
            "operator",
            scopes.joined(separator: ","),
            String(signedAt),
            gatewayToken,
            nonce,
            "ios",
            ""
        ].joined(separator: "|")

        guard let sigData = sigPayload.data(using: .utf8) else { return }
        let signature = try privateKey.signature(for: sigData)
        let signatureB64 = base64URLEncode(signature)

        let connectMsg: [String: Any] = [
            "type": "req",
            "id": UUID().uuidString,
            "method": "connect",
            "params": [
                "minProtocol": 3,
                "maxProtocol": 3,
                "client": [
                    "id": "gateway-client",
                    "mode": "backend",
                    "version": "1.0.0",
                    "platform": "ios"
                ],
                "role": "operator",
                "scopes": scopes,
                "auth": ["token": gatewayToken],
                "device": [
                    "id": identity.deviceId,
                    "publicKey": identity.publicKeyRaw,
                    "signature": signatureB64,
                    "signedAt": signedAt,
                    "nonce": nonce
                ]
            ]
        ]

        let data = try JSONSerialization.data(withJSONObject: connectMsg)
        try await webSocketTask?.send(.data(data))
    }

    private func parseMessage(_ message: URLSessionWebSocketTask.Message) -> [String: Any]? {
        switch message {
        case .string(let str):
            guard let data = str.data(using: .utf8),
                  let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
            return dict
        case .data(let data):
            return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        @unknown default:
            return nil
        }
    }

    private func startPing() {
        pingTask?.cancel()
        pingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard let self, self.isConnected, let ws = self.webSocketTask else { return }

                let pongOk = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
                    ws.sendPing { error in
                        cont.resume(returning: error == nil)
                    }
                }

                if !pongOk {
                    NSLog("[GW] ping/pong failed — treating as disconnected")
                    self.isConnected = false
                    for (_, cont) in self.pendingRequests {
                        cont.resume(throwing: GatewayClientError.disconnected)
                    }
                    self.pendingRequests.removeAll()
                    if !self.suppressReconnect { self.scheduleReconnect() }
                    return
                }
            }
        }
    }

    private func scheduleReconnect(delay: Int = 5) {
        let url = gatewayURL
        let token = gatewayToken
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard let self, !self.suppressReconnect, !url.isEmpty else { return }
            NSLog("[GW] reconnect attempt (delay=%ds)", delay)
            do {
                try await self.connect(url: url, token: token)
                NSLog("[GW] reconnect succeeded")
            } catch {
                NSLog("[GW] reconnect failed: %@", "\(error)")
                guard !self.suppressReconnect else { return }
                let nextDelay = min(delay * 2, 60)
                self.scheduleReconnect(delay: nextDelay)
            }
        }
    }
}

// MARK: - Errors

enum GatewayClientError: LocalizedError {
    case invalidURL
    case connectionFailed
    case authFailed(String)
    case pairingRequired(deviceId: String, requestId: String)
    case notConnected
    case disconnected
    case timeout

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Gateway URL 无效"
        case .connectionFailed: return "连接失败"
        case .authFailed(let msg): return "认证失败：\(msg)"
        case .pairingRequired(let deviceId, _):
            return "设备未配对，请在 Gateway 管理界面批准此设备\n设备ID：\(deviceId.prefix(16))..."
        case .notConnected: return "未连接"
        case .disconnected: return "已断开"
        case .timeout: return "连接超时"
        }
    }
}

// MARK: - AnyCodable helper

struct AnyCodable: Codable {
    let value: Any
    init(_ value: Any) { self.value = value }
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let v = try? container.decode(Bool.self) { value = v
        } else if let v = try? container.decode(Int.self) { value = v
        } else if let v = try? container.decode(Double.self) { value = v
        } else if let v = try? container.decode(String.self) { value = v
        } else { value = NSNull() }
    }
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case let v as Bool: try container.encode(v)
        case let v as Int: try container.encode(v)
        case let v as Double: try container.encode(v)
        case let v as String: try container.encode(v)
        default: try container.encodeNil()
        }
    }
}
