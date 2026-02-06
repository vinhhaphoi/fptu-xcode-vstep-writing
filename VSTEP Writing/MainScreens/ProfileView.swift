import SwiftUI

struct ProfileView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @State private var showingLogoutAlert = false
    @State private var showingSettings = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Profile Header
                VStack(spacing: 12) {
                    Image(systemName: "person.circle.fill")
                        .font(.system(size: 80))
                        .foregroundStyle(.blue)
                    ProfileInfoCard()

                }
                .padding(.top, 20)
                
                // Profile Content
                VStack(alignment: .leading, spacing: 16) {
                    Text("Thông tin cá nhân")
                        .font(.title2.bold())
                        .padding(.horizontal)
                }
                .padding(.top, 20)
                
                Spacer()
            }
        }
        .background(Color(.systemGroupedBackground))
        .toolbar {
            ToolBarItems
        }
        .alert("Đăng xuất", isPresented: $showingLogoutAlert) {
            Button("Hủy", role: .cancel) { }
            Button("Đăng xuất", role: .destructive) {
                handleLogout()
            }
        } message: {
            Text("Bạn có chắc muốn đăng xuất?")
        }
    }
    
    @ToolbarContentBuilder
    private var ToolBarItems: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button(role: .destructive) {
                showingLogoutAlert = true
            } label: {
                Image(systemName: "rectangle.portrait.and.arrow.forward")
                    .foregroundStyle(.red)
            }
        }
        
        // Settings button - Trailing (Bên phải)
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                showingSettings = true
            } label: {
                Image(systemName: "gearshape")
            }
        }
    }
    
    private func handleLogout() {
        do {
            try authManager.signOut()
            print("✅ Logged out successfully")
        } catch {
            print("❌ Logout error: \(error.localizedDescription)")
        }
    }
}

// Sample Profile Card
struct ProfileInfoCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "envelope.fill")
                    .foregroundColor(.blue)
                Text("Email verified")
                Spacer()
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            }
            
            Divider()
            
            HStack {
                Image(systemName: "calendar")
                    .foregroundColor(.blue)
                Text("Joined Jan 2026")
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .padding(.horizontal)
    }
}

// Placeholder Settings View
struct SettingsView: View {
    @Environment(\.dismiss) var dismiss
    @AppStorage("isDarkMode") private var isDarkMode = false
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle(isOn: $isDarkMode) {
                        Label("Dark Mode", systemImage: "moon.fill")
                    }
                } header: {
                    Text("Appearance")
                }
                
                Section {
                    Button {
                        // Action
                    } label: {
                        Label("Notifications", systemImage: "bell")
                    }
                    
                    Button {
                        // Action
                    } label: {
                        Label("Privacy", systemImage: "lock")
                    }
                } header: {
                    Text("Preferences")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        ProfileView()
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.large)
    }
    .environmentObject(AuthenticationManager.shared)
}
