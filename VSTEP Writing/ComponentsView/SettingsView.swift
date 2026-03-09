// SettingsView.swift

import SwiftUI
import UserNotifications

struct SettingsView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(LanguageManager.self) private var languageManager
    @AppStorage("isDarkMode") private var isDarkMode = false
    @EnvironmentObject var authManager: AuthenticationManager

    @State private var navigateToSecurity = false
    @State private var navigateToSubscription = false
    @State private var navigateToEditProfile = false
    @State private var isNotificationOn = false

    var body: some View {
        ScrollView {
            EditProfileButton
                .padding()

            securityButton
                .padding()

            subscriptionsButton
                .padding()

            languageButton
                .padding()

            notificationToggle
                .padding()

            if BiometricAuthService.shared.isAvailable {
                faceIDToggle
                    .padding()
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.large)
        .navigationDestination(isPresented: $navigateToEditProfile) {
            EditProfileView()
        }
        .navigationDestination(isPresented: $navigateToSecurity) {
            SecuritiesInfoView()
        }
        .navigationDestination(isPresented: $navigateToSubscription) {
            SubscriptionsView()
        }
        .task {
            await syncNotificationStatus()
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: UIApplication.willEnterForegroundNotification
            )
        ) { _ in
            Task { await syncNotificationStatus() }
        }
    }

    // MARK: - Language Toggle
    private var languageButton: some View {
        VStack(spacing: 10) {
            HStack(spacing: 15) {
                Text(languageManager.currentLanguage.flag)
                    .font(.system(size: 26))
                    .frame(width: 40)
                    .contentTransition(.symbolEffect(.replace))

                Text("Language")
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(.primary)

                Spacer()

                Toggle(
                    "",
                    isOn: Binding(
                        get: { languageManager.currentLanguage == .vietnamese },
                        set: { isVietnamese in
                            languageManager.setLanguage(
                                isVietnamese ? .vietnamese : .english
                            )
                        }
                    )
                )
                .labelsHidden()
                .tint(.accentColor)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .glassEffect()

            HStack(spacing: 8) {
                if languageManager.currentLanguage == .vietnamese {
                    Text("App is displaying in Vietnamese")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("App is displaying in English")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.leading, 20)
            .animation(
                .easeInOut,
                value: languageManager.currentLanguage.rawValue
            )
        }
    }

    // MARK: - Notification Toggle
    private var notificationToggle: some View {
        VStack(spacing: 10) {
            HStack(spacing: 15) {
                Image(
                    systemName: isNotificationOn
                        ? "bell.fill" : "bell.slash.fill"
                )
                .font(.system(size: 26))
                .foregroundStyle(isNotificationOn ? .orange : .secondary)
                .frame(width: 40)
                .contentTransition(.symbolEffect(.replace))

                Text("Notifications")
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(.primary)

                Spacer()

                Toggle(
                    "",
                    isOn: Binding(
                        get: { isNotificationOn },
                        set: { newValue in
                            Task { await handleNotificationToggle(newValue) }
                        }
                    )
                )
                .labelsHidden()
                .tint(.accentColor)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .glassEffect()

            HStack(spacing: 8) {
                if isNotificationOn {
                    Text("You will receive updates and alerts")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text(
                        "Enable to receive essay results, assignments and blog updates"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.leading, 20)
            .animation(.easeInOut, value: isNotificationOn)
        }
    }

    // MARK: - Face ID Toggle
    private var faceIDToggle: some View {
        let biometricName =
            BiometricAuthService.shared.biometricType == .faceID
            ? String(localized: "Face ID")
            : String(localized: "Touch ID")
        let icon =
            BiometricAuthService.shared.biometricType == .faceID
            ? "faceid" : "touchid"

        return VStack(spacing: 10) {
            HStack(spacing: 15) {
                Image(systemName: icon)
                    .font(.system(size: 26))
                    .foregroundStyle(
                        authManager.isBiometricLoginEnabled ? .blue : .secondary
                    )
                    .frame(width: 40)
                    .contentTransition(.symbolEffect(.replace))

                Text("Sign in with \(biometricName)")
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(.primary)

                Spacer()

                Toggle(
                    "",
                    isOn: Binding(
                        get: { authManager.isBiometricLoginEnabled },
                        set: { newValue in
                            if !newValue {
                                authManager.isBiometricLoginEnabled = false
                            } else {
                                Task { await handleFaceIDToggle(true) }
                            }
                        }
                    )
                )
                .labelsHidden()
                .tint(.accentColor)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .glassEffect()

            HStack(spacing: 8) {
                if authManager.isBiometricLoginEnabled {
                    Text(
                        "You will be asked to authenticate with \(biometricName) on next launch"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                } else {
                    Text(
                        "Enable to sign in faster without entering your password"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.leading, 20)
            .animation(.easeInOut, value: authManager.isBiometricLoginEnabled)
        }
    }

    private func handleFaceIDToggle(_ newValue: Bool) async {
        guard newValue else { return }
        do {
            try await BiometricAuthService.shared.authenticate()
            authManager.isBiometricLoginEnabled = true
        } catch BiometricError.cancelled {
        } catch {
            authManager.isBiometricLoginEnabled = false
        }
    }

    // MARK: - Edit Profile Button
    private var EditProfileButton: some View {
        VStack(spacing: 10) {
            Button {
                navigateToEditProfile = true
            } label: {
                HStack(spacing: 15) {
                    Image(systemName: "pencil.and.scribble")
                        .font(.system(size: 26))
                        .foregroundStyle(.primary)
                        .frame(width: 40)

                    Text("Edit your VSTEP account")
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

            HStack(spacing: 8) {
                Text("Manage your account information")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.leading, 20)
        }
    }

    // MARK: - Security Button
    private var securityButton: some View {
        VStack(spacing: 10) {
            Button {
                navigateToSecurity = true
            } label: {
                HStack(spacing: 15) {
                    Image(systemName: "lock.shield")
                        .font(.system(size: 26))
                        .foregroundStyle(.primary)
                        .frame(width: 40)

                    Text("Security")
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

            HStack(spacing: 8) {
                Text("Manage passwords and account security")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.leading, 20)
        }
    }

    // MARK: - Subscriptions Button
    private var subscriptionsButton: some View {
        VStack(spacing: 10) {
            Button {
                navigateToSubscription = true
            } label: {
                HStack(spacing: 15) {
                    Image(systemName: "wallet.pass")
                        .font(.system(size: 26))
                        .foregroundStyle(.primary)
                        .frame(width: 40)

                    Text("Subscriptions")
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

            HStack(spacing: 8) {
                Text("Manage your subscriptions")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.leading, 20)
        }
    }

    // MARK: - Actions
    private func syncNotificationStatus() async {
        let settings = await UNUserNotificationCenter.current()
            .notificationSettings()
        await MainActor.run {
            isNotificationOn = settings.authorizationStatus == .authorized
        }
    }

    private func handleNotificationToggle(_ newValue: Bool) async {
        if newValue {
            let settings = await UNUserNotificationCenter.current()
                .notificationSettings()
            switch settings.authorizationStatus {
            case .notDetermined:
                let granted =
                    (try? await UNUserNotificationCenter.current()
                        .requestAuthorization(options: [.alert, .badge, .sound]))
                    ?? false
                await MainActor.run {
                    isNotificationOn = granted
                    if granted {
                        UIApplication.shared.registerForRemoteNotifications()
                    }
                }
            case .denied:
                await MainActor.run {
                    isNotificationOn = false
                    openAppSettings()
                }
            case .authorized, .provisional, .ephemeral:
                await MainActor.run { isNotificationOn = true }
            @unknown default:
                break
            }
        } else {
            await MainActor.run {
                isNotificationOn = true
                openAppSettings()
            }
        }
    }

    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else {
            return
        }
        UIApplication.shared.open(url)
    }
}
