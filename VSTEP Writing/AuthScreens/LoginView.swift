import SwiftUI

struct LoginView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    
    // MARK: - States
    @State private var email = ""
    @State private var password = ""
    @State private var showForm = false
    @State private var isShowingSignUp = false
    @State private var errorMessage = ""
    @State private var isLoading = false
    @State private var isGoogleLoading = false
    
    @FocusState private var focusedField: Field?
    
    enum Field: Hashable {
        case email
        case password
    }
    
    // MARK: - Validation
    private var isEmailValid: Bool {
        let emailRegex = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
        let emailPredicate = NSPredicate(format:"SELF MATCHES %@", emailRegex)
        return emailPredicate.evaluate(with: email)
    }
    
    private var emailValidationMessage: String? {
        if email.isEmpty {
            return nil
        }
        if !isEmailValid {
            return "Invalid email format"
        }
        return nil
    }
    
    private var isButtonDisabled: Bool {
        isLoading || !isEmailValid || password.isEmpty
    }
    
    // MARK: - Body
    var body: some View {
        NavigationStack {
            ZStack {
                backgroundColor
                contentView
            }
            .navigationDestination(isPresented: $isShowingSignUp) {
                SignUpView()
            }
            
        }
    }
    
    // MARK: - Main Components
    private var backgroundColor: some View {
        Color(.systemGroupedBackground)
            .ignoresSafeArea()
    }
    
    private var contentView: some View {
        Group {
            if !showForm {
                initialScreen
            } else {
                formScreen
            }
        }
    }
    
    // MARK: - Initial Screen
    private var initialScreen: some View {
        VStack(spacing: 0) {
            Spacer()
            logoSection
            Spacer()
            actionButtonsSection
            Spacer()
            footerSection
        }
        .transition(.opacity)
    }
    
    private var logoSection: some View {
        VStack(spacing: 0) {
            Image(systemName: "graduationcap")
                .font(.system(size: 120))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.primary)
            
            Text("VSTEP Writing")
                .font(.largeTitle)
                .fontWeight(.bold)
                .padding(.top, 20)
        }
    }
    
    private var actionButtonsSection: some View {
        VStack(spacing: 40) {
            emailLoginSection
            googleLoginSection
        }
    }
    
    private var emailLoginSection: some View {
        VStack(spacing: 16) {
            Button {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    showForm = true
                }
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    focusedField = .email
                }
            } label: {
                Text("Sign in with Email")
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
            }
            .background(Color.black.opacity(0.85))
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .glassEffect()
            .disabled(isGoogleLoading)
            
            Text("Sign in to access your account")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 32)
    }
    
    private var googleLoginSection: some View {
        VStack(spacing: 16) {
            Button {
                Task { await handleGoogleSignIn() }
            } label: {
                googleButtonContent
            }
            .buttonStyle(.plain)
            .disabled(isGoogleLoading)
            
            Text("Quick sign in with your Google account")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 32)
    }
    
    private var googleButtonContent: some View {
        HStack(spacing: 12) {
            if isGoogleLoading {
                ProgressView()
                    .tint(.blue)
            } else {
                Image(systemName: "globe")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 24, height: 24)
                Text("Sign in with Google")
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 50)
        .glassEffect()
    }
    
    // MARK: - Form Screen
    private var formScreen: some View {
        VStack(spacing: 0) {
            formHeaderSection
            
            ScrollView {
                VStack(spacing: 20) {
                    inputFieldsCard
                    actionButtons
                }
                .padding(.top, 20)
            }
            .toolbar {
                cancelToolbarButton
            }
            
            Spacer()
            footerSection
        }
        .transition(.opacity)
        .onTapGesture {
            focusedField = nil
        }
    }
    
    private var formHeaderSection: some View {
        VStack(spacing: 0) {
            Image(systemName: "lock.shield")
                .font(.system(size: 100))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.primary)
                .padding(.top, 40)
                .padding(.bottom, 20)
            
            Text("Sign In")
                .font(.largeTitle)
                .fontWeight(.bold)
                .padding(.bottom, 20)
        }
    }
    
    private var inputFieldsCard: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                emailInputField
                Divider()
                    .padding(.leading, 56)
                passwordInputField
            }
            .glassEffect(in: .rect(cornerRadius: 16.0))
            .padding(.horizontal, 16)
            
            if !errorMessage.isEmpty {
                errorMessageView
            }
        }
    }
    
    private var emailInputField: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "envelope")
                    .foregroundStyle(.blue)
                    .font(.system(size: 20))
                    .frame(width: 28)
                
                TextField("Email", text: $email)
                    .textContentType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                    .autocorrectionDisabled()
                    .submitLabel(.next)
                    .focused($focusedField, equals: .email)
                    .onSubmit {
                        focusedField = .password
                    }
                
                if !email.isEmpty {
                    validationIcon
                }
            }
            .padding()
            
            if let message = emailValidationMessage {
                validationMessageView(message: message)
            }
        }
    }
    
    private var validationIcon: some View {
        Image(systemName: isEmailValid ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
            .foregroundStyle(isEmailValid ? .green : .orange)
            .font(.system(size: 20))
    }
    
    private func validationMessageView(message: String) -> some View {
        HStack {
            Image(systemName: "info.circle")
                .font(.caption)
            Text(message)
                .font(.caption)
            Spacer()
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }
    
    private var passwordInputField: some View {
        HStack(spacing: 12) {
            Image(systemName: "lock.shield")
                .foregroundStyle(.blue)
                .font(.system(size: 20))
                .frame(width: 28)
            
            SecureField("Password", text: $password)
                .textContentType(.password)
                .submitLabel(.go)
                .focused($focusedField, equals: .password)
                .onSubmit {
                    Task { await handleSignIn() }
                }
        }
        .padding()
    }
    
    private var errorMessageView: some View {
        HStack {
            Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .font(.caption)
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }
    
    private var actionButtons: some View {
        VStack(spacing: 16) {
            signInButton
            forgotPasswordButton
        }
        .padding(.horizontal, 16)
    }
    
    private var signInButton: some View {
        Button {
            Task { await handleSignIn() }
        } label: {
            Group {
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
            .frame(height: 50)
        }
        .disabled(isButtonDisabled)
        .background(.blue.gradient)
        .clipShape(Capsule())
        .glassEffect()
    }
    
    private var forgotPasswordButton: some View {
        Button("Forgot Password?") {
            // TODO: Handle forgot password
        }
        .fontWeight(.semibold)
        .frame(maxWidth: .infinity)
        .frame(height: 50)
        .glassEffect()
    }
    
    // MARK: - Toolbar
    private var cancelToolbarButton: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel", systemImage: "xmark") {
                withAnimation {
                    showForm = false
                    errorMessage = ""
                    email = ""
                    password = ""
                }
            }
        }
    }
    
    // MARK: - Footer
    private var footerSection: some View {
        VStack(spacing: 12) {
            signUpPrompt
            termsAndPrivacy
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 32)
        .padding(.bottom, 40)
    }
    
    private var signUpPrompt: some View {
        HStack(spacing: 4) {
            Text("Don't have an account?")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            Button("Sign Up") {
                isShowingSignUp = true
            }
            .font(.subheadline)
            .fontWeight(.semibold)
        }
    }
    
    private var termsAndPrivacy: some View {
        HStack(spacing: 3) {
            Text("By continuing, you agree to our")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            Button("Terms") {
                // TODO: Show terms
            }
            .font(.caption)
            
            Text("and")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            Button("Privacy Policy") {
                // TODO: Show privacy
            }
            .font(.caption)
        }
    }
    
    // MARK: - Actions
    private func handleSignIn() async {
        await MainActor.run {
            isLoading = true
            errorMessage = ""
            focusedField = nil
        }
        
        do {
            try await authManager.signIn(email: email, password: password)
        } catch {
            await MainActor.run {
                errorMessage = "Login failed: \(error.localizedDescription)"
            }
        }
        
        await MainActor.run {
            isLoading = false
        }
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
                errorMessage = "Google login failed: \(error.localizedDescription)"
            }
        }
        
        await MainActor.run {
            isGoogleLoading = false
        }
    }
}
