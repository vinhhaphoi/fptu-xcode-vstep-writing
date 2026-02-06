import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) var dismiss
    @AppStorage("isDarkMode") private var isDarkMode = false
    @State private var isNotificationOn = false
    
    // Navigation States
    @State private var navigateToSecurity = false
    @State private var navigateToSubscription = false
    @State private var navigateToEditProfile = false
    
    var body: some View {
        ScrollView {
            //Edit profile button
            EditProfileButton
                .padding()
            
            // Security Button
            securityButton
                .padding()
            
            // Subscriptions Button
            subscriptionsButton
                .padding()
            
            // Notification Toggle
            notificationToggle
                .padding()
//            
//            // About Section
//            aboutSection
//                .padding()
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
    }
    
    // MARK: - Notification Toggle
    private var notificationToggle: some View {
        HStack(spacing: 15) {
            Image(systemName: isNotificationOn ? "bell.fill" : "bell.slash.fill")
                .font(.system(size: 26))
                .foregroundStyle(isNotificationOn ? .orange : .gray)
                .frame(width: 40)
                .contentTransition(.symbolEffect(.replace))
            
            Text("Notifications")
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(.primary)
            
            Spacer()
            
            Toggle("", isOn: $isNotificationOn.animation(.easeInOut(duration: 0.3)))
                .labelsHidden()
                .tint(.accentColor)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .glassEffect()
    }
    
    //MARK: - Edit profile button
    private var EditProfileButton: some View {
        VStack(spacing: 10) {
            Button {
                navigateToSecurity = true
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
            
            // Caption
            HStack(spacing: 8) {
                Text("Manage your account infomation")
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
            
            // Caption
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
            
            // Caption
            HStack(spacing: 8) {
                Text("Manage your subscriptions")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.leading, 20)
        }
    }
    
    // MARK: - About Section
    private var aboutSection: some View {
        VStack(spacing: 12) {
            Button {
                // Rate app
            } label: {
                HStack(spacing: 15) {
                    Image(systemName: "star")
                        .font(.system(size: 26))
                        .foregroundStyle(.yellow)
                        .frame(width: 40)
                    
                    Text("Rate App")
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
            
            Divider()
                .padding(.leading, 70)
            
            Button {
                // Share app
            } label: {
                HStack(spacing: 15) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 26))
                        .foregroundStyle(.blue)
                        .frame(width: 40)
                    
                    Text("Share App")
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
        }
        .glassEffect(in: .rect(cornerRadius: 16.0))
    }
}
