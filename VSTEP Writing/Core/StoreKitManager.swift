import StoreKit
import FirebaseFirestore
import FirebaseAuth

typealias AppTransaction = StoreKit.Transaction

@Observable
class StoreKitManager {

    // MARK: - Properties
    var products: [Product] = []
    var purchasedProductIDs: Set<String> = []
    var isLoading: Bool = false
    var errorMessage: String? = nil

    private let productIDs = ["com.vstep.advanced", "com.vstep.premier"]
    private let db = Firestore.firestore()
    private var transactionListenerTask: Task<Void, Never>? = nil

    // MARK: - Init
    init() {
        transactionListenerTask = listenForTransactions()
        Task {
            await finishAllUnfinishedTransactions()
            await loadProducts()
            await updatePurchasedProducts()
        }
    }

    deinit {
        transactionListenerTask?.cancel()
    }

    // MARK: - Finish mọi transaction chưa được finish (giải quyết Billing Problem)
    func finishAllUnfinishedTransactions() async {
        for await result in Transaction.unfinished {
            switch result {
            case .verified(let transaction):
                await transaction.finish()
                print("Finished unfinished transaction: \(transaction.productID)")
            case .unverified(let transaction, let error):
                await transaction.finish()
                print("Finished unverified transaction \(transaction.productID): \(error)")
            }
        }
    }

    // MARK: - Load Products
    func loadProducts() async {
        isLoading = true
        do {
            let loaded = try await Product.products(for: productIDs)
            // Giữ đúng thứ tự advanced → premier
            products = productIDs.compactMap { id in
                loaded.first(where: { $0.id == id })
            }
        } catch {
            errorMessage = "Không thể tải sản phẩm: \(error.localizedDescription)"
            print("Failed to load products: \(error)")
        }
        isLoading = false
    }

    // MARK: - Purchase
    func purchase(_ product: Product) async throws {
        let result = try await product.purchase()

        switch result {
        case let .success(.verified(transaction)):
            await transaction.finish()
            await updatePurchasedProducts()
            await syncToFirebase(transaction: transaction, isActive: true)
            print("Purchase successful: \(transaction.productID)")

        case let .success(.unverified(transaction, error)):
            await transaction.finish()
            print("Unverified transaction \(transaction.productID): \(error)")

        case .pending:
            print("Purchase pending")

        case .userCancelled:
            print("User cancelled")

        @unknown default:
            break
        }
    }

    // MARK: - Update Purchased State
    @MainActor
    func updatePurchasedProducts() async {
        var activeIDs: Set<String> = []

        for await result in Transaction.currentEntitlements {
            switch result {
            case .verified(let transaction):
                if transaction.revocationDate == nil {
                    activeIDs.insert(transaction.productID)
                }
            case .unverified(_, let error):
                print("Unverified entitlement: \(error)")
            }
        }

        purchasedProductIDs = activeIDs
    }

    // MARK: - Listen For Transactions
    func listenForTransactions() -> Task<Void, Never> {
        Task.detached { [weak self] in
            guard let self else { return }
            for await result in Transaction.updates {
                switch result {
                case .verified(let transaction):
                    await transaction.finish()
                    await self.updatePurchasedProducts()
                    let isActive = transaction.revocationDate == nil
                    await self.syncToFirebase(transaction: transaction, isActive: isActive)

                case .unverified(let transaction, let error):
                    // Finish luôn để không hiện Billing Problem dialog
                    await transaction.finish()
                    print("Unverified update \(transaction.productID): \(error)")
                }
            }
        }
    }

    // MARK: - Restore Purchases
    func restorePurchases() async {
        do {
            try await AppStore.sync()
            await updatePurchasedProducts()
            print("Purchases restored")
        } catch {
            errorMessage = "Không thể khôi phục: \(error.localizedDescription)"
            print("Restore error: \(error)")
        }
    }

    // MARK: - Helpers
    func isPurchased(_ productID: String) -> Bool {
        purchasedProductIDs.contains(productID)
    }
}

// MARK: - Firebase Sync
extension StoreKitManager {

    func syncToFirebase(transaction: AppTransaction, isActive: Bool) async {
        guard let userID = Auth.auth().currentUser?.uid else { return }

        var data: [String: Any] = [
            "productID": transaction.productID,
            "status": isActive ? "active" : "expired",
            "startDate": Timestamp(date: transaction.purchaseDate),
            "updatedAt": FieldValue.serverTimestamp()
        ]

        if let expiry = transaction.expirationDate {
            data["expiryDate"] = Timestamp(date: expiry)
        }

        do {
            try await db
                .collection("subscriptions")
                .document(userID)
                .setData(data, merge: true)
            print("Firebase synced: \(transaction.productID) → \(isActive ? "active" : "expired")")
        } catch {
            print("Firebase sync error: \(error.localizedDescription)")
        }
    }
}
