import Domain
import Foundation
import Networking

public struct AuthService: Sendable {
    public let api: APIClient
    private let store: TokenStore

    public init(configuration: APIConfiguration, store: TokenStore, attest: AppAttestClient? = nil) {
        self.store = store
        api = APIClient(configuration: configuration, attest: attest, token: { store.load() })
    }

    public func signIn(email: String, password: String) async throws -> CurrentUser {
        try start(try await api.raw(try .post("api/login/password", json: ["email": email, "password": password]) as Endpoint<UserEnvelope>))
    }

    public func requestCode(email: String, locale: String? = nil) async throws {
        _ = try await api.raw(try .post("api/login_request", json: ["email": email, "locale": locale].compactMapValues { $0 }) as Endpoint<Empty>)
    }

    public func verify(email: String, code: String) async throws -> CurrentUser {
        try start(try await api.raw(try .post("api/login_verify", json: ["email": email, "code": code]) as Endpoint<UserEnvelope>))
    }

    public func signInWithGoogle(idToken: String) async throws -> CurrentUser {
        let (data, http) = try await api.unchecked(try .post("api/login/google", json: ["credential": idToken]) as Endpoint<UserEnvelope>)
        guard (200..<300).contains(http.statusCode) else { throw APIError.server(status: http.statusCode, message: APIClient.message(in: data)) }
        return try start((data, http))
    }

    private func start(_ response: (Data, HTTPURLResponse)) throws -> CurrentUser {
        guard let token = response.1.sessionToken else { throw APIError.invalidResponse }
        let user = try APIClient.decoder.decode(UserEnvelope.self, from: response.0).user
        store.save(token)
        return user
    }

    public func currentUser() async throws -> CurrentUser? {
        guard store.load() != nil else { return nil }
        do {
            return try await api.send(Endpoint<UserEnvelope>("GET", "api/me")).user
        } catch APIError.unauthorized {
            store.clear()
            return nil
        }
    }

    public func signOut() async {
        _ = try? await api.raw(Endpoint<Empty>("DELETE", "api/logout"))
        store.clear()
    }
}

public struct Empty: Decodable, Sendable {}
