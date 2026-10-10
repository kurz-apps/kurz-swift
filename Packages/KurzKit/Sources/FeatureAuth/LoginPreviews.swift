import Auth
import Networking
import SwiftUI

@MainActor private func previewSession() -> SessionStore {
    SessionStore(auth: AuthService(configuration: APIConfiguration(baseURL: URL(string: "http://localhost:3000")!), store: MemoryTokenStore()))
}

#Preview("Login") {
    LoginView(session: previewSession())
}

#Preview("Login · dark") {
    LoginView(session: previewSession()).preferredColorScheme(.dark)
}

#Preview("Login · light") {
    LoginView(session: previewSession()).preferredColorScheme(.light)
}

#Preview("Login · pt-PT") {
    LoginView(session: previewSession()).environment(\.locale, Locale(identifier: "pt-PT"))
}

#Preview("Login · large text") {
    LoginView(session: previewSession()).dynamicTypeSize(.accessibility2)
}

private extension LoginView {
    @MainActor static func preview(codeSent: Bool = false, email: String = "", password: String = "", error: LoginView.LoginError? = nil, showsPassword: Bool = false, resendDeadline: Date? = nil) -> LoginView {
        LoginView(session: previewSession(), email: email, password: password, codeSent: codeSent, error: error, showsPassword: showsPassword, resendDeadline: resendDeadline)
    }
}

#Preview("Login · password collapsed") {
    LoginView.preview()
}

#Preview("Login · sign-in error") {
    LoginView.preview(email: "ana@university.kurz.fyi", password: "secret", error: .init(message: "Wrong e-mail or password. Too many attempts pause password sign-in for a while.", place: .signIn))
}

#Preview("Login · e-mail error") {
    LoginView.preview(email: "ana@", error: .init(message: "That doesn't look like a valid e-mail address.", place: .email))
}

#Preview("Login · password visible") {
    LoginView.preview(email: "ana@university.kurz.fyi", password: "correct horse", showsPassword: true)
}

#Preview("Login · resend countdown") {
    LoginView.preview(codeSent: true, email: "ana@university.kurz.fyi", resendDeadline: .now.addingTimeInterval(42))
}

#Preview("Login · error, large text") {
    LoginView.preview(email: "ana@university.kurz.fyi", password: "secret", error: .init(message: "Wrong e-mail or password. Too many attempts pause password sign-in for a while.", place: .signIn)).dynamicTypeSize(.accessibility2)
}
