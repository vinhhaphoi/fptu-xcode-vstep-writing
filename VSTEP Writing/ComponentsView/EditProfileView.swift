// EditProfileView.swift

import FirebaseAuth
import FirebaseFirestore
import SwiftUI

struct EditProfileView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @Environment(\.dismiss) var dismiss

    @State private var displayName = ""
    @State private var targetLevel = ""
    @State private var email = ""
    @State private var role = ""

    @State private var isLoading = false
    @State private var isSaving = false
    @State private var errorMessage = ""
    @State private var showSuccess = false

    @State private var originalDisplayName = ""
    @State private var originalTargetLevel = ""

    private let targetLevels = ["B1", "B2", "C1"]
    private let db = Firestore.firestore()

    private var hasChanges: Bool {
        displayName != originalDisplayName || targetLevel != originalTargetLevel
    }

    private var roleColor: Color {
        switch role.lowercased() {
        case "admin": return .red
        case "teacher": return .orange
        default: return .blue
        }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                editableSection
                    .padding(.bottom, 28)

                readOnlySection
                    .padding(.bottom, 28)

                if !errorMessage.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundStyle(.red)
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 16)
                }

                saveButton

                Spacer(minLength: 40)
            }
            .padding(.vertical)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Edit your VSTEP account")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.ultraThinMaterial)
            }
        }
        .task { await loadUserData() }
        .alert("Profile Updated", isPresented: $showSuccess) {
            Button("OK") { dismiss() }
        } message: {
            Text("Your profile has been updated successfully.")
        }
    }

    // MARK: - Editable Section
    private var editableSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Edit Information")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 24)

            VStack(spacing: 0) {
                // Display Name
                HStack(spacing: 14) {
                    Image(systemName: "person.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(.blue)
                        .frame(width: 24)

                    Text("Name")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .frame(width: 70, alignment: .leading)

                    TextField("Display name", text: $displayName)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .autocorrectionDisabled()
                        .multilineTextAlignment(.trailing)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)

                Divider().padding(.leading, 58)

                // Target Level
                HStack(spacing: 14) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.system(size: 15))
                        .foregroundStyle(.green)
                        .frame(width: 24)

                    Text("Target")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .frame(width: 70, alignment: .leading)

                    Spacer()

                    Picker("", selection: $targetLevel) {
                        ForEach(targetLevels, id: \.self) { level in
                            Text(level).tag(level)
                        }
                    }
                    .pickerStyle(.menu)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
            }
            .glassEffect(in: .rect(cornerRadius: 16))
            .padding(.horizontal)
        }
    }

    // MARK: - Read-only Section
    private var readOnlySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Account Information")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 24)

            VStack(spacing: 0) {
                readOnlyRow(
                    icon: "envelope.fill",
                    color: .orange,
                    label: "Email",
                    value: email
                )

                Divider().padding(.leading, 58)

                readOnlyRow(
                    icon: "shield.fill",
                    color: .purple,
                    label: "Role",
                    value: role.capitalized
                )
            }
            .glassEffect(in: .rect(cornerRadius: 16))
            .padding(.horizontal)

            HStack(spacing: 4) {
                Image(systemName: "lock.fill")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Text("These fields cannot be changed.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 24)
        }
    }

    private func readOnlyRow(
        icon: String,
        color: Color,
        label: String,
        value: String
    ) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundStyle(color)
                .frame(width: 24)

            Text(label)
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(width: 70, alignment: .leading)

            Spacer()

            Text(value.isEmpty ? "—" : value)
                .font(.body)
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    // MARK: - Save Button
    private var saveButton: some View {
        Button {
            Task { await saveProfile() }
        } label: {
            Group {
                if isSaving {
                    ProgressView()
                } else {
                    Text("Save Changes")
                        .fontWeight(.semibold)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
        }
        .disabled(isSaving || !hasChanges)
        .buttonStyle(.plain)
        .glassEffect()
        .padding(.horizontal)
    }

    // MARK: - Actions
    private func loadUserData() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let doc =
                try await db
                .collection("users")
                .document(uid)
                .getDocument()
            let data = doc.data() ?? [:]

            await MainActor.run {
                displayName = data["displayName"] as? String ?? ""
                email =
                    data["email"] as? String ?? Auth.auth().currentUser?.email
                    ?? ""
                role = data["role"] as? String ?? "user"
                targetLevel = data["targetLevel"] as? String ?? "B1"
                originalDisplayName = displayName
                originalTargetLevel = targetLevel
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func saveProfile() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }

        let trimmedName = displayName.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else {
            errorMessage = "Display name cannot be empty."
            return
        }

        isSaving = true
        errorMessage = ""
        defer { isSaving = false }

        do {
            try await db.collection("users").document(uid).updateData([
                "displayName": trimmedName,
                "targetLevel": targetLevel,
                "updatedAt": FieldValue.serverTimestamp(),
            ])

            let changeRequest = Auth.auth().currentUser?
                .createProfileChangeRequest()
            changeRequest?.displayName = trimmedName
            try await changeRequest?.commitChanges()

            await MainActor.run {
                originalDisplayName = trimmedName
                originalTargetLevel = targetLevel
                displayName = trimmedName
            }

            showSuccess = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
