import SwiftUI

public struct LoadFailedView: View {
    let title: LocalizedStringKey
    let message: String
    let retry: () -> Void

    public init(_ title: LocalizedStringKey, message: String, retry: @escaping () -> Void) {
        self.title = title
        self.message = message
        self.retry = retry
    }

    public var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: "calendar.badge.exclamationmark")
        } description: {
            Text(message)
        } actions: {
            Button("Try again", action: retry).buttonStyle(.glassProminent).tint(Color.appPrimary)
        }
    }
}

#Preview("LoadFailedView · light") {
    LoadFailedView("Couldn't load your agenda", message: "The server is unreachable.") {}
        .background(Color.appBackground)
        .preferredColorScheme(.light)
}

#Preview("LoadFailedView · dark") {
    LoadFailedView("Couldn't load your agenda", message: "The server is unreachable.") {}
        .background(Color.appBackground)
        .preferredColorScheme(.dark)
}
