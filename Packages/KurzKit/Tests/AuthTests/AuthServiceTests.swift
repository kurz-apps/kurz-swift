import Domain
import Foundation
import Networking
import Testing
@testable import Auth

private final class Stub: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) -> (Int, [String: String], Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let (status, headers, body) = Stub.handler!(request)
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: headers)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

private let userJSON = #"{"user":{"id":1,"email":"a@b.co","admin":false,"time_zone":"UTC","locale":null,"has_password":false,"google_connected":false}}"#

@Suite(.serialized) struct AuthServiceTests {
    private func service(_ store: TokenStore) -> AuthService {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [Stub.self]
        return AuthService(configuration: .init(baseURL: URL(string: "http://localhost:3000")!, session: URLSession(configuration: cfg)), store: store)
    }

    @Test func verifyStoresTheCookieTokenAndReturnsTheUser() async throws {
        Stub.handler = { _ in (200, ["Set-Cookie": "kurz_session=tok123; path=/; httponly"], Data(userJSON.utf8)) }
        let store = MemoryTokenStore()
        let user = try await service(store).verify(email: "a@b.co", code: "123456")
        #expect(user.email == "a@b.co")
        #expect(store.load() == "tok123")
    }

    @Test func wrongCodeThrowsUnauthorizedAndStoresNothing() async {
        Stub.handler = { _ in (401, [:], Data(#"{"error":"Token invalid or expired"}"#.utf8)) }
        let store = MemoryTokenStore()
        await #expect(throws: APIError.unauthorized) { try await service(store).verify(email: "a@b.co", code: "000000") }
        #expect(store.load() == nil)
    }

    @Test func expiredSessionIsClearedOnRestore() async throws {
        Stub.handler = { _ in (401, [:], Data()) }
        let store = MemoryTokenStore("old")
        #expect(try await service(store).currentUser() == nil)
        #expect(store.load() == nil)
    }

    @Test func noTokenMeansNoRequest() async throws {
        Stub.handler = { _ in Issue.record("no request expected"); return (500, [:], Data()) }
        #expect(try await service(MemoryTokenStore()).currentUser() == nil)
    }

    @Test func signOutForgetsTheTokenEvenWhenOffline() async {
        Stub.handler = { _ in (500, [:], Data()) }
        let store = MemoryTokenStore("t")
        await service(store).signOut()
        #expect(store.load() == nil)
    }

    @Test func passwordSignInStoresTheCookieToken() async throws {
        Stub.handler = { req in
            #expect(req.url?.path == "/api/login/password")
            return (200, ["Set-Cookie": "kurz_session=pw1; path=/; httponly"], Data(userJSON.utf8))
        }
        let store = MemoryTokenStore()
        _ = try await service(store).signIn(email: "a@b.co", password: "secret123")
        #expect(store.load() == "pw1")
    }
}
