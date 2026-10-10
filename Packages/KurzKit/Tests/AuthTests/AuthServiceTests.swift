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

private func body(_ request: URLRequest) -> String {
    guard let stream = request.httpBodyStream else { return String(decoding: request.httpBody ?? Data(), as: UTF8.self) }
    stream.open()
    defer { stream.close() }
    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 4096)
    while stream.hasBytesAvailable, case let n = stream.read(&buffer, maxLength: buffer.count), n > 0 { data.append(buffer, count: n) }
    return String(decoding: data, as: UTF8.self)
}

private func form(_ string: String) -> [String: String] {
    var components = URLComponents()
    components.percentEncodedQuery = string
    return Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
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

    private var stubbedSession: URLSession {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [Stub.self]
        return URLSession(configuration: cfg)
    }

    @Test func googleAuthorizationURLUsesPKCEAndTheNativeClient() throws {
        let google = GoogleSignInService()
        let request = google.makeRequest()
        let items = Dictionary(uniqueKeysWithValues: (URLComponents(url: request.url, resolvingAgainstBaseURL: false)?.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        #expect(request.url.absoluteString.hasPrefix("https://accounts.google.com/o/oauth2/v2/auth?"))
        #expect(items["client_id"] == "146729417680-0b8olcohquir6qghpblo0s0oq45siqca.apps.googleusercontent.com")
        #expect(items["redirect_uri"] == "com.googleusercontent.apps.146729417680-0b8olcohquir6qghpblo0s0oq45siqca:/oauth2redirect")
        #expect(items["response_type"] == "code")
        #expect(items["scope"] == "openid email profile")
        #expect(items["state"] == request.state)
        #expect(items["code_challenge_method"] == "S256")
        #expect(items["code_challenge"] == GoogleSignInService.challenge(for: request.verifier))
        #expect(request.verifier.count == 43)
        #expect(request.state != google.makeRequest().state)
    }

    @Test func pkceChallengeMatchesTheRFCExample() {
        #expect(GoogleSignInService.challenge(for: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk") == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }

    @Test func googleCodeIsExchangedForTheIDToken() async throws {
        let google = GoogleSignInService(session: stubbedSession)
        let request = google.makeRequest()
        Stub.handler = { req in
            #expect(req.url == GoogleSignInService.tokenEndpoint)
            #expect(req.httpMethod == "POST")
            #expect(req.value(forHTTPHeaderField: "Content-Type") == "application/x-www-form-urlencoded")
            let fields = form(body(req))
            #expect(fields == [
                "code": "4/0A+b c",
                "client_id": google.clientID,
                "code_verifier": request.verifier,
                "redirect_uri": google.redirectURI,
                "grant_type": "authorization_code",
            ])
            return (200, ["Content-Type": "application/json"], Data(#"{"access_token":"a","id_token":"jwt.id.token","token_type":"Bearer"}"#.utf8))
        }
        let callback = URL(string: "\(google.redirectURI)?state=\(request.state)&code=4/0A%2Bb%20c&scope=email")!
        #expect(try await google.idToken(for: request, callback: callback) == "jwt.id.token")
    }

    @Test func googleCallbackWithAnotherStateIsRejected() async {
        Stub.handler = { _ in Issue.record("no request expected"); return (500, [:], Data()) }
        let google = GoogleSignInService(session: stubbedSession)
        let request = google.makeRequest()
        await #expect(throws: GoogleSignInService.Failure.stateMismatch) {
            try await google.idToken(for: request, callback: URL(string: "\(google.redirectURI)?state=forged&code=x")!)
        }
    }

    @Test func googleErrorIsSurfaced() async {
        Stub.handler = { _ in Issue.record("no request expected"); return (500, [:], Data()) }
        let google = GoogleSignInService(session: stubbedSession)
        let request = google.makeRequest()
        await #expect(throws: GoogleSignInService.Failure.authorization("access_denied")) {
            try await google.idToken(for: request, callback: URL(string: "\(google.redirectURI)?state=\(request.state)&error=access_denied")!)
        }
    }

    @Test func refusedGoogleExchangeThrows() async {
        Stub.handler = { _ in (400, [:], Data(#"{"error":"invalid_grant"}"#.utf8)) }
        let google = GoogleSignInService(session: stubbedSession)
        let request = google.makeRequest()
        await #expect(throws: GoogleSignInService.Failure.tokenExchange(status: 400)) {
            try await google.idToken(for: request, callback: URL(string: "\(google.redirectURI)?state=\(request.state)&code=x")!)
        }
    }

    @Test func googleIDTokenStartsAKurzSession() async throws {
        Stub.handler = { req in
            #expect(req.url?.path == "/api/login/google")
            #expect(req.httpMethod == "POST")
            #expect(body(req) == #"{"credential":"jwt.id.token"}"#)
            return (200, ["Set-Cookie": "kurz_session=g1; path=/; httponly"], Data(userJSON.utf8))
        }
        let store = MemoryTokenStore()
        let user = try await service(store).signInWithGoogle(idToken: "jwt.id.token")
        #expect(user.email == "a@b.co")
        #expect(store.load() == "g1")
    }

    @Test(arguments: [
        (401, #"{"error":"google_invalid_token"}"#, APIError.server(status: 401, message: "google_invalid_token")),
        (401, #"{"error":"google_email_not_verified"}"#, APIError.server(status: 401, message: "google_email_not_verified")),
        (403, #"{"error":"Account deactivated"}"#, APIError.server(status: 403, message: "Account deactivated")),
        (404, "", APIError.server(status: 404, message: nil)),
    ])
    func googleBackendErrorsKeepTheirCode(status: Int, json: String, expected: APIError) async {
        Stub.handler = { _ in (status, [:], Data(json.utf8)) }
        let store = MemoryTokenStore()
        await #expect(throws: expected) { try await service(store).signInWithGoogle(idToken: "bad") }
        #expect(store.load() == nil)
    }
}
