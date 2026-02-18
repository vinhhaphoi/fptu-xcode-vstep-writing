import SwiftUI
import StoreKit
import FirebaseFirestore
import FirebaseAuth


// MARK: - SubscriptionsView

struct SubscriptionsView: View {

    @State private var store = StoreKitManager()
    @State private var plans: [String: Plan] = [:]
    @State private var activeProductID: String? = nil
    @State private var expiryDate: Date? = nil
    @State private var alertMessage: AlertMessage? = nil
    @State private var isRestoring = false

    private let db = Firestore.firestore()
    private let productIDs = ["com.vstep.advanced", "com.vstep.premier"]

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {

                // Header Card
                headerCard
                    .padding()

                // Active Subscription Status (nếu đang có)
                if activeProductID != nil {
                    activeSubscriptionSection
                        .padding(.horizontal)
                }

                // Plans
                if store.isLoading {
                    ProgressView("Loading plans...")
                        .padding(40)
                } else {
                    plansSection
                        .padding(.horizontal)
                }

                // Restore Button
                restoreButton
                    .padding(.horizontal)
                    .padding(.bottom, 40)
            }
        }
        .scrollIndicators(.hidden)
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Subscriptions")
        .navigationBarTitleDisplayMode(.large)
        .alert(item: $alertMessage) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("OK"))
            )
        }
        .task {
            await loadFirebasePlans()
            await loadActiveSubscription()
        }
    }

    // MARK: - Header Card

    private var headerCard: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.yellow.opacity(0.15))
                    .frame(width: 100, height: 100)

                Image(systemName: "crown.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.yellow)
            }

            Text("VSTEP Writing Premium")
                .font(.title2.bold())

            Text("Unlock your full writing potential")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .glassEffect(in: .rect(cornerRadius: 16.0))
    }

    // MARK: - Active Subscription Section

    private var activeSubscriptionSection: some View {
        VStack(spacing: 10) {
            HStack(spacing: 15) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(.green)
                    .frame(width: 40)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Active Plan")
                        .font(.system(size: 17, weight: .regular))
                        .foregroundStyle(.primary)

                    if let id = activeProductID,
                       let plan = plans[id] {
                        Text(plan.displayName)
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }

                Spacer()

                if let date = expiryDate {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Renews")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Text(date.formatted(.dateTime.day().month().year()))
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .glassEffect()

            HStack(spacing: 8) {
                Text("Manage your subscription in App Store settings")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.leading, 20)
        }
    }

    // MARK: - Plans Section

    private var plansSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Choose a Plan")
                .font(.system(size: 17, weight: .semibold))
                .padding(.leading, 4)

            ForEach(store.products) { product in
                planCard(product: product)
            }
        }
    }

    private func planCard(product: Product) -> some View {
        let isPurchased = store.isPurchased(product.id)
        let plan = plans[product.id]
        let isActive = activeProductID == product.id

        return VStack(spacing: 0) {

            // Plan Header Row
            HStack(spacing: 15) {
                Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 26))
                    .foregroundStyle(isActive ? .green : .blue)
                    .frame(width: 40)
                    .contentTransition(.symbolEffect(.replace))

                VStack(alignment: .leading, spacing: 4) {
                    Text(plan?.displayName ?? product.displayName)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.primary)

                    Text(product.displayPrice + "/month")
                        .font(.caption)
                        .foregroundStyle(.blue)
                }

                Spacer()

                if isActive {
                    Text("Active")
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(.green))
                } else {
                    Button {
                        Task {
                            do {
                                try await store.purchase(product)
                                await loadActiveSubscription()
                            } catch {
                                alertMessage = AlertMessage(
                                    title: "Purchase Failed",
                                    message: error.localizedDescription
                                )
                            }
                        }
                    } label: {
                        Text("Subscribe")
                            .font(.caption.bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(.blue))
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)

            // Divider
            Divider()
                .padding(.leading, 70)

            // Benefits List
            if let benefits = plan?.benefits {
                VStack(spacing: 0) {
                    benefitRow(icon: "infinity", title: "Unlimited Essays", enabled: benefits.unlimitedTests)
                    benefitRow(icon: "waveform.and.mic", title: "AI Grammar Check", enabled: true)
                    benefitRow(icon: "chart.bar.fill", title: "Advanced Analytics", enabled: benefits.detailedAnalytics)
                    benefitRow(icon: "wifi.slash", title: "Offline Mode", enabled: benefits.offlineMode)
                    benefitRow(icon: "star.fill", title: "Priority Support", enabled: benefits.prioritySupport)
                    benefitRow(icon: "xmark.circle.fill", title: "Remove Ads", enabled: benefits.adsRemoved, isLast: true)
                }
            } else {
                // Skeleton fallback nếu Firebase chưa load
                VStack(spacing: 0) {
                    ForEach(0..<4, id: \.self) { _ in
                        HStack {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.secondary.opacity(0.2))
                                .frame(width: 20, height: 20)
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.secondary.opacity(0.2))
                                .frame(height: 14)
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                    }
                }
            }
        }
        .glassEffect(in: .rect(cornerRadius: 16.0))
    }

    private func benefitRow(icon: String, title: String, enabled: Bool, isLast: Bool = false) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 15) {
                Image(systemName: enabled ? icon : "xmark")
                    .font(.system(size: 16))
                    .foregroundStyle(enabled ? .green : Color.secondary.opacity(0.4))
                    .frame(width: 40)

                Text(title)
                    .font(.system(size: 15))
                    .foregroundStyle(enabled ? .primary : Color.secondary.opacity(0.5))

                Spacer()

                Image(systemName: enabled ? "checkmark" : "minus")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(enabled ? .green : Color.secondary.opacity(0.4))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)

            if !isLast {
                Divider()
                    .padding(.leading, 70)
            }
        }
    }

    // MARK: - Restore Button

    private var restoreButton: some View {
        VStack(spacing: 10) {
            Button {
                Task {
                    isRestoring = true
                    await store.restorePurchases()
                    await loadActiveSubscription()
                    isRestoring = false
                    alertMessage = AlertMessage(
                        title: "Restored",
                        message: "Your purchases have been restored."
                    )
                }
            } label: {
                HStack(spacing: 15) {
                    Image(systemName: isRestoring ? "arrow.triangle.2.circlepath" : "clock.arrow.circlepath")
                        .font(.system(size: 24))
                        .foregroundStyle(.blue)
                        .frame(width: 40)
                        .symbolEffect(.rotate, isActive: isRestoring)

                    Text("Restore Purchases")
                        .font(.system(size: 17, weight: .regular))
                        .foregroundStyle(.primary)

                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .buttonStyle(.plain)
            .glassEffect()

            HStack(spacing: 8) {
                Text("Already purchased? Tap to restore your subscription.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.leading, 20)
        }
    }

    // MARK: - Firebase

    private func loadFirebasePlans() async {
        for id in productIDs {
            do {
                let doc = try await db.collection("plans").document(id).getDocument()
                print("📄 [\(id)] exists: \(doc.exists)")
                print("📄 [\(id)] raw: \(String(describing: doc.data()))")

                guard doc.exists else { continue }

                do {
                    let plan = try doc.data(as: Plan.self)
                    await MainActor.run { plans[id] = plan }
                    print("✅ [\(id)] decoded: \(plan.displayName)")
                } catch {
                    print("❌ [\(id)] decode error: \(error)")
                }
            } catch {
                print("❌ [\(id)] fetch error: \(error)")
            }
        }
    }

    private func loadActiveSubscription() async {
        guard let userID = Auth.auth().currentUser?.uid else { return }
        do {
            let doc = try await db.collection("subscriptions").document(userID).getDocument()
            let data = doc.data()
            let status = data?["status"] as? String
            let productID = data?["productID"] as? String
            let expiry = (data?["expiryDate"] as? Timestamp)?.dateValue()

            await MainActor.run {
                if status == "active", let id = productID {
                    activeProductID = id
                    expiryDate = expiry
                } else {
                    activeProductID = nil
                    expiryDate = nil
                }
            }
        } catch {
            print("Firebase fetch subscription error: \(error.localizedDescription)")
        }
    }
}
