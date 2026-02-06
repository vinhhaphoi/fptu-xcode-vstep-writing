import FirebaseAuth
import PhotosUI
import SwiftUI

struct ProfileView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @AppStorage("isDarkMode") private var isDarkMode = false

    // Navigation States
    @State private var showSettings = false
    @State private var showEditProfile = false
    @State private var selectedPolicy: PolicyType? = nil
    @State private var showLogoutAlert = false

    // Photo Upload States
    @State private var showImagePicker = false
    @State private var selectedImage: PhotosPickerItem?
    @State private var avatarImage: Image?
    @State private var isUploadingPhoto = false
    @State private var alertMessage: AlertMessage?

    var body: some View {
        ScrollView {
            // Header Card với Avatar
            profileHeaderCard
                .padding()

//            // Contact Info
//            contactInfoSection
//                .padding()

//            // Edit Profile Button
//            editProfileButton
//                .padding()

//            // Settings Button
//            settingsButton
//                .padding()

            // Policy Buttons
            policyButtons
                .padding()

            // Dark Mode Toggle
            darkModeToggle
                .padding()

            // Sign Out Button
            signOutButton
                .padding()

            // App Info Footer
            appInfoFooter
                .padding(.top, 20)
                .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .contentMargins(.bottom, 60)
        .background(Color(.systemGroupedBackground))
        .photosPicker(
            isPresented: $showImagePicker,
            selection: $selectedImage,
            matching: .images
        )
        .onChange(of: selectedImage) { oldValue, newValue in
            Task { await handleImageSelection(newValue) }
        }
        .alert("Sign out", isPresented: $showLogoutAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Sign out", role: .destructive) {
                handleLogout()
            }
        } message: {
            Text("Are you confirm to sign out?")
        }
        .alert(item: $alertMessage) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("OK"))
            )
        }
        .navigationDestination(isPresented: $showSettings) {
            SettingsView()
        }
        .navigationDestination(isPresented: $showEditProfile) {
            EditProfileView()
        }
        .navigationDestination(item: $selectedPolicy) { policyType in
            switch policyType {
            case .termsOfUse:
                TermsOfUseView()
            case .privacyPolicy:
                PrivacyPolicyView()
            }
        }
        .toolbar {
            ToolBarItems
        }
    }

    // MARK: - Toolbar
    @ToolbarContentBuilder
    private var ToolBarItems: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape")
            }
        }
    }

    // MARK: - Profile Header Card
    private var profileHeaderCard: some View {
        VStack(spacing: 20) {
            // Avatar
            ZStack(alignment: .bottomTrailing) {
                avatarView
                    .frame(width: 120, height: 120)
                    .clipShape(Circle())
                    .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
                    .overlay {
                        if isUploadingPhoto {
                            ZStack {
                                Circle()
                                    .fill(.ultraThinMaterial)
                                ProgressView()
                            }
                        }
                    }

                // Edit Photo Button (Small icon overlay)
                Button {
                    showImagePicker = true
                } label: {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.white)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(Color.blue))
                        .shadow(radius: 3)
                }
                .disabled(isUploadingPhoto)
                .offset(x: -2, y: -2)
            }
        }
        .padding(.vertical, 28)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Avatar View
    @ViewBuilder
    private var avatarView: some View {
        if let avatarImage {
            avatarImage
                .resizable()
                .scaledToFill()
        } else if let photoURL = authManager.user?.photoURL {
            AsyncImage(url: photoURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                case .failure:
                    avatarPlaceholder
                case .empty:
                    ProgressView()
                @unknown default:
                    avatarPlaceholder
                }
            }
        } else {
            avatarPlaceholder
        }
    }

    private var avatarPlaceholder: some View {
        Circle()
            .fill(Color.blue.gradient)
            .overlay {
                Image(systemName: "person.fill")
                    .font(.system(size: 48, weight: .medium))
                    .foregroundColor(.white)
            }
    }

    // Bỏ hẳn RemoteImageView struct - Không cần!

    // MARK: - Contact Info Section
    private var contactInfoSection: some View {
        VStack(spacing: 0) {
            ForEach(Array(contactInfoList.enumerated()), id: \.offset) {
                index,
                contact in
                HStack(spacing: 15) {
                    Image(systemName: contact.icon)
                        .font(.system(size: 26))
                        .foregroundStyle(contact.iconColor)
                        .frame(width: 40)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(contact.label)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text(contact.value)
                            .font(.system(size: 17, weight: .regular))
                            .foregroundStyle(.primary)
                    }

                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)

                if index != contactInfoList.count - 1 {
                    Divider()
                        .padding(.leading, 70)
                }
            }
        }
        .glassEffect(in: .rect(cornerRadius: 16.0))
    }

    private var contactInfoList: [ContactInfo] {
        var items: [ContactInfo] = []

        // Email
        let emailValue = authManager.user?.email ?? "Email not available"
        items.append(
            ContactInfo(
                icon: "envelope.badge.person.crop",
                iconColor: .primary,
                label: "Email",
                value: emailValue
            )
        )

        // UID (for development/debugging)
        if let uid = authManager.user?.uid {
            items.append(
                ContactInfo(
                    icon: "number",
                    iconColor: .primary,
                    label: "User ID",
                    value: String(uid.prefix(12)) + "..."
                )
            )
        }

        return items
    }

    // MARK: - Edit Profile Button
    private var editProfileButton: some View {
        Button {
            showEditProfile = true
        } label: {
            HStack(spacing: 15) {
                Image(systemName: "pencil.line")
                    .font(.system(size: 26))
                    .foregroundStyle(.primary)
                    .frame(width: 40)

                Text("Edit Profile")
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(.primary)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .buttonStyle(.plain)
        .glassEffect()
    }

    // MARK: - Settings Button
    private var settingsButton: some View {
        Button {
            showSettings = true
        } label: {
            HStack(spacing: 15) {
                Image(systemName: "gear")
                    .font(.system(size: 26))
                    .foregroundStyle(.primary)
                    .frame(width: 40)

                Text("Settings")
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(.primary)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .buttonStyle(.plain)
        .glassEffect()
    }

    // MARK: - Policy Buttons
    private var policyButtons: some View {
        VStack(spacing: 0) {
            ForEach(Array(policyList.enumerated()), id: \.offset) {
                index,
                policy in
                Button {
                    selectedPolicy = policy.type
                } label: {
                    HStack(spacing: 15) {
                        Image(systemName: policy.icon)
                            .font(.system(size: 26))
                            .foregroundStyle(policy.iconColor)
                            .frame(width: 40)

                        Text(policy.title)
                            .font(.system(size: 17, weight: .regular))
                            .foregroundStyle(.primary)

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                }
                .buttonStyle(.plain)

                if index != policyList.count - 1 {
                    Divider()
                        .padding(.leading, 70)
                }
            }
        }
        .glassEffect(in: .rect(cornerRadius: 16.0))
    }

    private var policyList: [PolicyInfo] {
        return [
            PolicyInfo(
                icon: "newspaper",
                iconColor: .blue,
                title: "Terms of Use",
                type: .termsOfUse
            ),
            PolicyInfo(
                icon: "hand.raised",
                iconColor: .purple,
                title: "Privacy Policy",
                type: .privacyPolicy
            ),
        ]
    }

    // MARK: - Dark Mode Toggle
    private var darkModeToggle: some View {
        HStack(spacing: 15) {
            Image(systemName: isDarkMode ? "moon.stars.fill" : "sun.max.fill")
                .font(.system(size: 26))
                .foregroundStyle(isDarkMode ? .indigo : .orange)
                .frame(width: 40)
                .contentTransition(.symbolEffect(.replace))

            Text("Dark Mode")
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(.primary)

            Spacer()

            Toggle("", isOn: $isDarkMode.animation(.easeInOut(duration: 0.3)))
                .labelsHidden()
                .tint(.accentColor)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .glassEffect()
    }

    // MARK: - Sign Out Button
    private var signOutButton: some View {
        Button(role: .destructive) {
            showLogoutAlert = true
        } label: {
            HStack(spacing: 15) {
                Image(systemName: "rectangle.portrait.and.arrow.forward")
                    .font(.system(size: 26))
                    .foregroundStyle(.red)
                    .frame(width: 40)

                Text("Sign Out")
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(.primary)

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .glassEffect()
    }

    // MARK: - App Info Footer
    private var appInfoFooter: some View {
        VStack(spacing: 6) {
            Text("VSTEP Writing")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("Version 1.0.0")
                .font(.caption)
                .foregroundStyle(.tertiary)
            
            Text("Powered by Vinhhaphoi from NTHT x Vinhhaphoi")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("© 2026 All rights reserved")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .multilineTextAlignment(.center)
    }

    // MARK: - Actions
    private func handleLogout() {
        do {
            try authManager.signOut()
            print("✅ Logged out successfully")
        } catch {
            print("❌ Logout error: \(error.localizedDescription)")
        }
    }

    private func handleImageSelection(_ item: PhotosPickerItem?) async {
        guard let item = item else { return }

        do {
            if let data = try await item.loadTransferable(type: Data.self),
                let uiImage = UIImage(data: data)
            {
                await MainActor.run {
                    avatarImage = Image(uiImage: uiImage)
                    isUploadingPhoto = true
                }

                // TODO: Upload to Firebase Storage
                // For now, just simulate upload
                try? await Task.sleep(nanoseconds: 2_000_000_000)

                await MainActor.run {
                    isUploadingPhoto = false
                    alertMessage = AlertMessage(
                        title: "Success",
                        message: "Profile photo updated!"
                    )
                }
            }
        } catch {
            await MainActor.run {
                isUploadingPhoto = false
                avatarImage = nil
                alertMessage = AlertMessage(
                    title: "Error",
                    message: "Failed to load image"
                )
            }
        }
    }
}

// MARK: - Supporting Models
struct ContactInfo: Identifiable {
    let id = UUID()
    let icon: String
    let iconColor: Color
    let label: String
    let value: String
}

struct PolicyInfo: Identifiable {
    let id = UUID()
    let icon: String
    let iconColor: Color
    let title: String
    let type: PolicyType
}

enum PolicyType: String, Identifiable {
    case termsOfUse = "Terms of Use"
    case privacyPolicy = "Privacy Policy"

    var id: String { rawValue }
}

struct AlertMessage: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

struct EditProfileView: View {
    @Environment(\.dismiss) var dismiss

    var body: some View {
        Text("Edit Profile")
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
    }
}

struct TermsOfUseView: View {
    var body: some View {
        ScrollView {
            Text("Terms of Use content...")
                .padding()
        }
        .navigationTitle("Terms of Use")
    }
}

struct PrivacyPolicyView: View {
    var body: some View {
        ScrollView {
            Text("Privacy Policy content...")
                .padding()
        }
        .navigationTitle("Privacy Policy")
    }
}
