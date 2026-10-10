import Auth
import DesignSystem
import Domain
import FeatureAgenda
import FeatureAuth
import FeatureShell
import SwiftUI

struct ContentView: View {
    let session: SessionStore

    private var isSignedIn: Bool {
        if case .signedIn = session.state { true } else { false }
    }

    var body: some View {
        Group {
            switch session.state {
            case .launching: ProgressView()
            case .signedOut: LoginView(session: session)
            case .unreachable:
                ContentUnavailableView {
                    Label("Can't reach Kurz", systemImage: "wifi.exclamationmark")
                } description: {
                    Text("Check your connection and try again.")
                } actions: {
                    Button("Try again") { Task { await session.restore() } }.buttonStyle(.borderedProminent)
                }
            case .signedIn(let user):
                RootView(model: AgendaModel(api: session.auth.api), userEmail: user.email) { Task { await session.signOut() } }
            }
        }
        .tint(Color.appPrimary)
        #if os(macOS)
        .background(MacWindowSizing(isSignedIn: isSignedIn))
        #endif
        .animation(.default, value: session.state)
        .task { await session.restore() }
    }
}
