import SwiftUI

struct LoginView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @State private var email = ""
    @State private var password = ""
    @State private var isShowingSignUp = false
    @State private var errorMessage = ""
    @State private var isLoading = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                VStack(spacing: 20) {
                    Image(systemName: "lock.shield")
                        .font(.system(size: 80))
                        .foregroundStyle(.blue)
                        .padding(.bottom, 30)
                    
                    Text("Sign in")
                        .font(.title.bold())
                    
                    // Email & Password Block với Glass Effect
                    VStack(spacing: 15) {
                        TextField("Identity", text: $email)
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .autocapitalization(.none)
                            .padding()
                        
                        SecureField("Password", text: $password)
                            .textContentType(.password)
                            .padding()
                    }
                    .glassEffect(in: .rect(cornerRadius: 16.0)) // Glass effect cho khối
                    .padding(.horizontal)
                    
                    if !errorMessage.isEmpty {
                        Text(errorMessage)
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                    
                    // Email Login Button với Glass Effect đơn lẻ
                    Button(action: handleSignIn) {
                        HStack {
                            if isLoading {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            } else {
                                Text("Sign in")
                                    .fontWeight(.semibold)
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .padding()
                    }
                    .glassEffect() // Glass effect cho button đơn lẻ
                    .padding(.horizontal)
                    .disabled(email.isEmpty || password.isEmpty || isLoading)
                    
                    // Divider
                    HStack {
                        Rectangle()
                            .frame(height: 1)
                            .foregroundColor(.gray.opacity(0.3))
                        Text("or")
                            .foregroundColor(.gray)
                            .font(.caption)
                        Rectangle()
                            .frame(height: 1)
                            .foregroundColor(.gray.opacity(0.3))
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 10)
                    
                    // Google Sign-In Button với Glass Effect đơn lẻ
                    Button(action: handleGoogleSignIn) {
                        HStack {
                            Image(systemName: "globe")
                                .font(.title3)
                            Text("Sign in with Google")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                    }
                    .glassEffect() // Glass effect cho button đơn lẻ
                    .padding(.horizontal)
                    .disabled(isLoading)
                    
                    Button("Don't have account? Sign up") {
                        isShowingSignUp = true
                    }
                    .padding(.top, 10)
                    
                    Spacer()
                }
            }
            .sheet(isPresented: $isShowingSignUp) {
                SignUpView()
            }
        }
        .background(Color(.systemGroupedBackground))
    }
    
    private func handleSignIn() {
        isLoading = true
        errorMessage = ""
        
        Task {
            do {
                try await authManager.signIn(email: email, password: password)
            } catch {
                errorMessage = "Login failed: \(error.localizedDescription)"
            }
            isLoading = false
        }
    }
    
    private func handleGoogleSignIn() {
        isLoading = true
        errorMessage = ""
        
        Task {
            do {
                try await authManager.signInWithGoogle()
            } catch {
                errorMessage = "Login with Google failed: \(error.localizedDescription)"
            }
            isLoading = false
        }
    }
}
