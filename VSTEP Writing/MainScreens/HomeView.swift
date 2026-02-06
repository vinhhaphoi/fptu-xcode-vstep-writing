import SwiftUI

struct HomeView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Welcome Banner
                WelcomeBanner()
                
                // Quick Actions
                QuickActionsSection()
                
                // Recent Activity
                RecentActivitySection()
                
                Spacer(minLength: 50)
            }
            .padding(.vertical)
        }
    }
}

struct WelcomeBanner: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Welcome Back!")
                .font(.title.bold())
            
            Text("Continue your writing practice")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(
            LinearGradient(
                colors: [.blue.opacity(0.3), .purple.opacity(0.3)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .cornerRadius(16)
        .padding(.horizontal)
    }
}

struct QuickActionsSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Quick Actions")
                .font(.title2.bold())
                .padding(.horizontal)
            
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                QuickActionCard(icon: "pencil", title: "New Essay", color: .blue)
                QuickActionCard(icon: "book", title: "Grammar", color: .green)
                QuickActionCard(icon: "list.clipboard", title: "Practice", color: .orange)
                QuickActionCard(icon: "chart.bar", title: "Progress", color: .purple)
            }
            .padding(.horizontal)
        }
    }
}

struct QuickActionCard: View {
    let icon: String
    let title: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title)
                .foregroundColor(color)
            
            Text(title)
                .font(.subheadline.weight(.medium))
        }
        .frame(maxWidth: .infinity)
        .frame(height: 100)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 2)
    }
}

struct RecentActivitySection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Recent Activity")
                .font(.title2.bold())
                .padding(.horizontal)
            
            ForEach(0..<5) { index in
                ActivityRow(index: index)
            }
        }
    }
}

struct ActivityRow: View {
    let index: Int
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: "doc.text.fill")
                .foregroundColor(.blue)
                .font(.title3)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Essay \(index + 1)")
                    .font(.headline)
                
                Text("Completed 2 days ago")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Text("85%")
                .font(.headline)
                .foregroundColor(.green)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .padding(.horizontal)
    }
}
