import Foundation

public enum APIError: Error, Equatable, Sendable {
    case unauthorized
    case server(status: Int, message: String?)
    case invalidResponse
}

public struct Endpoint<Response: Decodable & Sendable>: Sendable {
    public var method: String
    public var path: String
    public var query: [URLQueryItem]
    public var body: Data?

    public init(_ method: String = "GET", _ path: String, query: [URLQueryItem] = [], body: Data? = nil) {
        self.method = method
        self.path = path
        self.query = query
        self.body = body
    }

    public static func post(_ path: String, json: some Encodable) throws -> Endpoint {
        Endpoint("POST", path, body: try JSONEncoder().encode(json))
    }
}

public struct APIConfiguration: Sendable {
    public var baseURL: URL
    public var session: URLSession

    public init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    public static let production = APIConfiguration(baseURL: URL(string: "https://api.kurz.fyi")!)
}

public struct APIClient: Sendable {
    public var configuration: APIConfiguration
    public var token: @Sendable () async -> String?
    public var attest: AppAttestClient?

    public static let attestedPaths: Set<String> = ["api/login_request", "api/login/password", "api/signup", "api/password/forgot", "api/password/reset"]

    public init(configuration: APIConfiguration, attest: AppAttestClient? = nil, token: @escaping @Sendable () async -> String?) {
        self.configuration = configuration
        self.attest = attest
        self.token = token
    }

    public func send<R>(_ endpoint: Endpoint<R>) async throws -> R {
        let (data, _) = try await raw(endpoint)
        do { return try Self.decoder.decode(R.self, from: data) } catch { throw APIError.invalidResponse }
    }

    public func raw<R>(_ endpoint: Endpoint<R>) async throws -> (Data, HTTPURLResponse) {
        let (data, http) = try await unchecked(endpoint)
        switch http.statusCode {
        case 200..<300: return (data, http)
        case 401: throw APIError.unauthorized
        default: throw APIError.server(status: http.statusCode, message: Self.message(in: data))
        }
    }

    public func unchecked<R>(_ endpoint: Endpoint<R>) async throws -> (Data, HTTPURLResponse) {
        guard var url = URLComponents(url: configuration.baseURL.appending(path: endpoint.path), resolvingAgainstBaseURL: false) else {
            throw APIError.invalidResponse
        }
        if !endpoint.query.isEmpty { url.queryItems = endpoint.query }
        var request = URLRequest(url: url.url!)
        request.httpMethod = endpoint.method
        request.httpBody = endpoint.body
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if endpoint.body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        request.httpShouldHandleCookies = false
        if let token = await token() { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }

        guard let attest, Self.attestedPaths.contains(endpoint.path) else { return try await load(request) }
        var headers = await attest.headers(for: request.httpBody ?? Data())
        var response = try await load(request, headers)
        if !headers.isEmpty, [400, 401, 403].contains(response.1.statusCode), ["invalid_attestation", "captcha_failed"].contains(Self.message(in: response.0)) {
            await attest.reject(headers)
            headers = await attest.headers(for: request.httpBody ?? Data())
            if !headers.isEmpty { response = try await load(request, headers) }
        }
        return response
    }

    private func load(_ request: URLRequest, _ headers: [String: String] = [:]) async throws -> (Data, HTTPURLResponse) {
        var request = request
        for (field, value) in headers { request.setValue(value, forHTTPHeaderField: field) }
        let (data, response) = try await configuration.session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        return (data, http)
    }

    public static func message(in data: Data) -> String? {
        (try? JSONSerialization.jsonObject(with: data) as? [String: Any]).flatMap { $0["error"] as? String ?? $0["message"] as? String }
    }

    public static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}

public extension HTTPURLResponse {
    var sessionToken: String? {
        let fields = allHeaderFields.reduce(into: [String: String]()) { if let k = $1.key as? String, let v = $1.value as? String { $0[k] = v } }
        guard let url else { return nil }
        return HTTPCookie.cookies(withResponseHeaderFields: fields, for: url).first { $0.name == "kurz_session" }?.value
    }
}
