import FirebaseAuth
import FirebaseFirestore
import StoreKit

typealias AppTransaction = StoreKit.Transaction

@Observable
class StoreKitManager {

    // MARK: - Properties
    var products: [Product] = []
    var purchasedProductIDs: Set<String> = []
    var expiryDates: [String: Date] = [:]  // Added: productID -> expiryDate for View
    var isLoading: Bool = false
    var errorMessage: String? = nil

    // Single source of productIDs - SubscriptionsView reads from here
    let productIDs = ["com.vstep.advanced", "com.vstep.premier"]

    private var transactionListenerTask: Task<Void, Never>? = nil

    // MARK: - Init
    init() {
        // Must start listener before anything else to avoid missing transactions
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
            print("Failed to load products: \(error)")
        }
        isLoading = false
    }

    // MARK: - Purchase
    func purchase(_ product: Product) async throws {
        let result = try await product.purchase()

        switch result {
        case .success(.verified(let transaction)):
            await transaction.finish()
            await syncEntitlementsToFirebase()
            print("Purchase successful: \(transaction.productID)")

        case .success(.unverified(let transaction, let error)):
            // Do not finish unverified - let Apple verify first
            print("Unverified transaction \(transaction.productID): \(error)")

        case .pending:
            print("Purchase pending")

        case .userCancelled:
            print("User cancelled")

        @unknown default:
            break
        }
    }

    // MARK: - Listen For Transactions
    private func listenForTransactions() -> Task<Void, Never> {
        Task.detached { [weak self] in
            guard let self else { return }
            for await result in Transaction.updates {
                switch result {
                case .verified(let transaction):
                    await transaction.finish()
                    // Every Apple event (renewal, refund) triggers a full sync
                    await self.syncEntitlementsToFirebase()

                case .unverified(let transaction, let error):
                    print(
                        "Unverified update \(transaction.productID): \(error)"
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
            print("Purchases restored")
        } catch {
            errorMessage = error.localizedDescription
            print("Restore error: \(error)")
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

// MARK: - Firebase Sync
extension StoreKitManager {

    /// StoreKit is source of truth. Reads currentEntitlements and overwrites Firebase.
    /// If no active entitlement found, writes inactive status to Firebase.
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

            // Collect expiry per productID for View display
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
            expiryDates = collectedExpiry  // Update expiry map for View
        }

        let ref = FirebaseService.shared.db
            .collection("subscriptions")
            .document(userID)

        do {
            if let tx = latestTransaction {
                var data: [String: Any] = [
                    "productID": tx.productID,
                    "status": "active",
                    "startDate": Timestamp(date: tx.purchaseDate),
                    "originalTransactionId": String(tx.originalID),
                    "updatedAt": FieldValue.serverTimestamp(),
                ]
                if let expiry = tx.expirationDate {
                    data["expiryDate"] = Timestamp(date: expiry)
                }
                // Use setData without merge to fully overwrite stale data
                try await ref.setData(data)
                print("Firebase synced active: \(tx.productID)")
            } else {
                try await ref.setData([
                    "productID": NSNull(),
                    "status": "inactive",
                    "expiryDate": NSNull(),
                    "updatedAt": FieldValue.serverTimestamp(),
                ])
                print("Firebase synced: no active subscription")
            }
        } catch {
            print("Firebase sync error: \(error.localizedDescription)")
        }
    }
}
