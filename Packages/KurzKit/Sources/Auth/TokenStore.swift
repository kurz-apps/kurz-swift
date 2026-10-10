import Foundation
import Security
import Synchronization

public protocol TokenStore: Sendable {
    func load() -> String?
    func save(_ token: String)
    func clear()
}

public struct KeychainTokenStore: TokenStore {
    private let service: String
    private let account: String

    public init(service: String = "fyi.kurz.app", account: String = "session") {
        self.service = service
        self.account = account
    }

    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    }

    public func load() -> String? {
        var out: AnyObject?
        let q = query.merging([kSecReturnData as String: true]) { $1 }
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public func save(_ token: String) {
        clear()
        let attrs: [String: Any] = [kSecValueData as String: Data(token.utf8), kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock]
        SecItemAdd(query.merging(attrs) { $1 } as CFDictionary, nil)
    }

    public func clear() { SecItemDelete(query as CFDictionary) }
}

public final class MemoryTokenStore: TokenStore {
    private let value: Mutex<String?>
    public init(_ token: String? = nil) { value = Mutex(token) }
    public func load() -> String? { value.withLock { $0 } }
    public func save(_ token: String) { value.withLock { $0 = token } }
    public func clear() { value.withLock { $0 = nil } }
}
