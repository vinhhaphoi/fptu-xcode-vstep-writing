import Combine
import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions
import FirebaseStorage
import Foundation
import UIKit

// MARK: - FirebaseService Core
@MainActor
class FirebaseService: ObservableObject {

    static let shared = FirebaseService()

    // MARK: - Internal dependencies (accessible to all extensions)
    let db = Firestore.firestore()
    let storage = Storage.storage()
    lazy var functions = Functions.functions(region: "asia-southeast1")

    // MARK: - Published State
    @Published var tasks: [VSTEPTask] = []
    @Published var questions: [VSTEPQuestion] = []
    @Published var rubric: VSTEPRubric?
    @Published var userProgress: UserProgress?
    @Published var isLoading = false
    @Published var errorMessage: String?

    // MARK: - Avatar State
    @Published var uploadedAvatarURL: String?
    @Published var isUploadingPhoto = false
    @Published var avatarUploadError: String?

    // MARK: - Auth Helpers
    var currentUserId: String? { Auth.auth().currentUser?.uid }
    var isAuthenticated: Bool { currentUserId != nil }

    // MARK: - Submission Listeners
    var submissionListeners: [String: ListenerRegistration] = [:]

    private init() {}
}
