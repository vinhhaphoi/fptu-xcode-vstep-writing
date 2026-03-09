import SwiftUI

struct RootView: View {
    @State private var languageManager = LanguageManager()
    @EnvironmentObject var authManager: AuthenticationManager
    @AppStorage("isDarkMode") private var isDarkMode = false

    @State private var isUnlocked = false
    @State private var showEnableBiometricAlert = false
    @State private var biometricError: String?

    var body: some View {
        Group {
            switch authManager.authState {
            case .loading:
                ProgressView("Loading...")

            case .authenticated:
                if authManager.isBiometricLoginEnabled && !isUnlocked {
                    biometricLockScreen
                } else {
                    ContentView()
                        .environment(languageManager)
                        .environment(
                            \.locale,
                            languageManager.currentLanguage.locale
                        )
                }

            case .unauthenticated:
                SignInView(onLoginSuccess: handleLoginSuccess)
            }
        }
        .preferredColorScheme(isDarkMode ? .dark : .light)
        // Auto-trigger Face ID when app becomes active
        .task {
            if authManager.authState == .authenticated,
                authManager.isBiometricLoginEnabled,
                !isUnlocked
            {
                await triggerBiometricUnlock()
            }
        }
        // Prompt to enable Face ID after first login
        .alert(biometricAlertTitle, isPresented: $showEnableBiometricAlert) {
            Button("Enable") {
                authManager.isBiometricLoginEnabled = true
                isUnlocked = true
            }
            Button("Not now", role: .cancel) {
                isUnlocked = true
            }
        } message: {
            Text("Sign in faster and more securely next time.")
        }
    }

    // MARK: - Biometric Lock Screen
    private var biometricLockScreen: some View {
        VStack(spacing: 32) {
            Spacer()

            VStack(spacing: 16) {
                Image(systemName: biometricIcon)
                    .font(.system(size: 64, weight: .thin))
                    .foregroundStyle(.primary)

                Text("VSTEP Writing")
                    .font(.title.bold())

                Text("Sign in to continue")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if let error = biometricError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            Button {
                Task { await triggerBiometricUnlock() }
            } label: {
                Label(biometricButtonTitle, systemImage: biometricIcon)
                    .font(.headline)
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity)
                    .background(Capsule().fill(Color.accentColor))
                    .foregroundColor(.white)
                    .padding(.horizontal, 40)
            }

            Spacer()
        }
    }

    // MARK: - Helpers
    private var biometricType: BiometricType {
        BiometricAuthService.shared.biometricType
    }

    private var biometricIcon: String {
        biometricType == .faceID ? "faceid" : "touchid"
    }

    private var biometricButtonTitle: String {
        biometricType == .faceID
            ? "Sign in with Face ID" : "Sign in with Touch ID"
    }

    private var biometricAlertTitle: String {
        biometricType == .faceID ? "Enable Face ID?" : "Enable Touch ID?"
    }

    // MARK: - Actions
    private func triggerBiometricUnlock() async {
        biometricError = nil
        do {
            try await BiometricAuthService.shared.authenticate()
            isUnlocked = true
        } catch BiometricError.cancelled {
            // Keep lock screen visible, do nothing
        } catch {
            biometricError = error.localizedDescription
        }
    }

    // Called from SignInView after successful login
    private func handleLoginSuccess() {
        if authManager.shouldPromptEnableBiometric() {
            showEnableBiometricAlert = true
        } else {
            isUnlocked = true
        }
    }
}
