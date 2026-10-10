import SwiftUI

public struct TextButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline)
            .foregroundStyle(Color.appPrimary)
            .opacity(isEnabled ? (configuration.isPressed ? 0.6 : 1) : 0.45)
    }
}

private struct TextButtonPreview: View {
    var body: some View {
        VStack(spacing: 16) {
            Button("Resend code") {}
            Button("Resend code") {}.disabled(true)
        }
        .buttonStyle(TextButtonStyle())
        .padding(24)
        .background(Color.appCard)
    }
}

#Preview("TextButtonStyle · light") { TextButtonPreview().preferredColorScheme(.light) }

#Preview("TextButtonStyle · dark") { TextButtonPreview().preferredColorScheme(.dark) }
