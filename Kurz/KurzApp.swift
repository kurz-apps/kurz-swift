import Auth
import Domain
import FeatureAgenda
import Networking
import SwiftUI

@main struct KurzApp: App {
    @State private var session: SessionStore

    init() {
        let env = ProcessInfo.processInfo.environment
        let configuration = env["KURZ_API_URL"].flatMap(URL.init(string:)).map { APIConfiguration(baseURL: $0) } ?? .production
        let store: TokenStore = env["KURZ_FRESH_INSTALL"] == "1" ? MemoryTokenStore() : KeychainTokenStore()
        _session = State(initialValue: SessionStore(auth: AuthService(configuration: configuration, store: store)))
    }

    private var isSignedIn: Bool {
        if case .signedIn = session.state { true } else { false }
    }

    var body: some Scene {
        WindowGroup {
            ContentView(session: session)
        }
        .commands {
            SidebarCommands()
            AgendaCommands()
            CommandMenu("Account") {
                if case .signedIn(let user) = session.state {
                    Text(user.email)
                }
                Button("Sign out") { Task { await session.signOut() } }
                    .disabled(!isSignedIn)
            }
        }
        #if os(macOS)
        .windowToolbarStyle(.unified(showsTitle: false))
        .defaultSize(width: 590, height: 610)
        #endif
    }
}
