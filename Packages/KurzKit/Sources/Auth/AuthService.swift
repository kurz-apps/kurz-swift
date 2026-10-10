import Domain
import Foundation
import Networking

public struct AuthService: Sendable {
    public let api: APIClient
    private let store: TokenStore

    public init(configuration: APIConfiguration, store: TokenStore) {
        self.store = store
        api = APIClient(configuration: configuration, token: { store.load() })
    }

    public func signIn(email: String, password: String) async throws -> CurrentUser {
        let (data, http) = try await api.raw(try .post("api/login/password", json: ["email": email, "password": password]) as Endpoint<UserEnvelope>)
        guard let token = http.sessionToken else { throw APIError.invalidResponse }
        let user = try APIClient.decoder.decode(UserEnvelope.self, from: data).user
        store.save(token)
        return user
    }

    public func requestCode(email: String, locale: String? = nil) async throws {
        _ = try await api.raw(try .post("api/login_request", json: ["email": email, "locale": locale].compactMapValues { $0 }) as Endpoint<Empty>)
    }

    public func verify(email: String, code: String) async throws -> CurrentUser {
        let (data, http) = try await api.raw(try .post("api/login_verify", json: ["email": email, "code": code]) as Endpoint<UserEnvelope>)
        guard let token = http.sessionToken else { throw APIError.invalidResponse }
        let user = try APIClient.decoder.decode(UserEnvelope.self, from: data).user
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
