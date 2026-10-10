import Auth
import Networking
import SwiftUI

@main struct KurzApp: App {
    @State private var session: SessionStore

    init() {
        let env = ProcessInfo.processInfo.environment
        let configuration = env["KURZ_API_URL"].flatMap(URL.init(string:)).map { APIConfiguration(baseURL: $0) } ?? .production
        let store: TokenStore = env["KURZ_FRESH_INSTALL"] == "1" ? MemoryTokenStore() : KeychainTokenStore()
        let attest = AppAttestClient(configuration: configuration, attestor: DeviceAppAttestor(), store: KeychainTokenStore(account: "app-attest-key"))
        _session = State(initialValue: SessionStore(auth: AuthService(configuration: configuration, store: store, attest: attest)))
    }

    var body: some Scene {
        WindowGroup {
            ContentView(session: session)
        }
        #if os(macOS)
        .windowToolbarStyle(.unified(showsTitle: false))
        #endif
    }
}
