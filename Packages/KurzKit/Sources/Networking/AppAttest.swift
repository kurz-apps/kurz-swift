import CryptoKit
import Foundation
import Synchronization
#if canImport(DeviceCheck)
import DeviceCheck
#endif

public enum AppAttestError: Error, Equatable, Sendable {
    case invalidKey
    case serverUnavailable
    case rejected
}

public protocol AppAttesting: Sendable {
    var isSupported: Bool { get }
    func generateKey() async throws -> String
    func attestKey(_ keyId: String, clientDataHash: Data) async throws -> Data
    func generateAssertion(_ keyId: String, clientDataHash: Data) async throws -> Data
}

#if canImport(DeviceCheck)
@available(iOS 14.0, macOS 11.0, *)
public struct DeviceAppAttestor: AppAttesting {
    public init() {}

    public var isSupported: Bool { DCAppAttestService.shared.isSupported }

    public func generateKey() async throws -> String {
        try await mapped { try await DCAppAttestService.shared.generateKey() }
    }

    public func attestKey(_ keyId: String, clientDataHash: Data) async throws -> Data {
        try await mapped { try await DCAppAttestService.shared.attestKey(keyId, clientDataHash: clientDataHash) }
    }

    public func generateAssertion(_ keyId: String, clientDataHash: Data) async throws -> Data {
        try await mapped { try await DCAppAttestService.shared.generateAssertion(keyId, clientDataHash: clientDataHash) }
    }

    private func mapped<T>(_ work: () async throws -> T) async throws -> T {
        do { return try await work() } catch let error as DCError {
            switch error.code {
            case .invalidKey: throw AppAttestError.invalidKey
            case .serverUnavailable: throw AppAttestError.serverUnavailable
            default: throw error
            }
        }
    }
}
#endif

public final class MemoryAppAttestor: AppAttesting {
    public struct Calls: Sendable, Equatable {
        public var generated = 0
        public var attested: [Data] = []
        public var asserted: [Data] = []
    }

    public let isSupported: Bool
    private let state = Mutex((calls: Calls(), invalidKeys: Set<String>(), unavailable: 0))

    public init(isSupported: Bool = true) { self.isSupported = isSupported }

    public var calls: Calls { state.withLock { $0.calls } }
    public func invalidate(_ keyId: String) { state.withLock { _ = $0.invalidKeys.insert(keyId) } }
    public func failNext(unavailable count: Int) { state.withLock { $0.unavailable = count } }

    public func generateKey() async throws -> String {
        try state.withLock {
            try Self.check(&$0.unavailable)
            $0.calls.generated += 1
            return "key-\($0.calls.generated)"
        }
    }

    public func attestKey(_ keyId: String, clientDataHash: Data) async throws -> Data {
        try state.withLock {
            try Self.check(&$0.unavailable)
            if $0.invalidKeys.contains(keyId) { throw AppAttestError.invalidKey }
            $0.calls.attested.append(clientDataHash)
            return Data("attestation:\(keyId)".utf8)
        }
    }

    public func generateAssertion(_ keyId: String, clientDataHash: Data) async throws -> Data {
        try state.withLock {
            try Self.check(&$0.unavailable)
            if $0.invalidKeys.contains(keyId) { throw AppAttestError.invalidKey }
            $0.calls.asserted.append(clientDataHash)
            return Data("assertion:\(keyId):\($0.calls.asserted.count)".utf8)
        }
    }

    private static func check(_ unavailable: inout Int) throws {
        guard unavailable > 0 else { return }
        unavailable -= 1
        throw AppAttestError.serverUnavailable
    }
}

public actor AppAttestClient {
    public static let keyIdHeader = "X-Kurz-App-Key-Id"
    public static let challengeHeader = "X-Kurz-App-Challenge"
    public static let assertionHeader = "X-Kurz-App-Assertion"

    private let attestor: AppAttesting
    private let store: TokenStore
    private let api: APIClient
    private var registering: Task<String, Error>?

    public init(configuration: APIConfiguration, attestor: AppAttesting, store: TokenStore) {
        self.attestor = attestor
        self.store = store
        api = APIClient(configuration: configuration, token: { nil })
    }

    public func headers(for body: Data) async -> [String: String] {
        guard attestor.isSupported else { return [:] }
        do {
            return try await assert(body)
        } catch AppAttestError.invalidKey {
            store.clear()
            return (try? await assert(body)) ?? [:]
        } catch {
            return [:]
        }
    }

    public func reject(_ headers: [String: String]) {
        if let keyId = headers[Self.keyIdHeader], store.load() == keyId { store.clear() }
    }

    private func assert(_ body: Data) async throws -> [String: String] {
        let keyId = try await key()
        let (challenge, bytes) = try await fetchChallenge()
        let assertion = try await retrying { try await attestor.generateAssertion(keyId, clientDataHash: Data(SHA256.hash(data: bytes + body))) }
        return [Self.keyIdHeader: keyId, Self.challengeHeader: challenge, Self.assertionHeader: assertion.base64EncodedString()]
    }

    private func key() async throws -> String {
        if let keyId = store.load() { return keyId }
        if let registering { return try await registering.value }
        let task = Task { try await register() }
        registering = task
        defer { registering = nil }
        return try await task.value
    }

    private func register() async throws -> String {
        let keyId = try await retrying { try await attestor.generateKey() }
        let (challenge, bytes) = try await fetchChallenge()
        let attestation = try await retrying { try await attestor.attestKey(keyId, clientDataHash: Data(SHA256.hash(data: bytes))) }
        let body = ["key_id": keyId, "attestation": attestation.base64EncodedString(), "challenge": challenge]
        let (_, http) = try await api.unchecked(try .post("api/app/attest", json: body) as Endpoint<Empty>)
        guard (200..<300).contains(http.statusCode) else { throw AppAttestError.rejected }
        store.save(keyId)
        return keyId
    }

    private func fetchChallenge() async throws -> (String, Data) {
        let challenge = try await api.send(Endpoint<Challenge>("POST", "api/app/challenge")).challenge
        guard let bytes = Data(base64URLEncoded: challenge) else { throw APIError.invalidResponse }
        return (challenge, bytes)
    }

    private func retrying<T>(_ work: () async throws -> T) async throws -> T {
        do { return try await work() } catch AppAttestError.serverUnavailable { return try await work() }
    }

    private struct Challenge: Decodable, Sendable { var challenge: String }
    private struct Empty: Decodable, Sendable {}
}

extension Data {
    init?(base64URLEncoded string: String) {
        var base64 = string.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        self.init(base64Encoded: base64)
    }
}
