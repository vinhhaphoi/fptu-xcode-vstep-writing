import SwiftUI
import FirebaseAuth

struct SecuritiesInfoView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var authManager: AuthenticationManager
    
    @State private var showChangePasswordSheet = false
    @State private var showDeleteAccountAlert = false
    @State private var alertMessage: AlertMessage?
    
    var body: some View {
        ScrollView {
            // Security Info Section
            securityInfoSection
                .padding()
            
            // Change Password Button
            changePasswordButton
                .padding()
            
            // Delete Account Button
            deleteAccountButton
                .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Security")
        .navigationBarTitleDisplayMode(.large)
        .sheet(isPresented: $showChangePasswordSheet) {
            ChangePasswordView()
        }
        .alert("Delete Account", isPresented: $showDeleteAccountAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                handleDeleteAccount()
            }
        } message: {
            Text("Are you sure you want to delete your account? This action cannot be undone.")
        }
        .alert(item: $alertMessage) { alert in
            Alert(title: Text(alert.title), message: Text(alert.message), dismissButton: .default(Text("OK")))
        }
    }
    
    // MARK: - Security Info Section
    private var securityInfoSection: some View {
        VStack(spacing: 0) {
            ForEach(Array(securityInfoList.enumerated()), id: \.offset) { index, info in
                HStack(spacing: 15) {
                    Text(info.label)
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)
                        .frame(width: 80, alignment: .leading)
                    
                    Spacer()
                    
                    Text(info.value)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                
                if index != securityInfoList.count - 1 {
                    Divider()
                        .padding(.leading, 20)
                }
            }
        }
        .glassEffect(in: .rect(cornerRadius: 16.0))
    }
    
    private var securityInfoList: [SecurityInfo] {
        var items: [SecurityInfo] = []
        
        if let email = authManager.user?.email {
            items.append(SecurityInfo(
                label: "Email",
                value: email
            ))
        }
        
        // Add provider info
        items.append(SecurityInfo(
            label: "Provider",
            value: "Email/Password"
        ))
        
        return items
    }
    
    // MARK: - Change Password Button
    private var changePasswordButton: some View {
        Button {
            showChangePasswordSheet = true
        } label: {
            HStack(spacing: 15) {
                Image(systemName: "key.horizontal")
                    .font(.system(size: 26))
                    .foregroundStyle(.blue)
                    .frame(width: 40)
                
                Text("Change Password")
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .buttonStyle(.plain)
        .glassEffect()
    }
    
    // MARK: - Delete Account Button
    private var deleteAccountButton: some View {
        Button(role: .destructive) {
            showDeleteAccountAlert = true
        } label: {
            HStack(spacing: 15) {
                Image(systemName: "person.badge.minus")
                    .font(.system(size: 26))
                    .foregroundStyle(.red)
                    .frame(width: 40)
                
                Text("Delete Account")
                    .font(.body)
                    .fontWeight(.semibold)
                    .foregroundStyle(.red)
                
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .buttonStyle(.plain)
        .glassEffect()
    }
    
    // MARK: - Actions
    private func handleDeleteAccount() {
        // TODO: Implement delete account
        print("⚠️ Delete account requested")
        alertMessage = AlertMessage(title: "Not Implemented", message: "Account deletion is not yet implemented.")
    }
}

struct SecurityInfo {
    let label: String
    let value: String
}

// MARK: - Change Password View
struct ChangePasswordView: View {
    @Environment(\.dismiss) var dismiss
    @State private var currentPassword = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var errorMessage = ""
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    VStack(spacing: 16) {
                        SecureField("Current Password", text: $currentPassword)
                            .textContentType(.password)
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(10)
                        
                        SecureField("New Password", text: $newPassword)
                            .textContentType(.newPassword)
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(10)
                        
                        SecureField("Confirm New Password", text: $confirmPassword)
                            .textContentType(.newPassword)
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(10)
                    }
                    .padding()
                    
                    if !errorMessage.isEmpty {
                        Text(errorMessage)
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                    
                    Button {
                        handleChangePassword()
                    } label: {
                        Text("Change Password")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(isFormValid ? Color.blue : Color.gray)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                    }
                    .disabled(!isFormValid)
                    .padding(.horizontal)
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Change Password")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private var isFormValid: Bool {
        !currentPassword.isEmpty &&
        !newPassword.isEmpty &&
        newPassword == confirmPassword &&
        newPassword.count >= 6
    }
    
    private func handleChangePassword() {
        // TODO: Implement password change
        print("🔐 Changing password...")
        dismiss()
    }
}

#Preview {
    NavigationStack {
        SecuritiesInfoView()
    }
    .environmentObject(AuthenticationManager.shared)
}
