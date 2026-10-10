import CryptoKit
import Foundation
import Security

// OAuth 2.1 (PKCE, public client, dynamic registration) + a minimal MCP client over Streamable HTTP.
// ponytail: endpoints hardcoded from /.well-known/oauth-authorization-server; discover them there if the server moves.
nonisolated enum Kurz {
    static let mcpURL = URL(string: "https://api.kurz.fyi/mcp")!
    static let issuer = "https://api.kurz.fyi"
    static let authorizeURL = URL(string: "https://kurz.fyi/oauth/authorize")!
    static let tokenURL = URL(string: "https://api.kurz.fyi/oauth/token")!
    static let registerURL = URL(string: "https://api.kurz.fyi/oauth/register")!
    static let scheme = "fyi.kurz.app"
    static let redirect = "fyi.kurz.app://oauth/callback"
    static let scope = "appointments:read"  // read-only on purpose: the model can never change the agenda
}

nonisolated struct Failure: LocalizedError {
    let message: String
    /// Literals and interpolations are looked up in Localizable.xcstrings.
    init(_ message: String.LocalizationValue) { self.message = String(localized: message) }
    var errorDescription: String? { message }
}

private nonisolated struct Credentials: Codable {
    var clientID: String
    var accessToken: String?
    var refreshToken: String?
    var expiresAt: Date?
}

private nonisolated enum Keychain {
    static let item: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: Kurz.scheme]

    static func load() -> Credentials? {
        var out: AnyObject?
        let q = item.merging([kSecReturnData as String: true]) { $1 }
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return try? JSONDecoder().decode(Credentials.self, from: data)
    }

    static func save(_ c: Credentials) {
        guard let data = try? JSONEncoder().encode(c) else { return }
        SecItemDelete(item as CFDictionary)
        SecItemAdd(item.merging([kSecValueData as String: data]) { $1 } as CFDictionary, nil)
    }

    static func clear() { SecItemDelete(item as CFDictionary) }
}

private extension Data {
    nonisolated var base64url: String {
        base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

private extension CharacterSet {
    nonisolated static let formValue = CharacterSet.alphanumerics.union(.init(charactersIn: "-._~"))
}

/// Sends the request and returns the JSON object body; non-2xx becomes a `Failure` with the server's error text.
private nonisolated func json(_ r: URLRequest) async throws -> [String: Any] {
    let (data, resp) = try await URLSession.shared.data(for: r)
    let j = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    guard let code = (resp as? HTTPURLResponse)?.statusCode, (200..<300).contains(code) else {
        let why = (j["error_description"] as? String) ?? (j["error"] as? String) ?? String(localized: "HTTP error")
        throw Failure("\(r.url?.path ?? "server"): \(why)")
    }
    return j
}

actor Auth {
    private var creds = Keychain.load()

    /// A valid access token: cached, refreshed, or (last resort) a fresh browser login via `authenticate`.
    func token(authenticate: (URL) async throws -> URL) async throws -> String {
        if let t = creds?.accessToken, let exp = creds?.expiresAt, exp > .now.addingTimeInterval(30) { return t }
        // ponytail: any refresh failure falls back to a full login
        if let r = creds?.refreshToken, let t = try? await tokenRequest(["grant_type": "refresh_token", "refresh_token": r]) { return t }
        return try await login(authenticate)
    }

    /// True when a previous login left tokens behind (no network involved).
    var hasSession: Bool { creds?.refreshToken != nil || creds?.accessToken != nil }

    /// Local logout only. ponytail: also POST /oauth/revoke if tokens must die server-side.
    func logout() {
        creds = nil
        Keychain.clear()
    }

    private func login(_ authenticate: (URL) async throws -> URL) async throws -> String {
        let clientID: String
        if let id = creds?.clientID { clientID = id } else { clientID = try await register() }
        let verifier = Data((0..<32).map { _ in UInt8.random(in: .min ... .max) }).base64url
        let state = UUID().uuidString
        var url = URLComponents(url: Kurz.authorizeURL, resolvingAgainstBaseURL: false)!
        url.queryItems = [
            "response_type": "code", "client_id": clientID, "redirect_uri": Kurz.redirect, "scope": Kurz.scope,
            "state": state, "code_challenge": Data(SHA256.hash(data: Data(verifier.utf8))).base64url,
            "code_challenge_method": "S256", "resource": Kurz.mcpURL.absoluteString,
        ].map { URLQueryItem(name: $0, value: $1) }

        let callback = try await authenticate(url.url!)
        let q = Dictionary(
            (URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []).map { ($0.name, $0.value ?? "") },
            uniquingKeysWith: { $1 })
        if let error = q["error"] { throw Failure("Login refused: \(q["error_description"] ?? error)") }
        // The server advertises RFC 9207 (`iss`), so a missing/foreign issuer means a mix-up attack or a wrong server.
        guard q["iss"] == Kurz.issuer else { throw Failure("Login rejected: unexpected issuer (\(q["iss"] ?? String(localized: "missing")))") }
        guard q["state"] == state, let code = q["code"] else { throw Failure("Login rejected: invalid response") }
        return try await tokenRequest(["grant_type": "authorization_code", "code": code, "redirect_uri": Kurz.redirect, "code_verifier": verifier])
    }

    private func register() async throws -> String {
        var r = URLRequest(url: Kurz.registerURL)
        r.httpMethod = "POST"
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.httpBody = try JSONSerialization.data(withJSONObject: [
            "client_name": "Kurz", "redirect_uris": [Kurz.redirect], "response_types": ["code"],
            "grant_types": ["authorization_code", "refresh_token"], "token_endpoint_auth_method": "none",
        ])
        guard let id = try await json(r)["client_id"] as? String else { throw Failure("Registration returned no client_id") }
        creds = Credentials(clientID: id)
        Keychain.save(creds!)
        return id
    }

    private func tokenRequest(_ form: [String: String]) async throws -> String {
        guard var c = creds else { throw Failure("No registered client") }
        let fields = form.merging(["client_id": c.clientID, "resource": Kurz.mcpURL.absoluteString]) { $1 }
        var r = URLRequest(url: Kurz.tokenURL)
        r.httpMethod = "POST"
        r.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        r.httpBody = Data(
            fields.map { "\($0)=\($1.addingPercentEncoding(withAllowedCharacters: .formValue) ?? "")" }
                .joined(separator: "&").utf8)
        let j = try await json(r)
        guard let access = j["access_token"] as? String else { throw Failure("Invalid token response") }
        c.accessToken = access
        c.refreshToken = j["refresh_token"] as? String ?? c.refreshToken
        c.expiresAt = .now.addingTimeInterval(j["expires_in"] as? Double ?? 3600)
        creds = c
        Keychain.save(c)
        return access
    }
}

actor MCP {
    let auth = Auth()
    private var token = ""
    private var sessionID: String?
    private var nextID = 0

    /// Logs in if needed, runs the MCP handshake and returns the server's `tools/list`.
    /// ponytail: no `nextCursor` pagination; fine until the server has dozens of tools.
    func connect(authenticate: (URL) async throws -> URL) async throws -> [[String: Any]] {
        token = try await auth.token(authenticate: authenticate)
        sessionID = nil
        _ = try await rpc("initialize", ["protocolVersion": "2025-06-18", "capabilities": [:], "clientInfo": ["name": "Kurz", "version": "1.0"]])
        _ = try await rpc("notifications/initialized", notification: true)
        return try await rpc("tools/list")["tools"] as? [[String: Any]] ?? []
    }

    /// Calls a tool and returns its text content (tool-side errors come back as text so the model can react).
    func callTool(_ name: String, arguments: String) async throws -> String {
        let args = (try? JSONSerialization.jsonObject(with: Data(arguments.utf8))) ?? [String: Any]()
        let r = try await rpc("tools/call", ["name": name, "arguments": args])
        let text = (r["content"] as? [[String: Any]] ?? []).compactMap { $0["text"] as? String }.joined(separator: "\n")
        // ponytail: the on-device model has a ~4k-token window; paginate or pre-filter by date if agendas outgrow this cap
        return String(text.prefix(6000))
    }

    private func rpc(_ method: String, _ params: [String: Any] = [:], notification: Bool = false) async throws -> [String: Any] {
        var body: [String: Any] = ["jsonrpc": "2.0", "method": method, "params": params]
        if !notification {
            nextID += 1
            body["id"] = nextID
        }
        var r = URLRequest(url: Kurz.mcpURL)
        r.httpMethod = "POST"
        r.httpBody = try JSONSerialization.data(withJSONObject: body)
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        r.setValue("2025-06-18", forHTTPHeaderField: "MCP-Protocol-Version")
        if let sessionID { r.setValue(sessionID, forHTTPHeaderField: "Mcp-Session-Id") }

        let (data, resp) = try await URLSession.shared.data(for: r)
        guard let http = resp as? HTTPURLResponse else { throw Failure("Invalid MCP response") }
        if let s = http.value(forHTTPHeaderField: "Mcp-Session-Id") { sessionID = s }
        guard (200..<300).contains(http.statusCode) else { throw Failure("MCP replied with HTTP \(http.statusCode)") }
        if notification { return [:] }

        // The reply is either a JSON object or an SSE stream whose `data:` lines carry the JSON-RPC message.
        let text = String(decoding: data, as: UTF8.self)
        let payloads = text.first == "{" ? [text] : text.split(whereSeparator: \.isNewline).filter { $0.hasPrefix("data:") }.map { String($0.dropFirst(5)) }
        for p in payloads {
            guard let m = try? JSONSerialization.jsonObject(with: Data(p.utf8)) as? [String: Any], m["id"] as? Int == nextID else { continue }
            if let e = m["error"] as? [String: Any] { throw Failure("\(e["message"] as? String ?? String(localized: "MCP error"))") }
            return m["result"] as? [String: Any] ?? [:]
        }
        throw Failure("MCP response had no result")
    }
}
