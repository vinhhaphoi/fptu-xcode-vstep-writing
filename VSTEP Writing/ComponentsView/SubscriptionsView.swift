import StoreKit
import SwiftUI

// MARK: - SubscriptionsView
struct SubscriptionsView: View {

    @Environment(StoreKitManager.self) private var store
    @State private var plans: [String: Plan] = [:]
    @State private var alertMessage: AlertMessage? = nil
    @State private var isRestoring = false
    @Environment(\.scenePhase) private var scenePhase

    private var activeProductID: String? {
        store.productIDs.first { store.isPurchased($0) }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {

                headerCard
                    .padding()

                if activeProductID != nil {
                    activeSubscriptionSection
                        .padding(.horizontal)
                }

                if store.isLoading {
                    ProgressView("Loading plans...")
                        .padding(40)
                } else {
                    plansSection
                        .padding(.horizontal)
                }

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
            await store.syncEntitlementsToFirebase()
        }
        .task(id: scenePhase) {
            if scenePhase == .active {
                await store.syncEntitlementsToFirebase()
            }
        }
    }

    // MARK: - Header Card

    private var headerCard: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(BrandColor.muted)
                    .frame(width: 100, height: 100)

                Image(systemName: "crown.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(BrandColor.primary)
            }

            Text("VSTEP Writing Premium")
                .font(.title2.bold())
                .foregroundStyle(BrandColor.primary)

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
                    .foregroundStyle(BrandColor.light)
                    .frame(width: 40)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Active Plan")
                        .font(.system(size: 17, weight: .regular))
                        .foregroundStyle(.primary)

                    if let id = activeProductID, let plan = plans[id] {
                        Text(plan.displayName)
                            .font(.caption)
                            .foregroundStyle(BrandColor.medium)
                    }
                }

                Spacer()

                if let id = activeProductID,
                    let expiry = store.expiryDate(for: id)
                {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Renews")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Text(expiry.formatted(.dateTime.day().month().year()))
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .glassEffect()

            HStack {
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
                .foregroundStyle(BrandColor.primary)
                .padding(.leading, 4)

            ForEach(store.products) { product in
                planCard(product: product)
            }
        }
    }

    private func planCard(product: Product) -> some View {
        let plan = plans[product.id]
        let isActive = activeProductID == product.id
        let limits = AIUsageManager.shared.planLimits[product.id]

        return VStack(spacing: 0) {

            // Plan Header Row
            HStack(spacing: 15) {
                Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 26))
                    .foregroundStyle(
                        isActive ? BrandColor.light : BrandColor.primary
                    )
                    .frame(width: 40)
                    .contentTransition(.symbolEffect(.replace))

                VStack(alignment: .leading, spacing: 4) {
                    Text(plan?.displayName ?? product.displayName)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.primary)

                    Text(product.displayPrice + "/month")
                        .font(.caption)
                        .foregroundStyle(BrandColor.medium)
                }

                Spacer()

                if isActive {
                    Text("Active")
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(BrandColor.light))
                } else {
                    Button {
                        Task {
                            do {
                                try await store.purchase(product)
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
                            .background(Capsule().fill(BrandColor.primary))
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)

            Divider()
                .padding(.leading, 70)

            // Live Limits Section
            if let limits {
                liveLimitsSection(limits: limits)

                Divider()
                    .padding(.leading, 70)
            }

            // Benefits Section
            if let benefits = plan?.benefits {
                VStack(spacing: 0) {
                    // Updated: explain daily AI grading quota clearly
                    let maxEssays = limits?.maxEssaysPerDay ?? 1
                    let gradingAttempts = limits?.gradingAttemptsPerEssay ?? 1
                    let submissions = limits?.submissionsPerEssayPerDay ?? 1
                    let isUnlimitedEssays = maxEssays == Int.max

                    benefitRow(
                        icon: "doc.text.magnifyingglass",
                        title: isUnlimitedEssays
                            ? "Unlimited essays graded by AI today"
                            : "\(maxEssays) essay\(maxEssays > 1 ? "s" : "") graded by AI today",
                        subtitle:
                            "Up to \(gradingAttempts) AI attempt\(gradingAttempts > 1 ? "s" : "") · \(submissions) submission\(submissions > 1 ? "s" : "")/essay — unused quota resets tomorrow",
                        enabled: benefits.unlimitedTests
                    )
                    benefitRow(
                        icon: "bubble.left.and.bubble.right.fill",
                        title: "AI Writing Chatbot",
                        subtitle:
                            "\(limits?.chatbotQuestionsPerDay ?? 0) questions/day",
                        enabled: benefits.aiGrammarCheck
                    )
                    // Advanced Analytics: no longer comingSoon, shows weekly insight limit
                    benefitRow(
                        icon: "chart.bar.fill",
                        title: "Advanced Analytics",
                        subtitle: limits.map {
                            "\($0.insightRefreshesPerWeek) AI insight refresh\($0.insightRefreshesPerWeek > 1 ? "es" : "")/week"
                        },
                        enabled: benefits.detailedAnalytics
                    )
                    benefitRow(
                        icon: "star.fill",
                        title: "Priority Support",
                        subtitle: nil,
                        enabled: benefits.prioritySupport,
                        badge: .comingSoon,
                        isLast: true  // Remove Ads removed — this is now last
                    )
                }
            } else {
                skeletonBenefits
            }
        }
        .glassEffect(in: .rect(cornerRadius: 16.0))
    }

    // MARK: - Live Limits Section

    private func liveLimitsSection(limits: PlanLimits) -> some View {
        HStack(spacing: 0) {
            limitBadge(
                icon: "doc.text.fill",
                value: limits.maxEssaysPerDay == Int.max
                    ? "∞" : "\(limits.maxEssaysPerDay)",
                label: "Essays/day"
            )

            Divider()
                .frame(height: 36)

            limitBadge(
                icon: "brain.head.profile",
                value: limits.gradingAttemptsPerEssay == Int.max
                    ? "∞" : "\(limits.gradingAttemptsPerEssay)x",
                label: "AI Grading"
            )

            Divider()
                .frame(height: 36)

            limitBadge(
                icon: "bubble.left.fill",
                value: limits.chatbotQuestionsPerDay == 0
                    ? "—"
                    : "\(limits.chatbotQuestionsPerDay)",
                label: "Chat/day"
            )
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 20)
    }

    private func limitBadge(icon: String, value: String, label: String)
        -> some View
    {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(BrandColor.medium)

            Text(value)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(BrandColor.primary)

            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Benefit Row

    private enum BenefitBadge {
        case comingSoon
    }

    private func benefitRow(
        icon: String,
        title: String,
        subtitle: String?,
        enabled: Bool,
        badge: BenefitBadge? = nil,
        isLast: Bool = false
    ) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 15) {
                Image(systemName: enabled ? icon : "xmark")
                    .font(.system(size: 16))
                    .foregroundStyle(
                        enabled
                            ? BrandColor.light : Color.secondary.opacity(0.4)
                    )
                    .frame(width: 40)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(title)
                            .font(.system(size: 15))
                            .foregroundStyle(
                                enabled
                                    ? .primary : Color.secondary.opacity(0.5)
                            )

                        if let badge, case .comingSoon = badge {
                            Text("Soon")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(BrandColor.soft))
                        }
                    }

                    if let subtitle, enabled {
                        Text(subtitle)
                            .font(.caption2)
                            .foregroundStyle(BrandColor.medium)
                    }
                }

                Spacer()

                Image(systemName: enabled ? "checkmark" : "minus")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(
                        enabled
                            ? BrandColor.light : Color.secondary.opacity(0.4)
                    )
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)

            if !isLast {
                Divider()
                    .padding(.leading, 70)
            }
        }
    }

    // MARK: - Skeleton

    private var skeletonBenefits: some View {
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

    // MARK: - Restore Button

    private var restoreButton: some View {
        VStack(spacing: 10) {
            Button {
                Task {
                    isRestoring = true
                    await store.restorePurchases()
                    isRestoring = false
                    alertMessage = AlertMessage(
                        title: "Restored",
                        message: "Your purchases have been restored."
                    )
                }
            } label: {
                HStack(spacing: 15) {
                    Image(
                        systemName: isRestoring
                            ? "arrow.triangle.2.circlepath"
                            : "clock.arrow.circlepath"
                    )
                    .font(.system(size: 24))
                    .foregroundStyle(BrandColor.primary)
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

            HStack {
                Text("Already purchased? Tap to restore your subscription.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.leading, 20)
        }
    }

    // MARK: - Load Plans via FirebaseService

    private func loadFirebasePlans() async {
        let fetched = await FirebaseService.shared.fetchPlans(
            productIDs: store.productIDs
        )
        await MainActor.run { plans = fetched }
    }
}
