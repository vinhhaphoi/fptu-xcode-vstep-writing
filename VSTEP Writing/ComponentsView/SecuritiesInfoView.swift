// SecuritiesInfoView.swift

import FirebaseAuth
import FirebaseFirestore
import SwiftUI

struct SecuritiesInfoView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var authManager: AuthenticationManager

    @State private var showChangePasswordSheet = false
    @State private var showDeleteAccountSheet = false
    @State private var alertMessage: AlertMessage?

    var body: some View {
        ScrollView {
            securityInfoSection
                .padding()

            // Only show change password for email/password users
            changePasswordButton
                .padding()

            deleteAccountButton
                .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Security")
        .navigationBarTitleDisplayMode(.large)
        .sheet(isPresented: $showChangePasswordSheet) {
            ChangePasswordView()
        }
        .sheet(isPresented: $showDeleteAccountSheet) {
            DeleteAccountRequestView()
                .environmentObject(authManager)
        }
        .alert(item: $alertMessage) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    // MARK: - Detect sign-in provider
    private var isGoogleUser: Bool {
        Auth.auth().currentUser?.providerData.contains(where: {
            $0.providerID == "google.com"
        }) ?? false
    }

    private var providerDisplayName: String {
        isGoogleUser ? "Google" : "Email / Password"
    }

    // MARK: - Security Info Section
    private var securityInfoSection: some View {
        VStack(spacing: 0) {
            ForEach(Array(securityInfoList.enumerated()), id: \.offset) {
                index,
                info in
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
                    Divider().padding(.leading, 20)
                }
            }
        }
        .glassEffect(in: .rect(cornerRadius: 16))
    }

    private var securityInfoList: [SecurityInfo] {
        var items: [SecurityInfo] = []
        if let email = authManager.user?.email {
            items.append(SecurityInfo(label: "Email", value: email))
        }
        items.append(
            SecurityInfo(label: "Provider", value: providerDisplayName)
        )
        return items
    }

    // MARK: - Change Password Button
    private var changePasswordButton: some View {
        VStack(spacing: 10) {
            Button {
                if !isGoogleUser {
                    showChangePasswordSheet = true
                }
            } label: {
                HStack(spacing: 15) {
                    Image(systemName: "key.horizontal")
                        .font(.system(size: 26))
                        .foregroundStyle(
                            isGoogleUser ? Color.secondary : Color.blue
                        )
                        .frame(width: 40)

                    Text("Change Password")
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundStyle(isGoogleUser ? .secondary : .primary)

                    Spacer()

                    if isGoogleUser {
                        Image(systemName: "lock.fill")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    } else {
                        Image(systemName: "chevron.right")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .buttonStyle(.plain)
            .glassEffect()
            .disabled(isGoogleUser)

            // Dynamic caption based on provider
            HStack(spacing: 8) {
                if isGoogleUser {
                    Image(systemName: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(
                        "Password is managed by Google and cannot be changed here."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                } else {
                    Text("Update your account password anytime.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.leading, 20)
            .animation(.easeInOut, value: isGoogleUser)
        }
    }

    // MARK: - Delete Account Button
    private var deleteAccountButton: some View {
        VStack(spacing: 10) {
            Button(role: .destructive) {
                showDeleteAccountSheet = true
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

                    Image(systemName: "chevron.right")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .buttonStyle(.plain)
            .glassEffect()

            HStack {
                Text(
                    "Submit a request to delete your account. An admin will review and process it."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.leading, 20)
        }
    }
}

// MARK: - SecurityInfo Model
struct SecurityInfo {
    let label: String
    let value: String
}

// MARK: - ChangePasswordView
struct ChangePasswordView: View {
    @Environment(\.dismiss) var dismiss
    @State private var currentPassword = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var errorMessage = ""
    @State private var isLoading = false
    @State private var showSuccess = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Fields group
                    VStack(spacing: 0) {
                        passwordField(
                            title: "Current Password",
                            text: $currentPassword,
                            contentType: .password
                        )

                        Divider().padding(.leading, 20)

                        passwordField(
                            title: "New Password",
                            text: $newPassword,
                            contentType: .newPassword
                        )

                        Divider().padding(.leading, 20)

                        passwordField(
                            title: "Confirm New",
                            text: $confirmPassword,
                            contentType: .newPassword
                        )
                    }
                    .glassEffect(in: .rect(cornerRadius: 16))
                    .padding(.horizontal)

                    // Validation hints
                    VStack(alignment: .leading, spacing: 6) {
                        validationHint(
                            text: "At least 6 characters",
                            passed: newPassword.count >= 6
                        )
                        validationHint(
                            text: "Passwords match",
                            passed: !confirmPassword.isEmpty
                                && newPassword == confirmPassword
                        )
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)

                    if !errorMessage.isEmpty {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.circle.fill")
                                .foregroundStyle(.red)
                            Text(errorMessage)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                        .padding(.horizontal, 24)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    // Confirm button
                    Button {
                        Task { await handleChangePassword() }
                    } label: {
                        Group {
                            if isLoading {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Text("Update Password")
                                    .fontWeight(.semibold)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                    }
                    .disabled(!isFormValid || isLoading)
                    .buttonStyle(.plain)
                    .glassEffect(
                        .regular.tint(isFormValid ? .blue : .gray)
                    )
                    .padding(.horizontal)
                }
                .padding(.vertical)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Change Password")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel", systemImage: "xmark") { dismiss() }
                }
            }
            .alert("Password Updated", isPresented: $showSuccess) {
                Button("OK") { dismiss() }
            } message: {
                Text("Your password has been changed successfully.")
            }
        }
    }

    private func passwordField(
        title: String,
        text: Binding<String>,
        contentType: UITextContentType
    ) -> some View {
        HStack(spacing: 15) {
            Text(title)
                .font(.body)
                .foregroundStyle(.primary)
                .frame(width: 110, alignment: .leading)

            SecureField("Required", text: text)
                .textContentType(contentType)
                .font(.body)
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private func validationHint(text: String, passed: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: passed ? "checkmark.circle.fill" : "circle")
                .font(.caption)
                .foregroundStyle(passed ? .green : .secondary)
            Text(text)
                .font(.caption)
                .foregroundStyle(passed ? .primary : .secondary)
        }
    }

    private var isFormValid: Bool {
        !currentPassword.isEmpty
            && newPassword.count >= 6
            && newPassword == confirmPassword
    }

    private func handleChangePassword() async {
        isLoading = true
        errorMessage = ""
        defer { isLoading = false }

        guard let user = Auth.auth().currentUser,
            let email = user.email
        else { return }

        // Re-authenticate before changing password
        let credential = EmailAuthProvider.credential(
            withEmail: email,
            password: currentPassword
        )

        do {
            try await user.reauthenticate(with: credential)
            try await user.updatePassword(to: newPassword)
            showSuccess = true
        } catch let error as NSError {
            switch error.code {
            case AuthErrorCode.wrongPassword.rawValue:
                errorMessage = "Current password is incorrect."
            case AuthErrorCode.weakPassword.rawValue:
                errorMessage = "New password is too weak."
            default:
                errorMessage = error.localizedDescription
            }
        }
    }
}

// MARK: - DeleteAccountRequestView
struct DeleteAccountRequestView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var authManager: AuthenticationManager

    @State private var reason = ""
    @State private var hasReadTerms = false
    @State private var isLoading = false
    @State private var errorMessage = ""
    @State private var showSuccess = false

    private let db = Firestore.firestore()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {

                    // Info header
                    VStack(spacing: 12) {
                        Image(systemName: "clock.badge.questionmark")
                            .font(.system(size: 48))
                            .foregroundStyle(.orange)

                        Text("Request Account Deletion")
                            .font(.title2.bold())
                            .foregroundStyle(.primary)

                        Text(
                            "Your request will be reviewed by an admin. You will be notified once it is processed."
                        )
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                    .glassEffect(in: .rect(cornerRadius: 16))
                    .padding(.horizontal)

                    // What will be deleted
                    VStack(alignment: .leading, spacing: 0) {
                        Text("What will be deleted")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 20)
                            .padding(.bottom, 10)

                        VStack(spacing: 0) {
                            deletionItem(
                                icon: "person.fill",
                                color: .blue,
                                text: "Your account and profile information"
                            )
                            Divider().padding(.leading, 60)
                            deletionItem(
                                icon: "doc.text.fill",
                                color: .orange,
                                text: "All submitted essays and writing history"
                            )
                            Divider().padding(.leading, 60)
                            deletionItem(
                                icon: "bell.fill",
                                color: .purple,
                                text: "All notifications and preferences"
                            )
                            Divider().padding(.leading, 60)
                            deletionItem(
                                icon: "chart.bar.fill",
                                color: .green,
                                text: "Your progress and learning statistics"
                            )
                            Divider().padding(.leading, 60)
                            deletionItem(
                                icon: "creditcard.fill",
                                color: .red,
                                text: "Active subscription will not be refunded"
                            )
                        }
                        .glassEffect(in: .rect(cornerRadius: 16))
                        .padding(.horizontal)
                    }

                    // Reason input (required)
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Reason")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text("*")
                                .font(.subheadline)
                                .foregroundStyle(.red)
                        }
                        .padding(.horizontal, 24)

                        TextField(
                            "Tell us why you want to leave...",
                            text: $reason,
                            axis: .vertical
                        )
                        .lineLimit(3...5)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                        .glassEffect(
                            in: .rect(cornerRadius: 16)
                        )
                        .padding(.horizontal)

                        // Validation hint
                        HStack(spacing: 6) {
                            Image(
                                systemName: isReasonValid
                                    ? "checkmark.circle.fill" : "info.circle"
                            )
                            .font(.caption)
                            .foregroundStyle(
                                isReasonValid ? .green : .secondary
                            )

                            Text(
                                isReasonValid
                                    ? "Thank you for your feedback"
                                    : "Please provide at least 10 characters"
                            )
                            .font(.caption)
                            .foregroundStyle(
                                isReasonValid ? .green : .secondary
                            )
                        }
                        .padding(.horizontal, 24)
                        .animation(.easeInOut, value: isReasonValid)
                    }

                    // Terms checkbox
                    Button {
                        withAnimation { hasReadTerms.toggle() }
                    } label: {
                        HStack(spacing: 12) {
                            Image(
                                systemName: hasReadTerms
                                    ? "checkmark.square.fill" : "square"
                            )
                            .font(.system(size: 20))
                            .foregroundStyle(hasReadTerms ? .blue : .secondary)

                            Text(
                                "I understand that once approved, my account and all associated data will be permanently deleted."
                            )
                            .font(.caption)
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)

                            Spacer()
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 14)
                    }
                    .buttonStyle(.plain)
                    .glassEffect()
                    .padding(.horizontal)

                    if !errorMessage.isEmpty {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.circle.fill")
                                .foregroundStyle(.red)
                            Text(errorMessage)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                        .padding(.horizontal, 24)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    // Submit request button
                    Button {
                        Task { await handleRequestDeletion() }
                    } label: {
                        Group {
                            if isLoading {
                                ProgressView().tint(.white)
                            } else {
                                Text("Submit Deletion Request")
                                    .fontWeight(.semibold)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                    }
                    .disabled(!hasReadTerms || !isReasonValid || isLoading)
                    .buttonStyle(.plain)
                    .glassEffect(
                        .regular.tint(
                            hasReadTerms && isReasonValid ? .orange : .gray
                        )
                    )
                    .padding(.horizontal)
                    .padding(.bottom)
                }
                .padding(.vertical)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Delete Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel", systemImage: "xmark") { dismiss() }
                }
            }
            .alert("Request Submitted", isPresented: $showSuccess) {
                Button("OK") {
                    // authManager listens to auth state change and navigates to login automatically
                }
            } message: {
                Text(
                    "Your account has been disabled and your deletion request has been sent. An admin will review and process it shortly."
                )
            }
        }
    }

    private var isReasonValid: Bool {
        reason.trimmingCharacters(in: .whitespacesAndNewlines).count >= 10
    }

    // MARK: - Deletion Item Row
    private func deletionItem(icon: String, color: Color, text: String)
        -> some View
    {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(color)
                .frame(width: 28)
                .padding(.leading, 20)

            Text(text)
                .font(.subheadline)
                .foregroundStyle(.primary)

            Spacer()
        }
        .padding(.vertical, 14)
    }

    private func handleRequestDeletion() async {
        isLoading = true
        errorMessage = ""
        defer { isLoading = false }

        guard let user = Auth.auth().currentUser,
            let uid = Auth.auth().currentUser?.uid,
            let userEmail = user.email
        else {
            errorMessage = "You are not signed in."
            return
        }

        do {
            // Step 1: Check existing request
            let existingDoc =
                try await db
                .collection("deleteRequests")
                .document(uid)
                .getDocument()

            if existingDoc.exists {
                let currentStatus =
                    existingDoc.data()?["status"] as? String ?? ""
                if currentStatus == "pending" {
                    errorMessage =
                        "You already have a pending deletion request. Please wait for admin review."
                    return
                } else if currentStatus == "approved" {
                    errorMessage =
                        "Your deletion request has already been approved."
                    return
                }
            }

            let trimmedReason = reason.trimmingCharacters(
                in: .whitespacesAndNewlines
            )

            // Step 2: Write delete request to Firestore
            let requestData: [String: Any] = [
                "requestedAt": Timestamp(date: Date()),
                "status": "pending",
                "reason": trimmedReason,
            ]
            try await db
                .collection("deleteRequests")
                .document(uid)
                .setData(requestData)

            // Step 3: Disable user in Firestore
            try await db
                .collection("users")
                .document(uid)
                .updateData(["isDisabled": true])

            // Step 4: Send email to admin via Trigger Email extension
            try await sendDeletionRequestEmail(
                userEmail: userEmail,
                userUID: uid,
                reason: trimmedReason
            )

            // Step 5: Sign out
            try Auth.auth().signOut()

            showSuccess = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Send admin notification email via Firestore Trigger Email extension
    private func sendDeletionRequestEmail(
        userEmail: String,
        userUID: String,
        reason: String
    ) async throws {
        let adminEmail = "vinhhaphoi@gmail.com"
        let reasonText = reason.isEmpty ? "No reason provided" : reason

        let emailData: [String: Any] = [
            "to": [adminEmail],
            "message": [
                "subject": "[VSTEP Writing] Account Deletion Request",
                "html": """
                <h2>Account Deletion Request</h2>
                <p>A user has submitted a request to delete their account.</p>
                <table>
                    <tr><td><b>Email:</b></td><td>\(userEmail)</td></tr>
                    <tr><td><b>User UID:</b></td><td>\(userUID)</td></tr>
                    <tr><td><b>Reason:</b></td><td>\(reasonText)</td></tr>
                    <tr><td><b>Submitted at:</b></td><td>\(Date().formatted())</td></tr>
                </table>
                <p>Please review this request in the Firebase Console.</p>
                """,
            ],
        ]

        // Write to 'mail' collection — Trigger Email extension picks it up automatically
        try await db.collection("mail").addDocument(data: emailData)
    }
}
