import FirebaseAuth
import FirebaseFirestore
import PhotosUI
import SwiftUI

struct ProfileView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @EnvironmentObject var firebaseService: FirebaseService
    @Environment(StoreKitManager.self) private var store
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
    private var usageManager: AIUsageManager { AIUsageManager.shared }

    var body: some View {
        ScrollView {
            profileHeaderCard
                .padding()

            subscriptionStatusCard
                .padding(.horizontal)
                .padding(.bottom, 4)

            quotaCard
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
        .refreshable { await refreshProfile() }
        .onChange(of: selectedImage) { _, newItem in
            Task { await handleImageSelection(newItem) }
        }
        .onChange(of: firebaseService.avatarUploadError) { _, errorMsg in
            guard let errorMsg else { return }
            alertMessage = AlertMessage(title: "Error", message: errorMsg)
        }
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
            await usageManager.loadInitialData()
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
                    .foregroundStyle(BrandColor.primary)
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
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(BrandColor.primary))
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
            .fill(BrandColor.primary.gradient)
            .overlay {
                Image(systemName: "person.fill")
                    .font(.system(size: 48, weight: .medium))
                    .foregroundStyle(.white)
            }
    }

    // MARK: - Subscription Status Card
    private var subscriptionStatusCard: some View {
        VStack(spacing: 10) {
            if isLoadingSubscription {
                HStack(spacing: 15) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(BrandColor.muted)
                        .frame(width: 28, height: 28)
                        .frame(width: 40)
                    VStack(alignment: .leading, spacing: 6) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(BrandColor.muted.opacity(0.9))
                            .frame(width: 120, height: 14)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(BrandColor.muted.opacity(0.7))
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
                            .foregroundStyle(BrandColor.soft)
                            .frame(width: 40)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(planDisplayName(for: productID))
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(BrandColor.primary)
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
                            .foregroundStyle(BrandColor.medium)
                            .frame(width: 40)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("No Active Plan")
                                .font(.system(size: 17, weight: .regular))
                                .foregroundStyle(BrandColor.primary)
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

    // MARK: - Quota Card (đã có BrandColor ở lần trước)
    private var quotaCard: some View {
        let limits = usageManager.limits(for: store)
        let isFree =
            !store.isPurchased("com.vstep.advanced")
            && !store.isPurchased("com.vstep.premier")

        return VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "gauge.with.dots.needle.67percent")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(BrandColor.primary)
                Text("Today's Usage")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(BrandColor.primary)
                Spacer()
                Text("Resets at midnight")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 12)

            Divider().padding(.horizontal, 20)

            quotaRow(
                icon: "doc.text.fill",
                iconColor: BrandColor.primary,
                title: "Essays per day",
                used: usageManager.dailyUsage.totalEssaysGradedToday,
                total: limits.maxEssaysPerDay,
                isUnlimited: limits.maxEssaysPerDay == Int.max
            )

            Divider().padding(.leading, 68)

            let avgGradingUsed =
                usageManager.dailyUsage.gradingAttemptsPerEssay.values.max()
                ?? 0
            quotaRow(
                icon: "brain.head.profile",
                iconColor: BrandColor.medium,
                title: "AI grading per essay",
                used: avgGradingUsed,
                total: limits.gradingAttemptsPerEssay,
                isUnlimited: limits.gradingAttemptsPerEssay == Int.max
            )

            Divider().padding(.leading, 68)

            quotaRow(
                icon: "bubble.left.and.bubble.right.fill",
                iconColor: BrandColor.soft,
                title: "Chatbot questions",
                used: usageManager.dailyUsage.chatbotQuestionsToday,
                total: limits.chatbotQuestionsPerDay,
                isUnlimited: false,
                isLocked: isFree
            )

            Divider().padding(.leading, 68)

            let currentWeek = AIUsageManager.isoWeekKey()
            let insightUsed =
                usageManager.weeklyInsightUsage.weekKey == currentWeek
                ? usageManager.weeklyInsightUsage.usedCount : 0

            quotaRow(
                icon: "chart.bar.doc.horizontal.fill",
                iconColor: BrandColor.light,
                title: "AI insight refreshes",
                used: insightUsed,
                total: limits.insightRefreshesPerWeek,
                isUnlimited: false,
                isLocked: isFree,
                isWeekly: true,
                isLast: true
            )
        }
        .glassEffect(in: .rect(cornerRadius: 16.0))
    }

    private func quotaRow(
        icon: String,
        iconColor: Color,
        title: String,
        used: Int,
        total: Int,
        isUnlimited: Bool,
        isLocked: Bool = false,
        isWeekly: Bool = false,
        isLast: Bool = false
    ) -> some View {
        let remaining = max(0, total - used)
        let progress =
            isUnlimited || total == 0
            ? 1.0 : min(Double(used) / Double(total), 1.0)
        let isExhausted = !isUnlimited && !isLocked && remaining == 0

        return VStack(spacing: 0) {
            HStack(spacing: 14) {
                Image(systemName: isLocked ? "lock.fill" : icon)
                    .font(.system(size: 18))
                    .foregroundStyle(isLocked ? Color.secondary : iconColor)
                    .frame(width: 28)
                    .padding(.leading, 20)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Text(title)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(isLocked ? .secondary : .primary)

                        if isWeekly {
                            Text("/ week")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .glassEffect(in: .capsule)
                        }

                        Spacer()

                        if isLocked {
                            Text("Upgrade")
                                .font(.caption2.bold())
                                .foregroundStyle(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(BrandColor.primary))
                        } else if isUnlimited {
                            Label("Unlimited", systemImage: "infinity")
                                .font(.caption2.bold())
                                .foregroundStyle(BrandColor.light)
                        } else {
                            Text(isExhausted ? "Used up" : "\(remaining) left")
                                .font(.caption2.bold())
                                .foregroundStyle(
                                    isExhausted ? Color.red : BrandColor.medium
                                )
                        }
                    }

                    if !isLocked && !isUnlimited && total > 0 {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(BrandColor.muted.opacity(0.7))
                                    .frame(height: 5)
                                Capsule()
                                    .fill(
                                        isExhausted
                                            ? Color.red
                                            : progress > 0.75
                                                ? Color.orange : iconColor
                                    )
                                    .frame(
                                        width: geo.size.width * progress,
                                        height: 5
                                    )
                                    .animation(
                                        .easeOut(duration: 0.5),
                                        value: progress
                                    )
                            }
                        }
                        .frame(height: 5)

                        Text("\(used) / \(total) used")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else if isUnlimited {
                        Text("\(used) used today")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.trailing, 20)
            }
            .padding(.vertical, 14)
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
                iconColor: BrandColor.primary,
                title: "Terms of Use",
                type: .termsOfUse
            ),
            PolicyInfo(
                icon: "hand.raised",
                iconColor: BrandColor.light,
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
                .foregroundStyle(isDarkMode ? BrandColor.medium : .orange)
                .frame(width: 40)
                .contentTransition(.symbolEffect(.replace))
            Text("Dark Mode")
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(.primary)
            Spacer()
            Toggle("", isOn: $isDarkMode.animation(.easeInOut(duration: 0.3)))
                .labelsHidden()
                .tint(BrandColor.primary)
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
                    .foregroundStyle(BrandColor.primary)
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

    private func handleLogout() {
        do {
            try authManager.signOut()
        } catch {
            print("Logout error: \(error.localizedDescription)")
        }
    }

    private func refreshProfile() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.loadSubscription() }
            group.addTask { await self.firebaseService.fetchAvatarURL() }
            group.addTask {
                try? await self.firebaseService.fetchUserProgress()
            }
            group.addTask { await self.usageManager.loadInitialData() }
        }
    }

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
