import SwiftUI

struct SubscriptionsView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Premium Card
                premiumCard
                    .padding()
                
                // Features List
                featuresSection
                    .padding()
                
                // Subscribe Button
                subscribeButton
                    .padding()
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Subscriptions")
        .navigationBarTitleDisplayMode(.large)
    }
    
    // MARK: - Premium Card
    private var premiumCard: some View {
        VStack(spacing: 16) {
            Image(systemName: "crown.fill")
                .font(.system(size: 60))
                .foregroundStyle(.yellow)
            
            Text("VSTEP Writing Premium")
                .font(.title2.bold())
            
            Text("Unlock all features")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Text("$9.99/month")
                .font(.title3.bold())
                .foregroundColor(.blue)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .glassEffect(in: .rect(cornerRadius: 16.0))
    }
    
    // MARK: - Features Section
    private var featuresSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Features")
                .font(.title3.bold())
                .padding(.horizontal)
            
            VStack(spacing: 12) {
                ForEach(features, id: \.title) { feature in
                    FeatureRow(feature: feature)
                }
            }
            .glassEffect(in: .rect(cornerRadius: 16.0))
        }
    }
    
    private let features = [
        Feature(icon: "checkmark.circle.fill", title: "Unlimited Essays", color: .green),
        Feature(icon: "checkmark.circle.fill", title: "AI Grammar Check", color: .green),
        Feature(icon: "checkmark.circle.fill", title: "Advanced Analytics", color: .green),
        Feature(icon: "checkmark.circle.fill", title: "Export Reports", color: .green),
        Feature(icon: "checkmark.circle.fill", title: "Priority Support", color: .green)
    ]
    
    // MARK: - Subscribe Button
    private var subscribeButton: some View {
        Button {
            // Handle subscription
            print("🛒 Subscribe tapped")
        } label: {
            Text("Subscribe Now")
                .fontWeight(.semibold)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue)
                .cornerRadius(12)
        }
    }
}

struct Feature: Hashable {
    let icon: String
    let title: String
    let color: Color
}

struct FeatureRow: View {
    let feature: Feature
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: feature.icon)
                .font(.title3)
                .foregroundColor(feature.color)
                .frame(width: 32)
            
            Text(feature.title)
                .font(.body)
            
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
}

#Preview {
    NavigationStack {
        SubscriptionsView()
    }
}
