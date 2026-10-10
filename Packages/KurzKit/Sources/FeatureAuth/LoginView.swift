import AuthenticationServices
import Auth
import DesignSystem
import Networking
import SwiftUI

public struct LoginView: View {
    let session: SessionStore
    @State private var email: String
    @State private var password: String
    @State private var code = ""
    @State private var codeSent: Bool
    @State private var isLoading = false
    @State private var isGoogleLoading = false
    @State private var error: LoginError?
    @State private var showsPassword: Bool
    @State private var resendDeadline: Date?
    @State private var failureCount = 0
    @State private var successCount = 0
    @FocusState private var focus: Field?
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession

    private static let codeLength = 7
    private static let webURL = URL(string: "https://kurz.fyi")!
    private static let google = GoogleSignInService()

    private enum Field { case email, password, code }

    struct LoginError: Equatable {
        var message: String
        var place: LoginErrorPlace
    }

    public init(session: SessionStore) {
        self.init(session: session, email: "", password: "", codeSent: false, error: nil, showsPassword: false, resendDeadline: nil)
    }

    init(session: SessionStore, email: String, password: String, codeSent: Bool, error: LoginError?, showsPassword: Bool, resendDeadline: Date?) {
        self.session = session
        _email = State(initialValue: email)
        _password = State(initialValue: password)
        _codeSent = State(initialValue: codeSent)
        _error = State(initialValue: error)
        _showsPassword = State(initialValue: showsPassword)
        _resendDeadline = State(initialValue: resendDeadline)
    }

    public var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 24) {
                    KurzLogo(size: 56)
                    header
                    VStack(spacing: 16) {
                        if codeSent { codeStep } else { googleStep; credentialsStep }
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
            .onAppear { if LoginRules.shouldAutofocus(height: geometry.size.height) { focus = .email } }
        }
        .background(Color.appBackground.ignoresSafeArea())
        .animation(.default, value: codeSent)
        .animation(.default, value: emailReady)
        .animation(.default, value: error)
        .onChange(of: email) { if error?.place == .email { error = nil } }
        .onChange(of: error) { _, new in
            if let new { AccessibilityNotification.Announcement(new.message).post() }
        }
        .sensoryFeedback(.error, trigger: failureCount)
        .sensoryFeedback(.success, trigger: successCount)
    }

    @ViewBuilder private func errorView(_ place: LoginErrorPlace) -> some View {
        if let error, error.place == place {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill").accessibilityHidden(true)
                Text(verbatim: error.message).accessibilityIdentifier("login-error")
            }
            .font(.footnote).foregroundStyle(Color.appDestructive).multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .transition(.opacity)
        }
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
        errorView(.google)
        LabeledDivider("or", titleIdentifier: "login-divider")
    }

    @ViewBuilder private var credentialsStep: some View {
        VStack(spacing: 8) {
            FormField("E-mail", isFocused: focus == .email) {
                TextField("E-mail", text: $email, prompt: Text(""))
                    .placeholder("do.you.know@university.kurz.fyi", when: email.isEmpty)
                    .textContentType(.username).keyboard(.emailAddress).noAutocapitalization().autocorrectionDisabled()
                    .focused($focus, equals: .email).submitLabel(emailReady ? .next : .done).onSubmit { if emailReady { focus = .password } }
                    .accessibilityIdentifier("email-field")
            }
            errorView(.email)
        }
        FormField("Password", isFocused: focus == .password, trailing: { Link("Forgot your password?", destination: Self.webURL.appending(path: "password/forgot")).font(.footnote.weight(.semibold)).foregroundStyle(Color.appForeground) }) {
            HStack(spacing: 4) {
                passwordInput
                Button { showsPassword.toggle(); focus = .password } label: {
                    Image(systemName: showsPassword ? "eye.slash" : "eye").foregroundStyle(Color.appMutedForeground).frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain).padding(.vertical, -12).padding(.trailing, -8)
                .accessibilityLabel(showsPassword ? "Hide password" : "Show password")
                .accessibilityIdentifier("password-toggle")
            }
        }
        .frame(height: emailReady ? nil : 0, alignment: .top).clipped()
        .padding(.bottom, emailReady ? 0 : -16)
        .opacity(emailReady ? 1 : 0)
        .allowsHitTesting(emailReady)
        .accessibilityHidden(!emailReady)
        VStack(spacing: 8) {
            Button { Task { await signInWithPassword() } } label: { label("Sign in") }
                .buttonStyle(PrimaryButtonStyle()).disabled(isLoading || !emailReady || password.isEmpty)
                .accessibilityIdentifier("login-button")
            errorView(.signIn)
        }
        VStack(spacing: 8) {
            Button { requestCode() } label: { Label("E-mail me a code", systemImage: "envelope").fontWeight(.medium) }
                .buttonStyle(TextButtonStyle()).disabled(isLoading)
                .accessibilityIdentifier("send-code-button")
            errorView(.sendCode)
        }
    }

    @ViewBuilder private var passwordInput: some View {
        if showsPassword {
            TextField("", text: $password)
                .textContentType(.password).keyboard(.emailAddress).noAutocapitalization().autocorrectionDisabled()
                .focused($focus, equals: .password).submitLabel(.go).onSubmit { Task { await signInWithPassword() } }
                .accessibilityIdentifier("password-field")
        } else {
            SecureField("", text: $password)
                .textContentType(.password)
                .focused($focus, equals: .password).submitLabel(.go).onSubmit { Task { await signInWithPassword() } }
                .accessibilityIdentifier("password-field")
        }
    }

    @ViewBuilder private var codeStep: some View {
        FormField("Code", isFocused: focus == .code) {
            TextField("Code", text: $code, prompt: Text(""))
                .placeholder("0000000", when: code.isEmpty)
                .textContentType(.oneTimeCode).keyboard(.numberPad)
                .focused($focus, equals: .code).accessibilityIdentifier("code-field")
                .onChange(of: code) { _, new in if new.count >= Self.codeLength { Task { await verifyCode() } } }
        }
        VStack(spacing: 8) {
            Button { Task { await verifyCode() } } label: { label("Verify and sign in") }
                .buttonStyle(PrimaryButtonStyle()).disabled(isLoading || code.count < Self.codeLength)
                .accessibilityIdentifier("verify-button")
            errorView(.code)
        }
        resendButton
        Button("Use another e-mail") { codeSent = false; code = ""; error = nil; resendDeadline = nil }
            .buttonStyle(TextButtonStyle())
    }

    private var resendButton: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = resendDeadline.map { LoginRules.resendRemaining(until: $0, now: context.date) } ?? 0
            Button { Task { await sendCode(place: .code) } } label: {
                if remaining > 0 { Text("Resend in \(remaining)s").monospacedDigit() } else { Text("Resend code") }
            }
            .buttonStyle(TextButtonStyle()).disabled(isLoading || remaining > 0)
            .accessibilityIdentifier("resend-button")
        }
    }

    private var emailReady: Bool { normalizedEmail.wholeMatch(of: /[^\s@]+@[^\s@]+\.[^\s@]+/) != nil }
    private var normalizedEmail: String { email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }

    private func label(_ title: LocalizedStringKey) -> some View {
        Group { if isLoading && !isGoogleLoading { Text("Signing in…").fontWeight(.semibold) } else { Text(title).fontWeight(.semibold) } }.frame(maxWidth: .infinity)
    }

    private func perform(place: LoginErrorPlace, _ describe: @escaping (Error) -> LocalizedStringResource?, _ work: () async throws -> Void) async {
        guard !isLoading else { return }
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            try await work()
        } catch {
            if case .rateLimited(let retryAfter) = error as? APIError, codeSent { resendDeadline = LoginRules.resendDeadline(from: .now, retryAfter: retryAfter) }
            if let message = describe(error) {
                self.error = LoginError(message: String(localized: message), place: LoginRules.place(for: error, default: place))
                failureCount += 1
            }
        }
    }

    private func signInWithPassword() async {
        await perform(place: .signIn, { failure($0, unauthorized: "Wrong e-mail or password. Too many attempts pause password sign-in for a while.") }) {
            try await session.signIn(email: normalizedEmail, password: password)
            successCount += 1
        }
    }

    private func signInWithGoogle() async {
        isGoogleLoading = true
        defer { isGoogleLoading = false }
        await perform(place: .google, googleFailure) {
            let request = Self.google.makeRequest()
            let callback = try await webAuthenticationSession.authenticate(using: request.url, callback: .customScheme(Self.google.callbackScheme), additionalHeaderFields: [:])
            try await session.signInWithGoogle(idToken: try await Self.google.idToken(for: request, callback: callback))
            successCount += 1
        }
    }

    private func googleFailure(_ error: Error) -> LocalizedStringResource? {
        if error is CancellationError || (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin { return nil }
        if error is GoogleSignInService.Failure { return "Google sign-in did not go through. Please try again." }
        if case .server(404, _) = error as? APIError { return "Google sign-in isn't available right now." }
        return failure(error, unauthorized: "Google sign-in did not go through. Please try again.")
    }

    private func requestCode() {
        guard emailReady else {
            error = LoginError(message: String(localized: "Enter your e-mail first, then we send you a code."), place: .email)
            failureCount += 1
            return
        }
        Task { await sendCode(place: .sendCode) }
    }

    private func failure(_ error: Error, unauthorized: LocalizedStringResource) -> LocalizedStringResource {
        guard let api = error as? APIError else { return "Something went wrong, please try again later." }
        switch api {
        case .unauthorized: return unauthorized
        case .rateLimited: return "Too many attempts. Please wait a few minutes and try again."
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

    private func sendCode(place: LoginErrorPlace) async {
        await perform(place: place, { failure($0, unauthorized: "Something went wrong, please try again later.") }) {
            try await session.auth.requestCode(email: normalizedEmail, locale: Locale.current.language.languageCode?.identifier)
            resendDeadline = LoginRules.resendDeadline(from: .now)
            codeSent = true
            focus = .code
        }
    }

    private func verifyCode() async {
        await perform(place: .code, { code = ""; return failure($0, unauthorized: "That code is wrong or expired. Request a new one if needed.") }) {
            try await session.signIn(email: normalizedEmail, code: code)
            successCount += 1
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
