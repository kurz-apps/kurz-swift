import Foundation
import Networking
import Testing
@testable import FeatureAuth

struct LoginRulesTests {
    private let now = Date(timeIntervalSince1970: 1_000)

    @Test func countdownStartsAt45AndStopsAtZero() {
        let deadline = LoginRules.resendDeadline(from: now)
        #expect(LoginRules.resendRemaining(until: deadline, now: now) == 45)
        #expect(LoginRules.resendRemaining(until: deadline, now: now.addingTimeInterval(3)) == 42)
        #expect(LoginRules.resendRemaining(until: deadline, now: now.addingTimeInterval(44.2)) == 1)
        #expect(LoginRules.resendRemaining(until: deadline, now: now.addingTimeInterval(45)) == 0)
        #expect(LoginRules.resendRemaining(until: deadline, now: now.addingTimeInterval(500)) == 0)
    }

    @Test func retryAfterOverridesAndIsClamped() {
        #expect(LoginRules.resendRemaining(until: LoginRules.resendDeadline(from: now, retryAfter: 90), now: now) == 90)
        #expect(LoginRules.resendRemaining(until: LoginRules.resendDeadline(from: now, retryAfter: 86_400), now: now) == 300)
        #expect(LoginRules.resendRemaining(until: LoginRules.resendDeadline(from: now, retryAfter: 0), now: now) == 1)
    }

    @Test func emailProblemsGoUnderTheEmailField() {
        #expect(LoginRules.place(for: APIError.server(status: 422, message: "invalid_email"), default: .signIn) == .email)
        #expect(LoginRules.place(for: APIError.server(status: 422, message: "undeliverable_email"), default: .code) == .email)
        #expect(LoginRules.place(for: APIError.unauthorized, default: .signIn) == .signIn)
        #expect(LoginRules.place(for: APIError.rateLimited(retryAfter: 5), default: .google) == .google)
    }

    @Test func autofocusIsSkippedWhenTheViewIsShort() {
        #expect(LoginRules.shouldAutofocus(height: 667))
        #expect(LoginRules.shouldAutofocus(height: 1024))
        #expect(!LoginRules.shouldAutofocus(height: 402))
        #expect(!LoginRules.shouldAutofocus(height: 499))
    }
}
