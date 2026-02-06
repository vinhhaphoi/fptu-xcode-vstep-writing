// System frameworks
import Foundation
import Combine
import SwiftUI

// Firebase
import FirebaseCore
import FirebaseAuth

// Third-party
import GoogleSignIn

@MainActor
class AuthenticationManager: ObservableObject {
    static let shared = AuthenticationManager()
    
    @Published var user: User?
    @Published var authState: AuthState = .loading
    
    private var authStateListener: AuthStateDidChangeListenerHandle?
    
    enum AuthState {
        case loading
        case authenticated
        case unauthenticated
    }
    
    private init() {
        setupAuthStateListener()
    }
    
    private func setupAuthStateListener() {
        authStateListener = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            self?.user = user
            self?.authState = user != nil ? .authenticated : .unauthenticated
        }
    }
    
    // MARK: - Email/Password Auth
    func signUp(email: String, password: String) async throws {
        let result = try await Auth.auth().createUser(withEmail: email, password: password)
        self.user = result.user
    }
    
    func signIn(email: String, password: String) async throws {
        let result = try await Auth.auth().signIn(withEmail: email, password: password)
        self.user = result.user
    }
    
    // MARK: - Google Sign-In
    func signInWithGoogle() async throws {
        // 1. Get Firebase client ID
        guard let clientID = FirebaseApp.app()?.options.clientID else {
            throw AuthError.noClientID
        }
        
        // 2. Configure Google Sign-In
        let config = GIDConfiguration(clientID: clientID)
        GIDSignIn.sharedInstance.configuration = config
        
        // 3. Get presenting view controller
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootViewController = windowScene.windows.first?.rootViewController else {
            throw AuthError.noRootViewController
        }
        
        // 4. Start Google Sign-In flow
        let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: rootViewController)
        let user = result.user
        
        guard let idToken = user.idToken?.tokenString else {
            throw AuthError.noIDToken
        }
        
        // 5. Create Firebase credential
        let credential = GoogleAuthProvider.credential(
            withIDToken: idToken,
            accessToken: user.accessToken.tokenString
        )
        
        // 6. Sign in to Firebase
        let authResult = try await Auth.auth().signIn(with: credential)
        self.user = authResult.user
    }
    
    // MARK: - Sign Out
    func signOut() throws {
        // Sign out from Firebase
        try Auth.auth().signOut()
        
        // Sign out from Google
        GIDSignIn.sharedInstance.signOut()
        
        self.user = nil
    }
    
    // MARK: - Custom Errors
    enum AuthError: LocalizedError {
        case noClientID
        case noRootViewController
        case noIDToken
        case signInFailed(String)
        
        var errorDescription: String? {
            switch self {
            case .noClientID: return "Client ID not found"
            case .noRootViewController: return "Root View Controller not found"
            case .noIDToken: return "Can not get ID Token"
            case .signInFailed(let message): return message
            }
        }
    }
    
    deinit {
        if let listener = authStateListener {
            Auth.auth().removeStateDidChangeListener(listener)
        }
    }
}
