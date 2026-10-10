import Auth
import DesignSystem
import SwiftUI

public struct LoginView: View {
    let session: SessionStore
    @State private var email = ""
    @State private var code = ""
    @State private var codeSent = false
    @State private var isLoading = false
    @State private var error: String?
    @FocusState private var focus: Field?

    private static let codeLength = 7

    private enum Field { case email, code }

    public init(session: SessionStore) { self.session = session }

    public var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()
            LinearGradient(colors: [Color.appPrimary.opacity(0.35), .clear], startPoint: .topTrailing, endPoint: .center).ignoresSafeArea()
            VStack(spacing: 24) {
                Spacer(minLength: 0)
                Image(systemName: "calendar")
                    .font(.system(size: 34)).foregroundStyle(Color.appPrimary)
                    .frame(width: 72, height: 72).background(Color.appAccent, in: RoundedRectangle(cornerRadius: 20))
                    .accessibilityHidden(true)
                VStack(spacing: 8) {
                    Text("Welcome to Kurz").font(.largeTitle.bold()).foregroundStyle(Color.appForeground)
                    Text(codeSent ? "Enter the 7-digit code we sent to \(email)." : "Sign in with your e-mail. We'll send you a code, no password needed.")
                        .foregroundStyle(Color.appMutedForeground)
                }
                .multilineTextAlignment(.center)

                VStack(spacing: 16) {
                    Group {
                        if codeSent {
                            TextField("Code", text: $code)
                                .textContentType(.oneTimeCode).keyboard(.numberPad)
                                .focused($focus, equals: .code).accessibilityIdentifier("code-field")
                                .onChange(of: code) { _, new in if new.count >= Self.codeLength { Task { await verify() } } }
                        } else {
                            TextField("E-mail", text: $email)
                                .textContentType(.emailAddress).keyboard(.emailAddress).noAutocapitalization()
                                .autocorrectionDisabled()
                                .focused($focus, equals: .email).submitLabel(.go).onSubmit { Task { await send() } }
                                .accessibilityIdentifier("email-field")
                        }
                    }
                    .padding(14).background(Color.appBackground.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(focus == nil ? Color.appBorder : Color.appRing, lineWidth: 1))

                    if let error {
                        Text(error).font(.footnote).foregroundStyle(Color.appDestructive).accessibilityIdentifier("login-error")
                    }

                    let canSubmit = !isLoading && (codeSent ? code.count >= Self.codeLength : email.contains("@"))
                    Button { Task { await (codeSent ? verify() : send()) } } label: {
                        Group { if isLoading { ProgressView() } else { Text(codeSent ? "Sign in" : "Send code").fontWeight(.semibold) } }.frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent).tint(Color.appPrimary).controlSize(.large).disabled(!canSubmit)
                    .accessibilityIdentifier(codeSent ? "verify-button" : "send-code-button")

                    if codeSent {
                        Button("Use another e-mail") { codeSent = false; code = ""; error = nil }
                            .font(.subheadline).foregroundStyle(Color.appPrimary)
                    }
                }
                .padding(20)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24))
                Spacer(minLength: 0)
            }
            .padding(24)
            .frame(maxWidth: 440)
        }
        .onAppear { focus = .email }
        .animation(.default, value: codeSent)
    }

    private func send() async {
        isLoading = true; error = nil
        defer { isLoading = false }
        do {
            try await session.auth.requestCode(email: email.trimmingCharacters(in: .whitespaces).lowercased(), locale: Locale.current.language.languageCode?.identifier)
            codeSent = true
            focus = .code
        } catch {
            self.error = String(localized: "Couldn't send the code. Check the e-mail and try again.")
        }
    }

    private func verify() async {
        guard !isLoading else { return }
        isLoading = true; error = nil
        defer { isLoading = false }
        do {
            try await session.signIn(email: email.trimmingCharacters(in: .whitespaces).lowercased(), code: code)
        } catch {
            code = ""
            self.error = String(localized: "That code didn't work. Try again.")
        }
    }
}

private extension View {
    func keyboard(_ type: KeyboardKind) -> some View {
        #if os(iOS)
        keyboardType(type == .numberPad ? .numberPad : .emailAddress)
        #else
        self
        #endif
    }

    func noAutocapitalization() -> some View {
        #if os(iOS)
        textInputAutocapitalization(.never)
        #else
        self
        #endif
    }
}

private enum KeyboardKind { case numberPad, emailAddress }
