import DesignSystem
import Domain
import FeatureAgenda
import SwiftUI

public struct RootView: View {
    enum Destination: Hashable { case agenda, pending }

    let model: AgendaModel
    let userEmail: String
    let signOut: () -> Void
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var selection: Destination? = .agenda

    public init(model: AgendaModel, userEmail: String, signOut: @escaping () -> Void) {
        self.model = model
        self.userEmail = userEmail
        self.signOut = signOut
    }

    public var body: some View {
        if sizeClass == .compact {
            AgendaView(model: model, userEmail: userEmail, signOut: signOut)
        } else {
            NavigationSplitView {
                List(selection: $selection) {
                    Label("Agenda", systemImage: "calendar").tag(Destination.agenda)
                    Label("Pending approval", systemImage: "clock.badge.questionmark").tag(Destination.pending)
                        .badge(count)
                }
                .navigationTitle("Kurz")
                .safeAreaInset(edge: .bottom) { account }
            } detail: {
                switch selection ?? .agenda {
                case .agenda: AgendaView(model: model, userEmail: userEmail, signOut: signOut)
                case .pending: PendingView(model: model)
                }
            }
            .tint(Color.appPrimary)
            .task { await model.refresh() }
        }
    }

    private var count: Int {
        if case .loaded(let agenda) = model.phase { pendingCount(in: agenda) } else { 0 }
    }

    private var account: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(userEmail, systemImage: "person.crop.circle").font(.footnote).foregroundStyle(Color.appMutedForeground).lineLimit(1)
            Button("Sign out", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive, action: signOut)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.bar)
    }
}
