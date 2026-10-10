import Foundation
import Testing
@testable import Networking

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

@Suite(.serialized) struct APIClientTests {
    private func client(token: String? = "T") -> APIClient {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [Stub.self]
        return APIClient(configuration: .init(baseURL: URL(string: "http://localhost:3000")!, session: URLSession(configuration: cfg)), token: { token })
    }

    private struct Ping: Decodable, Sendable { var someValue: Int }

    @Test func sendsBearerAndDecodesSnakeCase() async throws {
        Stub.handler = { req in
            #expect(req.value(forHTTPHeaderField: "Authorization") == "Bearer T")
            #expect(req.url?.query == "from=2026-10-10")
            return (200, [:], Data(#"{"some_value":4}"#.utf8))
        }
        let r = try await client().send(Endpoint<Ping>("GET", "api/me/agenda", query: [.init(name: "from", value: "2026-10-10")]))
        #expect(r.someValue == 4)
    }

    @Test func rateLimitCarriesRetryAfterSeconds() async {
        Stub.handler = { _ in (429, ["Retry-After": "42"], Data()) }
        await #expect(throws: APIError.rateLimited(retryAfter: 42)) { try await client().send(Endpoint<Ping>("GET", "x")) }
        Stub.handler = { _ in (429, ["Retry-After": "Wed, 21 Oct 2026 07:28:00 GMT"], Data()) }
        await #expect(throws: APIError.rateLimited(retryAfter: nil)) { try await client().send(Endpoint<Ping>("GET", "x")) }
        Stub.handler = { _ in (429, [:], Data()) }
        await #expect(throws: APIError.rateLimited(retryAfter: nil)) { try await client().send(Endpoint<Ping>("GET", "x")) }
    }

    @Test func mapsStatusCodes() async {
        Stub.handler = { _ in (401, [:], Data()) }
        await #expect(throws: APIError.unauthorized) { try await client().send(Endpoint<Ping>("GET", "x")) }
        Stub.handler = { _ in (422, [:], Data(#"{"error":"invalid_range"}"#.utf8)) }
        await #expect(throws: APIError.server(status: 422, message: "invalid_range")) { try await client().send(Endpoint<Ping>("GET", "x")) }
    }

    @Test func readsTheSessionCookieFromALoginResponse() async throws {
        Stub.handler = { _ in (200, ["Set-Cookie": "kurz_session=abc.def; path=/; httponly; samesite=strict"], Data("{}".utf8)) }
        let (_, http) = try await client(token: nil).raw(Endpoint<Ping>("POST", "api/login_verify"))
        #expect(http.sessionToken == "abc.def")
    }
}
