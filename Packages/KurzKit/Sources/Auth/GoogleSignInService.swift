import CryptoKit
import Foundation

public struct GoogleSignInService: Sendable {
    public enum Failure: Error, Equatable, Sendable {
        case stateMismatch
        case authorization(String)
        case missingCode
        case tokenExchange(status: Int)
        case missingIDToken
    }

    public struct Request: Sendable {
        public let url: URL
        public let state: String
        public let verifier: String
    }

    public static let authorizationEndpoint = URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!
    public static let tokenEndpoint = URL(string: "https://oauth2.googleapis.com/token")!

    public let clientID: String
    public let callbackScheme: String
    private let session: URLSession

    public init(
        clientID: String = "146729417680-0b8olcohquir6qghpblo0s0oq45siqca.apps.googleusercontent.com",
        callbackScheme: String = "com.googleusercontent.apps.146729417680-0b8olcohquir6qghpblo0s0oq45siqca",
        session: URLSession = .shared
    ) {
        self.clientID = clientID
        self.callbackScheme = callbackScheme
        self.session = session
    }

    public var redirectURI: String { "\(callbackScheme):/oauth2redirect" }

    public func makeRequest() -> Request {
        let state = Self.randomToken()
        let verifier = Self.randomToken()
        var url = URLComponents(url: Self.authorizationEndpoint, resolvingAgainstBaseURL: false)!
        url.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: "openid email profile"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: Self.challenge(for: verifier)),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "prompt", value: "select_account"),
        ]
        return Request(url: url.url!, state: state, verifier: verifier)
    }

    public func idToken(for request: Request, callback: URL) async throws -> String {
        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let value = { (name: String) in items.first { $0.name == name }?.value }
        guard value("state") == request.state else { throw Failure.stateMismatch }
        if let error = value("error") { throw Failure.authorization(error) }
        guard let code = value("code"), !code.isEmpty else { throw Failure.missingCode }

        var form = URLComponents()
        form.queryItems = [
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "code_verifier", value: request.verifier),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "grant_type", value: "authorization_code"),
        ]
        var post = URLRequest(url: Self.tokenEndpoint)
        post.httpMethod = "POST"
        post.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        post.httpBody = Data((form.percentEncodedQuery ?? "").replacingOccurrences(of: "+", with: "%2B").utf8)

        let (data, response) = try await session.data(for: post)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw Failure.tokenExchange(status: status) }
        guard let token = (try? JSONDecoder().decode(TokenResponse.self, from: data))?.id_token, !token.isEmpty else { throw Failure.missingIDToken }
        return token
    }

    static func challenge(for verifier: String) -> String {
        base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    private static func randomToken() -> String {
        var generator = SystemRandomNumberGenerator()
        return base64URL(Data((0..<32).map { _ in UInt8.random(in: .min ... .max, using: &generator) }))
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }

    private struct TokenResponse: Decodable {
        let id_token: String?
    }
}
