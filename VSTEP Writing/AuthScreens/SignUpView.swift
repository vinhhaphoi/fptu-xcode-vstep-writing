import SwiftUI

struct SignUpView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @Environment(\.dismiss) var dismiss
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var errorMessage = ""
    @State private var isLoading = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Background gradient để highlight glass effect
                LinearGradient(
                    colors: [.purple.opacity(0.3), .pink.opacity(0.3), .orange.opacity(0.2)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 20) {
                        // Header Icon
                        Image(systemName: "person.badge.plus")
                            .font(.system(size: 70))
                            .foregroundStyle(.purple)
                            .padding(.top, 40)
                            .padding(.bottom, 10)
                        
                        Text("Tạo tài khoản")
                            .font(.title.bold())
                        
                        // Email, Password & Confirm Password Block với Glass Effect
                        VStack(spacing: 15) {
                            TextField("Email", text: $email)
                                .textContentType(.emailAddress)
                                .keyboardType(.emailAddress)
                                .autocapitalization(.none)
                                .padding()
                            
                            SecureField("Mật khẩu", text: $password)
                                .textContentType(.newPassword)
                                .padding()
                            
                            SecureField("Xác nhận mật khẩu", text: $confirmPassword)
                                .textContentType(.newPassword)
                                .padding()
                        }
                        .glassEffect(in: .rect(cornerRadius: 16.0)) // Glass effect cho khối
                        .padding(.horizontal)
                        
                        // Error Message
                        if !errorMessage.isEmpty {
                            Text(errorMessage)
                                .foregroundColor(.red)
                                .font(.caption)
                                .padding(.horizontal)
                                .multilineTextAlignment(.center)
                        }
                        
                        // Password Requirements Hint
                        if !password.isEmpty && password.count < 6 {
                            HStack {
                                Image(systemName: "info.circle")
                                    .foregroundColor(.orange)
                                Text("Mật khẩu phải có ít nhất 6 ký tự")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.horizontal)
                        }
                        
                        // Password Match Indicator
                        if !confirmPassword.isEmpty && password != confirmPassword {
                            HStack {
                                Image(systemName: "xmark.circle")
                                    .foregroundColor(.red)
                                Text("Mật khẩu không khớp")
                                    .font(.caption)
                                    .foregroundColor(.red)
                            }
                            .padding(.horizontal)
                        }
                        
                        // Sign Up Button với Glass Effect
                        Button(action: handleSignUp) {
                            HStack {
                                if isLoading {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                } else {
                                    Image(systemName: "checkmark.circle.fill")
                                    Text("Đăng ký")
                                        .fontWeight(.semibold)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                        }
                        .glassEffect() // Glass effect cho button đơn lẻ
                        .padding(.horizontal)
                        .disabled(!isFormValid || isLoading)
                        .opacity(isFormValid ? 1.0 : 0.6)
                        
                        Spacer(minLength: 20)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        HStack {
                            Image(systemName: "xmark.circle.fill")
                            Text("Hủy")
                        }
                    }
                }
            }
        }
    }
    
    private var isFormValid: Bool {
        !email.isEmpty &&
        !password.isEmpty &&
        password == confirmPassword &&
        password.count >= 6 &&
        email.contains("@")
    }
    
    private func handleSignUp() {
        guard password == confirmPassword else {
            errorMessage = "Mật khẩu không khớp"
            return
        }
        
        guard password.count >= 6 else {
            errorMessage = "Mật khẩu phải có ít nhất 6 ký tự"
            return
        }
        
        guard email.contains("@") else {
            errorMessage = "Email không hợp lệ"
            return
        }
        
        isLoading = true
        errorMessage = ""
        
        Task {
            do {
                try await authManager.signUp(email: email, password: password)
                dismiss()
            } catch {
                errorMessage = "Đăng ký thất bại: \(error.localizedDescription)"
            }
            isLoading = false
        }
    }
}
