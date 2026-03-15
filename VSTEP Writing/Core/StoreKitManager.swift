import FirebaseAuth
import FirebaseFirestore
import StoreKit

typealias AppTransaction = StoreKit.Transaction

@Observable
class StoreKitManager {

    // MARK: - Properties
    var products: [Product] = []
    var purchasedProductIDs: Set<String> = []
    var expiryDates: [String: Date] = [:]
    var isLoading: Bool = false
    var errorMessage: String? = nil

    let productIDs = ["com.vstep.advanced", "com.vstep.premier"]

    private var transactionListenerTask: Task<Void, Never>? = nil

    // MARK: - Init
    init() {
        transactionListenerTask = listenForTransactions()
        Task {
            await loadProducts()
            await syncEntitlementsToFirebase()
        }
    }

    deinit {
        transactionListenerTask?.cancel()
    }

    // MARK: - Load Products
    func loadProducts() async {
        isLoading = true
        do {
            let loaded = try await Product.products(for: productIDs)
            products = productIDs.compactMap { id in
                loaded.first(where: { $0.id == id })
            }
        } catch {
            errorMessage = error.localizedDescription
            print("[StoreKitManager] Load products error: \(error)")
        }
        isLoading = false
    }

    // MARK: - Purchase
    func purchase(_ product: Product) async throws {
        let result = try await product.purchase()

        switch result {
        case .success(.verified(let transaction)):
            await transaction.finish()

            // Step 1: Sync local StoreKit state
            await syncEntitlementsToFirebase()

            // Step 2: Ask backend to independently verify with Apple
            await verifyWithBackend(transaction: transaction)

            print(
                "[StoreKitManager] Purchase successful: \(transaction.productID)"
            )

        case .success(.unverified(let transaction, let error)):
            // Do not finish unverified - let Apple verify first
            print(
                "[StoreKitManager] Unverified transaction \(transaction.productID): \(error)"
            )

        case .pending:
            print("[StoreKitManager] Purchase pending")

        case .userCancelled:
            print("[StoreKitManager] User cancelled")

        @unknown default:
            break
        }
    }

    // MARK: - Listen For Transactions
    // Handles Apple server events: renewal, refund, revoke
    private func listenForTransactions() -> Task<Void, Never> {
        Task.detached { [weak self] in
            guard let self else { return }
            for await result in Transaction.updates {
                switch result {
                case .verified(let transaction):
                    await transaction.finish()

                    if transaction.revocationDate != nil {
                        // Refund detected — revoke access on backend
                        await self.revokeAccessOnBackend()
                    } else {
                        // Renewal or new transaction — sync normally
                        await self.syncEntitlementsToFirebase()
                        await self.verifyWithBackend(transaction: transaction)
                    }

                case .unverified(let transaction, let error):
                    print(
                        "[StoreKitManager] Unverified update \(transaction.productID): \(error)"
                    )
                }
            }
        }
    }

    // MARK: - Restore Purchases
    func restorePurchases() async {
        do {
            try await AppStore.sync()
            await syncEntitlementsToFirebase()

            // Re-verify latest active transaction after restore
            for await result in Transaction.currentEntitlements {
                if case .verified(let transaction) = result,
                    transaction.revocationDate == nil
                {
                    await verifyWithBackend(transaction: transaction)
                    break
                }
            }

            print("[StoreKitManager] Purchases restored")
        } catch {
            errorMessage = error.localizedDescription
            print("[StoreKitManager] Restore error: \(error)")
        }
    }

    // MARK: - Helpers
    func isPurchased(_ productID: String) -> Bool {
        purchasedProductIDs.contains(productID)
    }

    func expiryDate(for productID: String) -> Date? {
        expiryDates[productID]
    }
}

// MARK: - Firebase Sync (Local StoreKit → Firestore users/{userId})
extension StoreKitManager {

    // StoreKit is source of truth for local state.
    // Writes to users/{userId} per Cloud Functions v3.0 Required Schema.
    func syncEntitlementsToFirebase() async {
        guard let userID = Auth.auth().currentUser?.uid else { return }

        var activeIDs: Set<String> = []
        var collectedExpiry: [String: Date] = [:]
        var latestTransaction: AppTransaction? = nil
        var latestDate: Date = .distantPast

        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            guard transaction.revocationDate == nil else { continue }

            activeIDs.insert(transaction.productID)

            if let expiry = transaction.expirationDate {
                collectedExpiry[transaction.productID] = expiry
            }

            if transaction.purchaseDate > latestDate {
                latestDate = transaction.purchaseDate
                latestTransaction = transaction
            }
        }

        await MainActor.run {
            purchasedProductIDs = activeIDs
            expiryDates = collectedExpiry
        }

        // Write to users/{userId} — required by Cloud Functions v3.0
        let userRef = FirebaseService.shared.db
            .collection("users")
            .document(userID)

        do {
            if let tx = latestTransaction {
                // Map com.vstep.advanced -> "advanced", com.vstep.premier -> "premier"
                let tier =
                    tx.productID.components(separatedBy: ".").last ?? "free"

                var data: [String: Any] = [
                    "isSubscribed": true,
                    "subscriptionTier": tier,
                    "originalTransactionId": String(tx.originalID),
                    "updatedAt": FieldValue.serverTimestamp(),
                ]

                if let expiry = tx.expirationDate {
                    data["expiryDate"] = Timestamp(date: expiry)
                } else {
                    data["expiryDate"] = NSNull()
                }

                try await userRef.setData(data, merge: true)
                print("[StoreKitManager] Synced active tier: \(tier)")

            } else {
                // No active subscription — reset to free
                try await userRef.setData(
                    [
                        "isSubscribed": false,
                        "subscriptionTier": "free",
                        "expiryDate": NSNull(),
                        "updatedAt": FieldValue.serverTimestamp(),
                    ],
                    merge: true
                )
                print("[StoreKitManager] Synced: no active subscription")
            }
        } catch {
            print(
                "[StoreKitManager] Firestore sync error: \(error.localizedDescription)"
            )
        }
    }
}

// MARK: - Backend Verification (Cloud Functions v3.0)
extension StoreKitManager {

    // Call verifyStoreKitPurchase after every purchase/restore
    // Request: { transactionId, productId }
    // Response: { success, tier, expiryDate }
    private func verifyWithBackend(transaction: AppTransaction) async {
        do {
            try await AIUsageManager.shared.verifyStoreKitPurchase(
                transactionId: transaction.id,
                productId: transaction.productID
            )
            print(
                "[StoreKitManager] Backend verification successful: \(transaction.productID)"
            )
        } catch {
            // Non-critical: local StoreKit state already synced
            // Backend will re-verify via Apple Webhook on next renewal
            print(
                "[StoreKitManager] Backend verification failed (non-critical): \(error.localizedDescription)"
            )
        }
    }

    // Call when StoreKit detects revocationDate != nil (refund)
    // Request: { clearStatus: true }
    private func revokeAccessOnBackend() async {
        do {
            try await AIUsageManager.shared.revokeSubscription()
            print("[StoreKitManager] Backend access revoked (refund)")
        } catch {
            print(
                "[StoreKitManager] Revoke failed: \(error.localizedDescription)"
            )
        }

        // Also clear local state immediately
        await MainActor.run {
            purchasedProductIDs = []
            expiryDates = [:]
        }

        // Reset Firestore local write (backend also handles this via clearStatus)
        guard let userID = Auth.auth().currentUser?.uid else { return }
        try? await FirebaseService.shared.db
            .collection("users")
            .document(userID)
            .setData(
                [
                    "isSubscribed": false,
                    "subscriptionTier": "free",
                    "expiryDate": NSNull(),
                    "updatedAt": FieldValue.serverTimestamp(),
                ],
                merge: true
            )
    }
}
