import Foundation
import Networking

enum LoginErrorPlace: Equatable {
    case google, email, signIn, sendCode, code
}

enum LoginRules {
    static let resendInterval: TimeInterval = 45
    static let maxRetryAfter: TimeInterval = 300
    static let minAutofocusHeight: CGFloat = 500

    static func shouldAutofocus(height: CGFloat) -> Bool { height >= minAutofocusHeight }

    static func resendDeadline(from now: Date, retryAfter: TimeInterval? = nil) -> Date {
        now.addingTimeInterval(retryAfter.map { min(max($0, 1), maxRetryAfter) } ?? resendInterval)
    }

    static func resendRemaining(until deadline: Date, now: Date) -> Int {
        max(0, Int(deadline.timeIntervalSince(now).rounded(.up)))
    }

    static func place(for error: Error, default place: LoginErrorPlace) -> LoginErrorPlace {
        switch error as? APIError {
        case .server(_, "invalid_email"), .server(_, "undeliverable_email"): .email
        default: place
        }
    }
}
