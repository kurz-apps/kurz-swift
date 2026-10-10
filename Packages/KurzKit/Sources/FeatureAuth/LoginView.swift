import Auth
import DesignSystem
import Networking
import SwiftUI

public struct LoginView: View {
    let session: SessionStore
    @State private var email = ""
    @State private var password = ""
    @State private var code = ""
    @State private var codeSent = false
    @State private var isLoading = false
    @State private var error: LocalizedStringKey?
    @FocusState private var focus: Field?

    private static let codeLength = 7
    private static let webURL = URL(string: "https://kurz.fyi")!

    private enum Field { case email, password, code }

    public init(session: SessionStore) { self.session = session }

    public var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()
            VStack(spacing: 20) {
                Spacer(minLength: 0)
                KurzLogo(size: 64)
                VStack(spacing: 6) {
                    Text(codeSent ? "Check your e-mail" : "Sign in to Kurz").font(.title2.weight(.semibold)).foregroundStyle(Color.appForeground)
                    if codeSent {
                        Text("We sent a 7-digit code to \(email)").foregroundStyle(Color.appMutedForeground)
                    } else {
                        HStack(spacing: 4) {
                            Text("Don't have an account yet?").foregroundStyle(Color.appMutedForeground)
                            Link("Create account", destination: Self.webURL.appending(path: "signup")).foregroundStyle(Color.appForeground).underline()
                        }
                    }
                }
                .font(.subheadline).multilineTextAlignment(.center)

                VStack(spacing: 16) {
                    if codeSent { codeStep } else { credentialsStep }
                    if let error { Text(error).font(.footnote).foregroundStyle(Color.appDestructive).accessibilityIdentifier("login-error") }
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

    @ViewBuilder private var credentialsStep: some View {
        field("E-mail") {
            TextField("you@example.com", text: $email)
                .textContentType(.emailAddress).keyboard(.emailAddress).noAutocapitalization().autocorrectionDisabled()
                .focused($focus, equals: .email).submitLabel(.next).onSubmit { focus = .password }
                .accessibilityIdentifier("email-field")
        }
        field("Password", trailing: { Link("Forgot your password?", destination: Self.webURL.appending(path: "password/forgot")).font(.footnote).foregroundStyle(Color.appMutedForeground) }) {
            SecureField("Password", text: $password)
                .textContentType(.password)
                .focused($focus, equals: .password).submitLabel(.go).onSubmit { Task { await signInWithPassword() } }
                .accessibilityIdentifier("password-field")
        }
        let canSignIn = !isLoading && emailLooksValid && !password.isEmpty
        Button { Task { await signInWithPassword() } } label: { label("Sign in") }
            .buttonStyle(.glassProminent).tint(Color.appPrimary).controlSize(.large).disabled(!canSignIn)
            .accessibilityIdentifier("login-button")
        Button { Task { await sendCode() } } label: { Label("E-mail me a code", systemImage: "envelope") }
            .font(.subheadline).foregroundStyle(Color.appPrimary).disabled(isLoading || !emailLooksValid)
            .accessibilityIdentifier("send-code-button")
    }

    @ViewBuilder private var codeStep: some View {
        field("Code") {
            TextField("0000000", text: $code)
                .textContentType(.oneTimeCode).keyboard(.numberPad)
                .focused($focus, equals: .code).accessibilityIdentifier("code-field")
                .onChange(of: code) { _, new in if new.count >= Self.codeLength { Task { await verifyCode() } } }
        }
        Button { Task { await verifyCode() } } label: { label("Verify and sign in") }
            .buttonStyle(.glassProminent).tint(Color.appPrimary).controlSize(.large).disabled(isLoading || code.count < Self.codeLength)
            .accessibilityIdentifier("verify-button")
        Button("Use another e-mail") { codeSent = false; code = ""; error = nil }
            .font(.subheadline).foregroundStyle(Color.appPrimary)
    }

    private var emailLooksValid: Bool { email.contains("@") && email.contains(".") }
    private var normalizedEmail: String { email.trimmingCharacters(in: .whitespaces).lowercased() }

    private func label(_ title: LocalizedStringKey) -> some View {
        Group { if isLoading { ProgressView() } else { Text(title).fontWeight(.semibold) } }.frame(maxWidth: .infinity)
    }

    private func field<Content: View>(_ title: LocalizedStringKey, @ViewBuilder trailing: () -> some View = { EmptyView() }, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack { Text(title).font(.subheadline.weight(.medium)).foregroundStyle(Color.appForeground); Spacer(); trailing() }
            content()
                .padding(12).background(Color.appBackground.opacity(0.6), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.appBorder, lineWidth: 1))
        }
    }

    private func perform(_ failure: @escaping (Error) -> LocalizedStringKey, _ work: () async throws -> Void) async {
        guard !isLoading else { return }
        isLoading = true
        error = nil
        defer { isLoading = false }
        do { try await work() } catch { self.error = failure(error) }
    }

    private func signInWithPassword() async {
        await perform({ _ in "Wrong e-mail or password." }) { try await session.signIn(email: normalizedEmail, password: password) }
    }

    private func sendCode() async {
        await perform({ _ in "Couldn't send the code. Check the e-mail and try again." }) {
            try await session.auth.requestCode(email: normalizedEmail, locale: Locale.current.language.languageCode?.identifier)
            codeSent = true
            focus = .code
        }
    }

    private func verifyCode() async {
        await perform({ _ in code = ""; return "That code is wrong or expired." }) { try await session.signIn(email: normalizedEmail, code: code) }
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
