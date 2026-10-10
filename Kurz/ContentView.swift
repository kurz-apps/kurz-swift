import Auth
import Domain
import FeatureAgenda
import FeatureAuth
import SwiftUI

struct ContentView: View {
    let session: SessionStore

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
                AgendaView(model: AgendaModel(api: session.auth.api), userEmail: user.email) { Task { await session.signOut() } }
            }
        }
        .animation(.default, value: session.state)
        .task { await session.restore() }
    }
}
