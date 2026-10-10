import AuthenticationServices
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
    @State private var isGoogleLoading = false
    @State private var error: LocalizedStringKey?
    @FocusState private var focus: Field?
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession

    private static let codeLength = 7
    private static let webURL = URL(string: "https://kurz.fyi")!
    private static let google = GoogleSignInService()

    private enum Field { case email, password, code }

    public init(session: SessionStore) { self.session = session }

    public var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 24) {
                    KurzLogo(size: 56)
                    header
                    VStack(spacing: 16) {
                        if codeSent { codeStep } else { googleStep; credentialsStep }
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

    @ViewBuilder private var googleStep: some View {
        Button { Task { await signInWithGoogle() } } label: {
            HStack(spacing: 10) {
                if isGoogleLoading { ProgressView().controlSize(.small) } else { GoogleMark().frame(width: 18, height: 18) }
                Text("Continue with Google")
            }
        }
        .buttonStyle(OutlineButtonStyle()).disabled(isLoading)
        .accessibilityIdentifier("google-button")
        LabeledDivider("or", titleIdentifier: "login-divider")
    }

    @ViewBuilder private var credentialsStep: some View {
        FormField("E-mail", isFocused: focus == .email) {
            TextField("E-mail", text: $email, prompt: Text(""))
                .placeholder("do.you.know@university.kurz.fyi", when: email.isEmpty)
                .textContentType(.emailAddress).keyboard(.emailAddress).noAutocapitalization().autocorrectionDisabled()
                .focused($focus, equals: .email).submitLabel(emailReady ? .next : .done).onSubmit { if emailReady { focus = .password } }
                .accessibilityIdentifier("email-field")
        }
        if emailReady {
            FormField("Password", isFocused: focus == .password, trailing: { Link("Forgot your password?", destination: Self.webURL.appending(path: "password/forgot")).font(.footnote.weight(.semibold)).foregroundStyle(Color.appForeground) }) {
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
            .buttonStyle(TextButtonStyle()).disabled(isLoading)
            .accessibilityIdentifier("send-code-button")
    }

    @ViewBuilder private var codeStep: some View {
        FormField("Code", isFocused: focus == .code) {
            TextField("Code", text: $code, prompt: Text(""))
                .placeholder("0000000", when: code.isEmpty)
                .textContentType(.oneTimeCode).keyboard(.numberPad)
                .focused($focus, equals: .code).accessibilityIdentifier("code-field")
                .onChange(of: code) { _, new in if new.count >= Self.codeLength { Task { await verifyCode() } } }
        }
        Button { Task { await verifyCode() } } label: { label("Verify and sign in") }
            .buttonStyle(PrimaryButtonStyle()).disabled(isLoading || code.count < Self.codeLength)
            .accessibilityIdentifier("verify-button")
        Button("Resend code") { Task { await sendCode() } }
            .buttonStyle(TextButtonStyle()).disabled(isLoading)
        Button("Use another e-mail") { codeSent = false; code = ""; error = nil }
            .buttonStyle(TextButtonStyle())
    }

    private var emailReady: Bool { normalizedEmail.wholeMatch(of: /[^\s@]+@[^\s@]+\.[^\s@]+/) != nil }
    private var normalizedEmail: String { email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }

    private func label(_ title: LocalizedStringKey) -> some View {
        Group { if isLoading && !isGoogleLoading { Text("Signing in…").fontWeight(.semibold) } else { Text(title).fontWeight(.semibold) } }.frame(maxWidth: .infinity)
    }

    private func perform(_ describe: @escaping (Error) -> LocalizedStringKey?, _ work: () async throws -> Void) async {
        guard !isLoading else { return }
        isLoading = true
        error = nil
        defer { isLoading = false }
        do { try await work() } catch { self.error = describe(error) }
    }

    private func signInWithPassword() async {
        await perform({ failure($0, unauthorized: "Wrong e-mail or password. Too many attempts pause password sign-in for a while.") }) { try await session.signIn(email: normalizedEmail, password: password) }
    }

    private func signInWithGoogle() async {
        isGoogleLoading = true
        defer { isGoogleLoading = false }
        await perform(googleFailure) {
            let request = Self.google.makeRequest()
            let callback = try await webAuthenticationSession.authenticate(using: request.url, callback: .customScheme(Self.google.callbackScheme), additionalHeaderFields: [:])
            try await session.signInWithGoogle(idToken: try await Self.google.idToken(for: request, callback: callback))
        }
    }

    private func googleFailure(_ error: Error) -> LocalizedStringKey? {
        if error is CancellationError || (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin { return nil }
        if error is GoogleSignInService.Failure { return "Google sign-in did not go through. Please try again." }
        if case .server(404, _) = error as? APIError { return "Google sign-in isn't available right now." }
        return failure(error, unauthorized: "Google sign-in did not go through. Please try again.")
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
        case .server(403, _): return "Your account has been deactivated. Contact support if you believe this is a mistake."
        case .server(_, "google_invalid_token"): return "Google sign-in did not go through. Please try again."
        case .server(_, "google_email_not_verified"): return "Your Google account e-mail is not verified yet, so it can't be used to sign in."
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

private struct GoogleMark: View {
    var body: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)
            let line = size * 0.2
            ZStack {
                arc(0, 0.125, 0x4285F4, line)
                arc(0.125, 0.375, 0x34A853, line)
                arc(0.375, 0.6, 0xFBBC05, line)
                arc(0.6, 0.875, 0xEA4335, line)
                Rectangle().fill(Color(hex: 0x4285F4)).frame(width: size / 2, height: line).offset(x: size / 4)
            }
            .padding(line / 2)
            .frame(width: size, height: size)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }

    private func arc(_ from: CGFloat, _ to: CGFloat, _ hex: UInt32, _ line: CGFloat) -> some View {
        Circle().trim(from: from, to: to).stroke(Color(hex: hex), style: StrokeStyle(lineWidth: line))
    }
}
