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
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 24) {
                    KurzLogo(size: 56)
                    header
                    VStack(spacing: 16) {
                        if codeSent { codeStep } else { credentialsStep }
                        if let error {
                            Text(error).font(.footnote).foregroundStyle(Color.appDestructive).multilineTextAlignment(.center)
                                .accessibilityIdentifier("login-error")
                        }
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity)
                    .background(Color.appCard, in: RoundedRectangle(cornerRadius: 20))
                    .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.appBorder, lineWidth: 1))
                    .shadow(color: .black.opacity(0.08), radius: 16, y: 6)
                }
                .padding(24)
                .frame(maxWidth: 420)
                .frame(maxWidth: .infinity, minHeight: geometry.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.interactively)
        }
        .background(Color.appBackground.ignoresSafeArea())
        .onAppear { focus = .email }
        .animation(.default, value: codeSent)
        .animation(.default, value: emailReady)
    }

    private var header: some View {
        VStack(spacing: 8) {
            Text(codeSent ? "Check your e-mail" : "Sign in to Kurz").font(.title2.bold()).foregroundStyle(Color.appForeground)
            Group {
                if codeSent {
                    Text("We sent a 7-digit code to \(email)")
                } else {
                    Text("Don't have an account yet?") + Text(" ") + Text(createAccountLink) + Text(".")
                }
            }
            .font(.subheadline).foregroundStyle(Color.appMutedForeground)
        }
        .multilineTextAlignment(.center)
    }

    private var createAccountLink: AttributedString {
        var link = AttributedString(String(localized: "Create account"))
        link.link = Self.webURL.appending(path: "signup")
        link.font = .subheadline.bold()
        link.underlineStyle = .single
        link.foregroundColor = Color.appPrimary
        return link
    }

    @ViewBuilder private var credentialsStep: some View {
        field("E-mail", focusOn: .email) {
            TextField("do.you.know@university.kurz.fyi", text: $email)
                .textContentType(.emailAddress).keyboard(.emailAddress).noAutocapitalization().autocorrectionDisabled()
                .focused($focus, equals: .email).submitLabel(emailReady ? .next : .done).onSubmit { if emailReady { focus = .password } }
                .accessibilityIdentifier("email-field")
        }
        if emailReady {
            field("Password", focusOn: .password, trailing: { Link("Forgot your password?", destination: Self.webURL.appending(path: "password/forgot")).font(.footnote.weight(.semibold)).foregroundStyle(Color.appForeground) }) {
                SecureField("", text: $password)
                    .textContentType(.password)
                    .focused($focus, equals: .password).submitLabel(.go).onSubmit { Task { await signInWithPassword() } }
                    .accessibilityIdentifier("password-field")
            }
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
        Button { Task { await signInWithPassword() } } label: { label("Sign in") }
            .buttonStyle(PrimaryButtonStyle()).disabled(isLoading || !emailReady || password.isEmpty)
            .accessibilityIdentifier("login-button")
        Button { requestCode() } label: { Label("E-mail me a code", systemImage: "envelope").fontWeight(.medium) }
            .buttonStyle(.plain).font(.subheadline).foregroundStyle(Color.appPrimary).opacity(isLoading ? 0.45 : 1).disabled(isLoading)
            .accessibilityIdentifier("send-code-button")
    }

    @ViewBuilder private var codeStep: some View {
        field("Code", focusOn: .code) {
            TextField("0000000", text: $code)
                .textContentType(.oneTimeCode).keyboard(.numberPad)
                .focused($focus, equals: .code).accessibilityIdentifier("code-field")
                .onChange(of: code) { _, new in if new.count >= Self.codeLength { Task { await verifyCode() } } }
        }
        Button { Task { await verifyCode() } } label: { label("Verify and sign in") }
            .buttonStyle(PrimaryButtonStyle()).disabled(isLoading || code.count < Self.codeLength)
            .accessibilityIdentifier("verify-button")
        Button("Resend code") { Task { await sendCode() } }
            .buttonStyle(.plain).font(.subheadline).foregroundStyle(Color.appPrimary).opacity(isLoading ? 0.45 : 1).disabled(isLoading)
        Button("Use another e-mail") { codeSent = false; code = ""; error = nil }
            .buttonStyle(.plain).font(.subheadline).foregroundStyle(Color.appPrimary)
    }

    private var emailReady: Bool { normalizedEmail.wholeMatch(of: /[^\s@]+@[^\s@]+\.[^\s@]+/) != nil }
    private var normalizedEmail: String { email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }

    private func label(_ title: LocalizedStringKey) -> some View {
        Group { if isLoading { Text("Signing in…").fontWeight(.semibold) } else { Text(title).fontWeight(.semibold) } }.frame(maxWidth: .infinity)
    }

    private func field<Content: View>(_ title: LocalizedStringKey, focusOn: Field, @ViewBuilder trailing: () -> some View = { EmptyView() }, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack { Text(title).font(.subheadline.weight(.medium)).foregroundStyle(Color.appForeground); Spacer(minLength: 8); trailing() }
            content()
                .textFieldStyle(.plain).foregroundStyle(Color.appForeground).tint(Color.appPrimary)
                .padding(12).background(Color.appBackground, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(focus == focusOn ? Color.appRing : Color.appBorder, lineWidth: 1))
                .background { if focus == focusOn { RoundedRectangle(cornerRadius: 10).stroke(Color.appRing.opacity(0.3), lineWidth: 6) } }
        }
    }

    private func perform(_ describe: @escaping (Error) -> LocalizedStringKey, _ work: () async throws -> Void) async {
        guard !isLoading else { return }
        isLoading = true
        error = nil
        defer { isLoading = false }
        do { try await work() } catch { self.error = describe(error) }
    }

    private func signInWithPassword() async {
        await perform({ failure($0, unauthorized: "Wrong e-mail or password. Too many attempts pause password sign-in for a while.") }) { try await session.signIn(email: normalizedEmail, password: password) }
    }

    private func requestCode() {
        guard emailReady else { error = "Enter your e-mail first, then we send you a code."; return }
        Task { await sendCode() }
    }

    private func failure(_ error: Error, unauthorized: LocalizedStringKey) -> LocalizedStringKey {
        guard let api = error as? APIError else { return "Something went wrong, please try again later." }
        switch api {
        case .unauthorized: return unauthorized
        case .server(429, _): return "Too many attempts. Please wait a few minutes and try again."
        case .server(_, "invalid_email"): return "That doesn't look like a valid e-mail address."
        case .server(_, "undeliverable_email"): return "We can't send e-mails to that address. Temporary and disposable addresses aren't accepted."
        case .server(_, "new_address_limit"): return "New sign-ups are paused for today. If you already have an account, you can still sign in."
        case .server(_, "daily_limit"), .server(_, "monthly_limit"): return "Kurz has sent all the e-mails it can for now. Please try again later."
        case .server(_, "invalid_credentials"): return "Wrong e-mail or password. Too many attempts pause password sign-in for a while."
        case .server(_, "invalid_code"): return "That code is wrong or expired. Request a new one if needed."
        default: return "Something went wrong, please try again later."
        }
    }

    private func sendCode() async {
        await perform({ failure($0, unauthorized: "Something went wrong, please try again later.") }) {
            try await session.auth.requestCode(email: normalizedEmail, locale: Locale.current.language.languageCode?.identifier)
            codeSent = true
            focus = .code
        }
    }

    private func verifyCode() async {
        await perform({ code = ""; return failure($0, unauthorized: "That code is wrong or expired. Request a new one if needed.") }) { try await session.signIn(email: normalizedEmail, code: code) }
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
