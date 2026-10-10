import Domain
import Foundation
import Observation

@MainActor @Observable
public final class SessionStore {
    public enum State: Equatable { case launching, signedOut, unreachable, signedIn(CurrentUser) }

    public private(set) var state = State.launching
    public let auth: AuthService

    public init(auth: AuthService) { self.auth = auth }

    public func restore() async {
        do {
            state = try await auth.currentUser().map(State.signedIn) ?? .signedOut
        } catch {
            state = .unreachable
        }
    }

    public func signIn(email: String, code: String) async throws {
        state = .signedIn(try await auth.verify(email: email, code: code))
    }

    public func signIn(email: String, password: String) async throws {
        state = .signedIn(try await auth.signIn(email: email, password: password))
    }

    public func signOut() async {
        await auth.signOut()
        state = .signedOut
    }
}
