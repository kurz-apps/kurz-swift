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
