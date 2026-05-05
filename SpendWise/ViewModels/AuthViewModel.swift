import Foundation
import Combine
import FirebaseAuth

@MainActor
class AuthViewModel: ObservableObject {
    @Published var isAuthenticated = false
    @Published var isLoading = true
    @Published var errorMessage: String?

    private let authService = AuthService.shared
    private var cancellables = Set<AnyCancellable>()

    init() {
        authService.$isAuthenticated
            .assign(to: &$isAuthenticated)
        authService.$isLoading
            .assign(to: &$isLoading)
        authService.$errorMessage
            .assign(to: &$errorMessage)
    }

    func signInWithGoogle() async {
        errorMessage = nil
        await authService.signInWithGoogle()
    }

    func signInAnonymously() async {
        errorMessage = nil
        await authService.signInAnonymously()
    }

    func linkWithGoogle() async {
        errorMessage = nil
        await authService.linkWithGoogle()
    }

    func signOut() {
        authService.signOut()
    }

    var currentUser: User? { authService.currentUser }
    var isAnonymous: Bool { authService.isAnonymous }
    var userDisplayName: String { authService.userDisplayName }
    var userEmail: String { authService.userEmail }
    var userPhotoURL: URL? { authService.userPhotoURL }
}
