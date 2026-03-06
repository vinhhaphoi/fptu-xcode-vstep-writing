import FirebaseAuth
import FirebaseFirestore
import PhotosUI
import SwiftUI

struct ProfileView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @EnvironmentObject var firebaseService: FirebaseService
    @AppStorage("isDarkMode") private var isDarkMode = false

    // Navigation States
    @State private var showSettings = false
    @State private var showEditProfile = false
    @State private var selectedPolicy: PolicyType? = nil
    @State private var showLogoutAlert = false
    @State private var showContactUs = false
    @State private var showSubscription = false

    // Photo Upload States
    @State private var showImagePicker = false
    @State private var selectedImage: PhotosPickerItem?
    @State private var localAvatarPreview: Image?

    // Subscription States
    @State private var subscriptionStatus: String? = nil
    @State private var subscriptionProductID: String? = nil
    @State private var subscriptionExpiry: Date? = nil
    @State private var isLoadingSubscription = true
    @State private var alertMessage: AlertMessage?

    private let db = Firestore.firestore()

    var body: some View {
        ScrollView {
            profileHeaderCard
                .padding()

            subscriptionStatusCard
                .padding(.horizontal)
                .padding(.bottom, 4)

            policyButtons
                .padding()

            darkModeToggle
                .padding()

            ContactInfoButton
                .padding()

            signOutButton
                .padding()

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
        .refreshable {
            await refreshProfile()
        }
        .onChange(of: selectedImage) { _, newItem in
            Task { await handleImageSelection(newItem) }
        }
        // Show error alert from FirebaseService avatar upload
        .onChange(of: firebaseService.avatarUploadError) { _, errorMsg in
            guard let errorMsg else { return }
            alertMessage = AlertMessage(title: "Error", message: errorMsg)
        }
        // Show success alert when upload completes
        .onChange(of: firebaseService.isUploadingPhoto) { _, isUploading in
            guard !isUploading, firebaseService.uploadedAvatarURL != nil,
                firebaseService.avatarUploadError == nil
            else { return }
            alertMessage = AlertMessage(
                title: "Success",
                message: "Profile photo updated!"
            )
        }
        .navigationTitle("Profile")
        .toolbarTitleDisplayMode(.large)
        .alert("Sign out", isPresented: $showLogoutAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Sign out", role: .destructive) { handleLogout() }
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
        .navigationDestination(isPresented: $showSettings) { SettingsView() }
        .navigationDestination(isPresented: $showContactUs) {
            ContactInfoView()
        }
        .navigationDestination(isPresented: $showEditProfile) {
            EditProfileView()
        }
        .navigationDestination(isPresented: $showSubscription) {
            SubscriptionsView()
        }
        .navigationDestination(item: $selectedPolicy) { policyType in
            switch policyType {
            case .termsOfUse: TermsOfUseView()
            case .privacyPolicy: PrivacyPolicyView()
            }
        }
        .toolbar { ToolBarItems }
        .task {
            await loadSubscription()
            await firebaseService.fetchAvatarURL()
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
            ZStack(alignment: .bottomTrailing) {
                avatarView
                    .frame(width: 120, height: 120)
                    .clipShape(Circle())
                    .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
                    .overlay {
                        if firebaseService.isUploadingPhoto {
                            ZStack {
                                Circle().fill(.ultraThinMaterial)
                                ProgressView()
                            }
                        }
                    }

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
                .disabled(firebaseService.isUploadingPhoto)
                .offset(x: -2, y: -2)
            }
        }
        .padding(.vertical, 28)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Avatar View
    // Priority: local preview -> uploaded URL -> Firebase Auth URL -> placeholder
    @ViewBuilder
    private var avatarView: some View {
        if let localPreview = localAvatarPreview {
            localPreview.resizable().scaledToFill()
        } else if let urlString = firebaseService.uploadedAvatarURL,
            let url = URL(string: urlString)
        {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image): image.resizable().scaledToFill()
                case .failure: avatarPlaceholder
                case .empty: ProgressView()
                @unknown default: avatarPlaceholder
                }
            }
        } else if let photoURL = authManager.user?.photoURL {
            // Fallback to Firebase Auth photoURL (Google Sign In)
            AsyncImage(url: photoURL) { phase in
                switch phase {
                case .success(let image): image.resizable().scaledToFill()
                case .failure: avatarPlaceholder
                case .empty: ProgressView()
                @unknown default: avatarPlaceholder
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

    // MARK: - Subscription Status Card
    private var subscriptionStatusCard: some View {
        VStack(spacing: 10) {
            if isLoadingSubscription {
                HStack(spacing: 15) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.secondary.opacity(0.2))
                        .frame(width: 28, height: 28)
                        .frame(width: 40)
                    VStack(alignment: .leading, spacing: 6) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.secondary.opacity(0.2))
                            .frame(width: 120, height: 14)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.secondary.opacity(0.15))
                            .frame(width: 80, height: 11)
                    }
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .glassEffect()

            } else if subscriptionStatus == "active",
                let productID = subscriptionProductID
            {
                Button {
                    showSubscription = true
                } label: {
                    HStack(spacing: 15) {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(.yellow)
                            .frame(width: 40)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(planDisplayName(for: productID))
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(.primary)
                            if let expiry = subscriptionExpiry {
                                Text(
                                    "Renews \(expiry.formatted(.dateTime.day().month(.wide).year()))"
                                )
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                        }
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

            } else {
                Button {
                    showSubscription = true
                } label: {
                    HStack(spacing: 15) {
                        Image(systemName: "crown")
                            .font(.system(size: 22))
                            .foregroundStyle(.secondary)
                            .frame(width: 40)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("No Active Plan")
                                .font(.system(size: 17, weight: .regular))
                                .foregroundStyle(.primary)
                            Text("Upgrade to unlock all features")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
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
        }
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
                            .font(.system(size: 24))
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
                    Divider().padding(.leading, 70)
                }
            }
        }
        .glassEffect(in: .rect(cornerRadius: 16.0))
    }

    private var policyList: [PolicyInfo] {
        [
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
                .font(.system(size: 24))
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
                    .font(.system(size: 24))
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

    // MARK: - Contact Button
    private var ContactInfoButton: some View {
        Button {
            showContactUs = true
        } label: {
            HStack(spacing: 15) {
                Image(systemName: "info.circle")
                    .font(.system(size: 24))
                    .foregroundStyle(.blue)
                    .frame(width: 40)
                Text("Contact us")
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(.primary)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .buttonStyle(.plain)
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

    // MARK: - Firebase
    private func loadSubscription() async {
        guard let userID = Auth.auth().currentUser?.uid else {
            isLoadingSubscription = false
            return
        }

        do {
            let doc = try await db.collection("subscriptions").document(userID)
                .getDocument()
            let data = doc.data()

            await MainActor.run {
                subscriptionStatus = data?["status"] as? String
                subscriptionProductID = data?["productID"] as? String
                subscriptionExpiry = (data?["expiryDate"] as? Timestamp)?
                    .dateValue()
                isLoadingSubscription = false
            }
        } catch {
            await MainActor.run { isLoadingSubscription = false }
        }
    }

    private func planDisplayName(for productID: String) -> String {
        switch productID {
        case "com.vstep.advanced": return "Advanced Plan"
        case "com.vstep.premier": return "Premier Plan"
        default: return "Premium Plan"
        }
    }

    // MARK: - Actions
    private func handleLogout() {
        do {
            try authManager.signOut()
        } catch {
            print("Logout error: \(error.localizedDescription)")
        }
    }
    private func refreshProfile() async {
        await withTaskGroup(of: Void.self) { group in
            // Reload subscription status
            group.addTask { await self.loadSubscription() }
            // Reload avatar URL from Firestore
            group.addTask { await self.firebaseService.fetchAvatarURL() }
            // Reload user progress if needed
            group.addTask {
                try? await self.firebaseService.fetchUserProgress()
            }
        }
    }

    // MARK: - Actions
    private func handleImageSelection(_ item: PhotosPickerItem?) async {
        guard let item else { return }

        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                let uiImage = UIImage(data: data)
            else {
                alertMessage = AlertMessage(
                    title: "Error",
                    message: "Failed to load selected image."
                )
                return
            }

            // Show local preview immediately without waiting for upload
            localAvatarPreview = Image(uiImage: uiImage)
            firebaseService.isUploadingPhoto = true
            firebaseService.avatarUploadError = nil

            let newURL = try await firebaseService.uploadAvatar(image: uiImage)

            firebaseService.isUploadingPhoto = false
            localAvatarPreview = nil
            alertMessage = AlertMessage(
                title: "Success",
                message: "Profile photo updated!"
            )

            print("[ProfileView] Avatar upload success — URL: \(newURL)")
        } catch {
            firebaseService.isUploadingPhoto = false
            localAvatarPreview = nil
            alertMessage = AlertMessage(
                title: "Error",
                message: error.localizedDescription
            )
        }
    }

}
