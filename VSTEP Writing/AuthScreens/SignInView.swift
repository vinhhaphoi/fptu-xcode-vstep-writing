import FirebaseAuth
import SwiftUI

// MARK: - LoginView
struct SignInView: View {
    @EnvironmentObject var authManager: AuthenticationManager

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
        // Case 1: user typed something but format is wrong
        // Case 2: user tried to submit but email is empty
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
            // Email field
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

            // Password field
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

            // Error banner
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

            // Forgot password
            HStack {
                Spacer()
                Button("Forgot password?") {
                    // TODO: Handle forgot password
                }
                .font(.footnote)
                .foregroundStyle(.blue)
            }
            .padding(.horizontal, 4)

            // Sign In button
            signInButton
        }
    }

    // MARK: - Sign In Button
    private var signInButton: some View {
        Button {
            Task { await handleSignIn() }
        } label: {
            ZStack {
                if isLoading {
                    ProgressView()
                        .tint(.white)
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

            // Contact us link
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
        // Contact sheet
        .sheet(isPresented: $isShowingContact) {
            NavigationStack {
                ContactInfoView()
//                    .toolbar {
//                        ToolbarItem(placement: .topBarTrailing) {
//                            Button("Done") { isShowingContact = false }
//                        }
//                    }
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
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
            // Wrong password or invalid credential
            return "Incorrect email or password. Please try again."
        case 17011:
            // User not found
            return "No account found with this email."
        case 17010:
            // Too many requests
            return "Too many attempts. Please wait a moment and try again."
        case 17020:
            // Network error
            return "No internet connection. Please check your network."
        case 17005:
            // User disabled
            return "This account has been disabled. Please contact support."
        case 17026:
            // Weak password (for sign up, just in case)
            return "Password is too weak. Please choose a stronger one."
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

            // Inline error message
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
