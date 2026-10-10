import CryptoKit
import Foundation
import Synchronization
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

extension APIClientTests {
    private final class Server: Sendable {
        let log = Mutex<[URLRequest]>([])
        let challengeFails: Bool
        let protectedError: Mutex<[String]>

        init(challengeFails: Bool = false, protectedErrors: [String] = []) {
            self.challengeFails = challengeFails
            protectedError = Mutex(protectedErrors)
        }

        var paths: [String] { log.withLock { $0.map { $0.url!.path } } }
        func requests(_ path: String) -> [URLRequest] { log.withLock { $0.filter { $0.url!.path == path } } }

        func handle(_ req: URLRequest) -> (Int, [String: String], Data) {
            let n = log.withLock { $0.append(req); return $0.count }
            switch req.url!.path {
            case "/api/app/challenge":
                if challengeFails { return (500, [:], Data()) }
                return (200, [:], Data(#"{"challenge":"\#(APIClientTests.challenge(n))","expires_in":300}"#.utf8))
            case "/api/app/attest": return (204, [:], Data())
            default:
                if let error = protectedError.withLock({ $0.isEmpty ? nil : $0.removeFirst() }) { return (403, [:], Data(#"{"error":"\#(error)"}"#.utf8)) }
                return (200, [:], Data("{}".utf8))
            }
        }
    }

    static func challenge(_ n: Int) -> String {
        Data(repeating: UInt8(n), count: 32).base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }

    private var body: Data { Data(#"{"email":"a@b.c","password":"p"}"#.utf8) }

    private func attested(_ server: Server, _ attestor: MemoryAppAttestor, _ store: TokenStore = MemoryTokenStore()) -> APIClient {
        Stub.handler = { server.handle($0) }
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [Stub.self]
        let configuration = APIConfiguration(baseURL: URL(string: "http://localhost:3000")!, session: URLSession(configuration: cfg))
        return APIClient(configuration: configuration, attest: AppAttestClient(configuration: configuration, attestor: attestor, store: store), token: { nil })
    }

    private func login() -> Endpoint<Empty> { Endpoint("POST", "api/login/password", body: body) }

    private struct Empty: Decodable, Sendable {}

    @Test func signsProtectedRequestsWithAFreshChallengeEach() async throws {
        let server = Server()
        let attestor = MemoryAppAttestor()
        let store = MemoryTokenStore()
        let api = attested(server, attestor, store)
        _ = try await api.raw(login())
        _ = try await api.raw(login())

        #expect(server.paths == ["/api/app/challenge", "/api/app/attest", "/api/app/challenge", "/api/login/password", "/api/app/challenge", "/api/login/password"])
        #expect(store.load() == "key-1")
        #expect(attestor.calls.generated == 1)
        #expect(attestor.calls.attested == [Data(SHA256.hash(data: Data(base64URLEncoded: Self.challenge(1))!))])
        let attest = try JSONSerialization.jsonObject(with: server.requests("/api/app/attest")[0].bodyData) as! [String: String]
        #expect(attest == ["key_id": "key-1", "attestation": Data("attestation:key-1".utf8).base64EncodedString(), "challenge": Self.challenge(1)])

        let signed = server.requests("/api/login/password")
        #expect(signed.map { $0.value(forHTTPHeaderField: "X-Kurz-App-Challenge") } == [Self.challenge(3), Self.challenge(5)])
        #expect(signed.map { $0.value(forHTTPHeaderField: "X-Kurz-App-Key-Id") } == ["key-1", "key-1"])
        #expect(signed.map { $0.value(forHTTPHeaderField: "X-Kurz-App-Assertion") } == [1, 2].map { Data("assertion:key-1:\($0)".utf8).base64EncodedString() })
        #expect(attestor.calls.asserted == [3, 5].map { Data(SHA256.hash(data: Data(base64URLEncoded: Self.challenge($0))! + body)) })
    }

    @Test func leavesOtherPathsAlone() async throws {
        let server = Server()
        _ = try await attested(server, MemoryAppAttestor()).raw(Endpoint<Empty>("GET", "api/me"))
        #expect(server.paths == ["/api/me"])
        #expect(server.log.withLock { $0[0].value(forHTTPHeaderField: "X-Kurz-App-Key-Id") } == nil)
    }

    @Test func unsupportedDevicesSendPlainRequests() async throws {
        let server = Server()
        let attestor = MemoryAppAttestor(isSupported: false)
        _ = try await attested(server, attestor).raw(login())
        #expect(server.paths == ["/api/login/password"])
        #expect(server.log.withLock { $0[0].value(forHTTPHeaderField: "X-Kurz-App-Assertion") } == nil)
        #expect(attestor.calls == .init())
    }

    @Test func failsSoftWhenTheChallengeIsUnavailable() async throws {
        let server = Server(challengeFails: true)
        let store = MemoryTokenStore()
        _ = try await attested(server, MemoryAppAttestor(), store).raw(login())
        #expect(server.paths == ["/api/app/challenge", "/api/login/password"])
        #expect(server.requests("/api/login/password")[0].value(forHTTPHeaderField: "X-Kurz-App-Key-Id") == nil)
        #expect(store.load() == nil)
    }

    @Test func retriesOnceWhenAppAttestIsUnavailable() async throws {
        let attestor = MemoryAppAttestor()
        attestor.failNext(unavailable: 1)
        let server = Server()
        _ = try await attested(server, attestor).raw(login())
        #expect(server.requests("/api/login/password")[0].value(forHTTPHeaderField: "X-Kurz-App-Key-Id") == "key-1")
    }

    @Test func regeneratesAKeyTheDeviceRejects() async throws {
        let attestor = MemoryAppAttestor()
        attestor.invalidate("old")
        let store = MemoryTokenStore("old")
        let server = Server()
        _ = try await attested(server, attestor, store).raw(login())
        #expect(store.load() == "key-1")
        #expect(server.requests("/api/login/password")[0].value(forHTTPHeaderField: "X-Kurz-App-Key-Id") == "key-1")
    }

    @Test func reattestsWhenTheServerRejectsTheAssertion() async throws {
        let attestor = MemoryAppAttestor()
        let store = MemoryTokenStore("stale")
        let server = Server(protectedErrors: ["invalid_attestation"])
        let (_, http) = try await attested(server, attestor, store).raw(login())
        #expect(http.statusCode == 200)
        #expect(server.paths == ["/api/app/challenge", "/api/login/password", "/api/app/challenge", "/api/app/attest", "/api/app/challenge", "/api/login/password"])
        #expect(server.requests("/api/login/password").map { $0.value(forHTTPHeaderField: "X-Kurz-App-Key-Id") } == ["stale", "key-1"])
        #expect(store.load() == "key-1")
    }

    @Test func concurrentFirstRequestsShareOneKey() async throws {
        let attestor = MemoryAppAttestor()
        let api = attested(Server(), attestor)
        async let a = api.raw(login())
        async let b = api.raw(login())
        _ = try await (a, b)
        #expect(attestor.calls.generated == 1)
        #expect(attestor.calls.attested.count == 1)
        #expect(attestor.calls.asserted.count == 2)
    }
}

private extension URLRequest {
    var bodyData: Data {
        if let httpBody { return httpBody }
        guard let stream = httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let n = stream.read(&buffer, maxLength: buffer.count)
            if n <= 0 { break }
            data.append(buffer, count: n)
        }
        return data
    }
}
