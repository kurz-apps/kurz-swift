import SwiftUI

public struct FormField<Trailing: View, Content: View>: View {
    let title: LocalizedStringKey
    let isFocused: Bool
    let trailing: Trailing
    let content: Content

    public init(_ title: LocalizedStringKey, isFocused: Bool, @ViewBuilder trailing: () -> Trailing = { EmptyView() }, @ViewBuilder content: () -> Content) {
        self.title = title
        self.isFocused = isFocused
        self.trailing = trailing()
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack { Text(title).font(.subheadline.weight(.medium)).foregroundStyle(Color.appForeground); Spacer(minLength: 8); trailing }
            content
                .textFieldStyle(.plain).foregroundStyle(Color.appForeground).tint(Color.appPrimary)
                .padding(12).background(Color.appBackground, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(isFocused ? Color.appRing : Color.appBorder, lineWidth: 1))
                .background { if isFocused { RoundedRectangle(cornerRadius: 10).stroke(Color.appRing.opacity(0.3), lineWidth: 6) } }
        }
    }
}

public extension View {
    func placeholder(_ text: String, when isEmpty: Bool) -> some View {
        overlay(alignment: .leading) {
            if isEmpty { Text(verbatim: text).foregroundStyle(Color.appPlaceholder).allowsHitTesting(false).accessibilityHidden(true) }
        }
    }
}

private struct FormFieldPreview: View {
    @State private var email = ""
    @State private var password = "secret"

    var body: some View {
        VStack(spacing: 16) {
            FormField("E-mail", isFocused: true) {
                TextField("E-mail", text: $email, prompt: Text(""))
                    .placeholder("do.you.know@university.kurz.fyi", when: email.isEmpty)
            }
            FormField("Password", isFocused: false, trailing: { Link("Forgot your password?", destination: URL(string: "https://kurz.fyi")!).font(.footnote.weight(.semibold)).foregroundStyle(Color.appForeground) }) {
                SecureField("", text: $password)
            }
        }
        .padding(24)
        .background(Color.appCard)
    }
}

#Preview("FormField · light") { FormFieldPreview().preferredColorScheme(.light) }

#Preview("FormField · dark") { FormFieldPreview().preferredColorScheme(.dark) }
