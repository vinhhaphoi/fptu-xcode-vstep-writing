// SettingsView.swift

import SwiftUI
import UserNotifications

struct SettingsView: View {
    @Environment(\.dismiss) var dismiss
    @AppStorage("isDarkMode") private var isDarkMode = false

    // Navigation States
    @State private var navigateToSecurity = false
    @State private var navigateToSubscription = false
    @State private var navigateToEditProfile = false

    // Notification permission state - read from system, not AppStorage
    @State private var isNotificationOn = false

    var body: some View {
        ScrollView {
            EditProfileButton
                .padding()

            securityButton
                .padding()

            subscriptionsButton
                .padding()

            notificationToggle
                .padding()
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
            // Read actual system permission status on appear
            await syncNotificationStatus()
        }
        // Re-sync when app comes back to foreground (user may have changed in Settings.app)
        .onReceive(
            NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
        ) { _ in
            Task { await syncNotificationStatus() }
        }
    }

    // MARK: - Notification Toggle
    private var notificationToggle: some View {
        VStack(spacing: 10) {
            HStack(spacing: 15) {
                Image(systemName: isNotificationOn ? "bell.fill" : "bell.slash.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(isNotificationOn ? .orange : .secondary)
                    .frame(width: 40)
                    .contentTransition(.symbolEffect(.replace))

                Text("Notifications")
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(.primary)

                Spacer()

                Toggle("", isOn: Binding(
                    get: { isNotificationOn },
                    set: { newValue in
                        Task { await handleNotificationToggle(newValue) }
                    }
                ))
                .labelsHidden()
                .tint(.accentColor)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .glassEffect()

            // Caption shows current status hint
            HStack(spacing: 8) {
                Text(
                    isNotificationOn
                        ? "You will receive updates and alerts"
                        : "Enable to receive essay results, assignments and blog updates"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.leading, 20)
            .animation(.easeInOut, value: isNotificationOn)
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

    // Read current system notification permission and sync toggle state
    private func syncNotificationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        await MainActor.run {
            isNotificationOn = settings.authorizationStatus == .authorized
        }
    }

    private func handleNotificationToggle(_ newValue: Bool) async {
        if newValue {
            // User wants to enable - check current permission status
            let settings = await UNUserNotificationCenter.current().notificationSettings()

            switch settings.authorizationStatus {
            case .notDetermined:
                // First time - request permission
                let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(
                    options: [.alert, .badge, .sound]
                )) ?? false
                await MainActor.run {
                    isNotificationOn = granted
                    if granted {
                        UIApplication.shared.registerForRemoteNotifications()
                    }
                }

            case .denied:
                // Permission was denied - must go to Settings.app to re-enable
                await MainActor.run {
                    isNotificationOn = false
                    openAppSettings()
                }

            case .authorized, .provisional, .ephemeral:
                // Already authorized - just reflect the state
                await MainActor.run {
                    isNotificationOn = true
                }

            @unknown default:
                break
            }
        } else {
            // User wants to disable - iOS does not allow programmatic revoke
            // Must redirect to Settings.app
            await MainActor.run {
                isNotificationOn = true  // Revert toggle - cannot disable programmatically
                openAppSettings()
            }
        }
    }

    // Open iOS Settings.app for this app
    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
