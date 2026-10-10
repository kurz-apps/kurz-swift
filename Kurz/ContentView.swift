import AuthenticationServices
import SwiftUI

struct ContentView: View {
    @Environment(\.webAuthenticationSession) private var web
    @State private var model = AgendaModel()

    var body: some View {
        Group {
            switch model.signedIn {
            case nil: ProgressView()
            case false?: SignInView(model: model, login: login)
            case true?: AgendaView(model: model, login: login)
            }
        }
        .animation(.default, value: model.signedIn)
        .task { await model.start(login: login) }
    }

    private func login(_ url: URL) async throws -> URL {
        try await web.authenticate(using: url, callbackURLScheme: Kurz.scheme)
    }
}

struct SignInView: View {
    let model: AgendaModel
    let login: Login

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "calendar").font(.system(size: 56)).foregroundStyle(.tint).accessibilityHidden(true)
            Text("Your Kurz schedule").font(.largeTitle.bold()).multilineTextAlignment(.center)
            Text("Sign in to see your appointments. Access is read-only and the summary is generated on your device with Apple Intelligence.")
                .foregroundStyle(.secondary).multilineTextAlignment(.center)
            if let error = model.error { Text(error).font(.footnote).foregroundStyle(.red).multilineTextAlignment(.center) }
            Button {
                Task { await model.refresh(login: login) }
            } label: {
                Group { if model.isLoading { ProgressView() } else { Text("Sign in with Kurz") } }.frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).controlSize(.large).disabled(model.isLoading)
        }
        .padding(32)
        .frame(maxWidth: 420)
    }
}
