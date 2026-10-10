import Foundation

/// GET /api/me, and the body of every successful login.
public struct CurrentUser: Codable, Sendable, Equatable, Identifiable {
    public var id: Int
    public var email: String
    public var admin: Bool
    public var timeZone: String
    public var locale: String?
    public var hasPassword: Bool
    public var googleConnected: Bool
}

public struct UserEnvelope: Codable, Sendable, Equatable {
    public var user: CurrentUser
}
