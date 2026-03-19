import FirebaseAuth
import SwiftUI

// MARK: - LoginView
struct SignInView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    var onLoginSuccess: (() -> Void)? = nil

    // MARK: - States
    @State private var email = ""
    @State private var password = ""
    @State private var isPasswordVisible = false
    @State private var isShowingSignUp = false
    @State private var errorMessage = ""
    @State private var isLoading = false
    @State private var isGoogleLoading = false
    @State private var didAttemptSubmit = false
    @State private var isShowingTerms = false
    @State private var isShowingPrivacy = false
    @State private var isShowingContact = false
    @State private var isShowingForgotPassword = false

    @FocusState private var focusedField: Field?

    enum Field: Hashable {
        case email
        case password
    }

    // MARK: - Validation
    private var isEmailValid: Bool {
        let emailRegex = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
        return NSPredicate(format: "SELF MATCHES %@", emailRegex).evaluate(
            with: email
        )
    }

    private var showEmailError: Bool {
        (!email.isEmpty && !isEmailValid) || (didAttemptSubmit && email.isEmpty)
    }

    private var showPasswordError: Bool {
        didAttemptSubmit && password.isEmpty
    }

    private var isButtonDisabled: Bool {
        isLoading || isGoogleLoading
    }

    // MARK: - Body
    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        headerSection
                            .padding(.top, 60)
                            .padding(.bottom, 40)

                        formSection
                            .padding(.horizontal, 24)

                        dividerSection
                            .padding(.vertical, 28)

                        socialSection
                            .padding(.horizontal, 24)

                        Spacer(minLength: 40)

                        footerSection
                            .padding(.bottom, 40)
                    }
                }
            }
            .navigationBarHidden(true)
            .navigationDestination(isPresented: $isShowingSignUp) {
                SignUpView()
            }
        }
        .onTapGesture {
            focusedField = nil
        }
        .sheet(isPresented: $isShowingForgotPassword) {
            ForgotPasswordView(prefillEmail: email)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Header
    private var headerSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "graduationcap.fill")
                .font(.system(size: 56))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.primary)

            Text("VSTEP Writing")
                .font(.title.bold())

            Text("Sign in to continue your learning")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Form
    private var formSection: some View {
        VStack(spacing: 16) {
            FloatingLabelField(
                label: "Email",
                systemImage: "envelope",
                tint: .orange,
                error: showEmailError ? "Invalid email format" : nil
            ) {
                TextField("", text: $email)
                    .textContentType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                    .autocorrectionDisabled()
                    .submitLabel(.next)
                    .focused($focusedField, equals: .email)
                    .onSubmit { focusedField = .password }
            } trailingView: {
                if !email.isEmpty {
                    Image(
                        systemName: isEmailValid
                            ? "checkmark.circle.fill" : "xmark.circle.fill"
                    )
                    .foregroundStyle(isEmailValid ? .green : .red)
                    .font(.system(size: 18))
                    .transition(.scale.combined(with: .opacity))
                }
            }

            FloatingLabelField(
                label: "Password",
                systemImage: "lock",
                tint: .blue,
                error: showPasswordError ? "Password is required" : nil
            ) {
                Group {
                    if isPasswordVisible {
                        TextField("", text: $password)
                            .textContentType(.password)
                    } else {
                        SecureField("", text: $password)
                            .textContentType(.password)
                    }
                }
                .submitLabel(.go)
                .focused($focusedField, equals: .password)
                .onSubmit { Task { await handleSignIn() } }
            } trailingView: {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isPasswordVisible.toggle()
                    }
                } label: {
                    Image(systemName: isPasswordVisible ? "eye.slash" : "eye")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 18))
                }
                .buttonStyle(.plain)
            }

            if !errorMessage.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.caption)
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                    Spacer()
                }
                .padding(.horizontal, 4)
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            HStack {
                Spacer()
                Button("Forgot password?") {
                    focusedField = nil
                    isShowingForgotPassword = true
                }
                .font(.footnote)
                .foregroundStyle(.blue)
            }
            .padding(.horizontal, 4)

            signInButton
        }
    }

    // MARK: - Sign In Button
    private var signInButton: some View {
        HStack(spacing: 12) {
            Button {
                Task { await handleSignIn() }
            } label: {
                ZStack {
                    if isLoading {
                        ProgressView().tint(.white)
                    } else {
                        Text("Sign In")
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .glassEffect(.regular.tint(.blue).interactive(), in: .capsule)
            }
            .buttonStyle(.plain)
            .disabled(isButtonDisabled)
            .opacity(isButtonDisabled ? 0.6 : 1)
            .animation(.easeInOut(duration: 0.2), value: isButtonDisabled)

            if BiometricAuthService.shared.isAvailable
                && Auth.auth().currentUser != nil
            {
                Button {
                    Task { await handleBiometricSignIn() }
                } label: {
                    Image(
                        systemName: BiometricAuthService.shared.biometricType
                            == .faceID ? "faceid" : "touchid"
                    )
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(.primary)
                    .frame(width: 52, height: 52)
                    .glassEffect(.regular.interactive(), in: .capsule)
                }
                .buttonStyle(.plain)
                .disabled(isButtonDisabled)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isButtonDisabled)
    }

    // MARK: - Divider
    private var dividerSection: some View {
        HStack(spacing: 12) {
            Rectangle()
                .fill(Color(.separator))
                .frame(height: 0.5)
            Text("or")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Rectangle()
                .fill(Color(.separator))
                .frame(height: 0.5)
        }
        .padding(.horizontal, 24)
    }

    // MARK: - Social Login
    private var socialSection: some View {
        GlassEffectContainer {
            Button {
                Task { await handleGoogleSignIn() }
            } label: {
                HStack(spacing: 10) {
                    if isGoogleLoading {
                        ProgressView().tint(.primary)
                    } else {
                        Image(systemName: "globe")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(.primary)
                        Text("Continue with Google")
                            .fontWeight(.medium)
                            .foregroundStyle(.primary)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .glassEffect(.regular.interactive(), in: .capsule)
            }
            .buttonStyle(.plain)
            .disabled(isButtonDisabled)
        }
    }

    // MARK: - Footer
    private var footerSection: some View {
        VStack(spacing: 10) {
            HStack(spacing: 4) {
                Text("Don't have an account?")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button("Sign Up") { isShowingSignUp = true }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.blue)
            }

            HStack(spacing: 3) {
                Text("By continuing, you agree to our")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Terms") { isShowingTerms = true }
                    .font(.caption)
                Text("and")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Privacy Policy") { isShowingPrivacy = true }
                    .font(.caption)
            }

            Button("Need help? Contact us") { isShowingContact = true }
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 32)
        .sheet(isPresented: $isShowingTerms) {
            TermsOfUseView()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $isShowingPrivacy) {
            PrivacyPolicyView()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $isShowingContact) {
            NavigationStack {
                ContactInfoView()
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Biometric Sign In
    private func handleBiometricSignIn() async {
        do {
            try await BiometricAuthService.shared.authenticate()
            await MainActor.run {
                if Auth.auth().currentUser != nil {
                    if !authManager.isBiometricLoginEnabled {
                        authManager.isBiometricLoginEnabled = true
                    }
                    onLoginSuccess?()
                } else {
                    withAnimation {
                        errorMessage = "Session expired. Please sign in again."
                    }
                }
            }
        } catch BiometricError.cancelled {
        } catch {
            await MainActor.run {
                withAnimation { errorMessage = error.localizedDescription }
            }
        }
    }

    // MARK: - Actions
    private func handleSignIn() async {
        didAttemptSubmit = true
        guard isEmailValid && !password.isEmpty else { return }

        await MainActor.run {
            isLoading = true
            errorMessage = ""
            focusedField = nil
        }
        do {
            try await authManager.signIn(email: email, password: password)
            await MainActor.run { onLoginSuccess?() }
        } catch {
            await MainActor.run {
                withAnimation {
                    errorMessage = friendlyErrorMessage(from: error)
                }
            }
        }
        await MainActor.run { isLoading = false }
    }

    private func handleGoogleSignIn() async {
        await MainActor.run {
            isGoogleLoading = true
            errorMessage = ""
        }
        do {
            try await authManager.signInWithGoogle()
            await MainActor.run { onLoginSuccess?() }
        } catch {
            await MainActor.run {
                withAnimation {
                    errorMessage = friendlyErrorMessage(from: error)
                }
            }
        }
        await MainActor.run { isGoogleLoading = false }
    }

    // MARK: - Error Mapping
    private func friendlyErrorMessage(from error: Error) -> String {
        let code = (error as NSError).code
        switch code {
        case 17004, 17009:
            return "Incorrect email or password. Please try again."
        case 17011:
            return "No account found with this email."
        case 17010:
            return "Too many attempts. Please wait a moment and try again."
        case 17020:
            return "No internet connection. Please check your network."
        case 17005:
            return "This account has been disabled. Please contact support."
        case 17026:
            return "Password is too weak. Please choose a stronger one."
        default:
            return "Something went wrong. Please try again."
        }
    }
}

// MARK: - ForgotPasswordView
struct ForgotPasswordView: View {

    var prefillEmail: String = ""

    @Environment(\.dismiss) private var dismiss
    @State private var email: String = ""
    @State private var isLoading = false
    @State private var sentSuccessfully = false
    @State private var errorMessage = ""

    private var isEmailValid: Bool {
        let emailRegex = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
        return NSPredicate(format: "SELF MATCHES %@", emailRegex).evaluate(
            with: email
        )
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 28) {
                // Icon + header
                VStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Color.blue.opacity(0.1))
                            .frame(width: 72, height: 72)
                        Image(systemName: "lock.rotation")
                            .font(.system(size: 32))
                            .foregroundStyle(.blue)
                    }

                    Text("Reset Password")
                        .font(.title2.bold())

                    Text(
                        "Enter your email and we'll send you a link to reset your password."
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
                }
                .padding(.top, 8)

                if sentSuccessfully {
                    successView
                } else {
                    inputView
                }

                Spacer()
            }
            .padding(.horizontal, 24)
            .background(Color(.systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .font(.title3)
                    }
                }
            }
        }
        .onAppear {
            // Pre-fill email if user had already typed it on the sign-in screen
            if email.isEmpty {
                email = prefillEmail
            }
        }
    }

    // MARK: - Input View
    private var inputView: some View {
        VStack(spacing: 16) {
            FloatingLabelField(
                label: "Email",
                systemImage: "envelope",
                tint: .blue,
                error: (!email.isEmpty && !isEmailValid)
                    ? "Invalid email format" : nil
            ) {
                TextField("", text: $email)
                    .textContentType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                    .autocorrectionDisabled()
                    .submitLabel(.send)
                    .onSubmit { Task { await sendReset() } }
            } trailingView: {
                if !email.isEmpty {
                    Image(
                        systemName: isEmailValid
                            ? "checkmark.circle.fill" : "xmark.circle.fill"
                    )
                    .foregroundStyle(isEmailValid ? .green : .red)
                    .font(.system(size: 18))
                }
            }

            if !errorMessage.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.caption)
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                    Spacer()
                }
                .padding(.horizontal, 4)
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            Button {
                Task { await sendReset() }
            } label: {
                Group {
                    if isLoading {
                        ProgressView().tint(.white)
                    } else {
                        Text("Send Reset Link")
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .glassEffect(.regular.tint(.blue).interactive(), in: .capsule)
            }
            .buttonStyle(.plain)
            .disabled(!isEmailValid || isLoading)
            .opacity(!isEmailValid || isLoading ? 0.6 : 1)
            .animation(.easeInOut(duration: 0.2), value: isEmailValid)
        }
    }

    // MARK: - Success View
    private var successView: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.12))
                    .frame(width: 64, height: 64)
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(.green)
            }
            .transition(.scale.combined(with: .opacity))

            Text("Email Sent!")
                .font(.headline)

            Text(
                "Check your inbox at **\(email)** and follow the link to reset your password."
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)

            // Note for Google users who accidentally landed here
            HStack(spacing: 6) {
                Image(systemName: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(
                    "If you signed up with Google, your password is managed by Google."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(12)
            .glassEffect(in: .rect(cornerRadius: 10))

            Button {
                dismiss()
            } label: {
                Text("Done")
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .glassEffect(
                        .regular.tint(.blue).interactive(),
                        in: .capsule
                    )
            }
            .buttonStyle(.plain)
        }
        .animation(.spring(duration: 0.4), value: sentSuccessfully)
    }

    // MARK: - Send Reset Email
    private func sendReset() async {
        guard isEmailValid else { return }

        await MainActor.run {
            isLoading = true
            errorMessage = ""
        }

        do {
            try await Auth.auth().sendPasswordReset(withEmail: email)
            await MainActor.run {
                isLoading = false
                withAnimation(.spring(duration: 0.4)) {
                    sentSuccessfully = true
                }
            }
        } catch {
            await MainActor.run {
                isLoading = false
                errorMessage = friendlyResetError(from: error)
            }
        }
    }

    // MARK: - Error Mapping
    private func friendlyResetError(from error: Error) -> String {
        let code = (error as NSError).code
        switch code {
        case 17011:
            return "No account found with this email."
        case 17020:
            return "No internet connection. Please check your network."
        case 17010:
            return "Too many requests. Please wait a moment and try again."
        default:
            return "Something went wrong. Please try again."
        }
    }
}

// MARK: - FloatingLabelField
struct FloatingLabelField<Input: View, Trailing: View>: View {
    let label: String
    let systemImage: String
    let tint: Color
    let error: String?
    @ViewBuilder let inputView: () -> Input
    @ViewBuilder let trailingView: () -> Trailing

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .foregroundStyle(error != nil ? .red : tint)
                    .font(.system(size: 18))
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(.caption)
                        .foregroundStyle(error != nil ? .red : .secondary)
                    inputView()
                        .frame(height: 22)
                }

                trailingView()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .glassEffect(
                error != nil
                    ? .regular.tint(.red.opacity(0.15))
                    : .regular
            )
            .animation(.easeInOut(duration: 0.2), value: error != nil)

            if let error {
                HStack(spacing: 5) {
                    Image(systemName: "info.circle")
                        .font(.caption2)
                    Text(error)
                        .font(.caption)
                }
                .foregroundStyle(.red)
                .padding(.horizontal, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: error)
    }
}
