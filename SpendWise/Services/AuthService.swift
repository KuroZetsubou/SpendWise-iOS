import Foundation
import FirebaseCore
import FirebaseAuth
import GoogleSignIn

@MainActor
class AuthService: ObservableObject {
    static let shared = AuthService()

    @Published var currentUser: User?
    @Published var isAuthenticated = false
    @Published var isLoading = true
    @Published var errorMessage: String?

    private var stateListener: AuthStateDidChangeListenerHandle?

    private init() {
        stateListener = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in
                self?.currentUser = user
                self?.isAuthenticated = user != nil
                self?.isLoading = false
            }
        }
    }

    deinit {
        if let listener = stateListener {
            Auth.auth().removeStateDidChangeListener(listener)
        }
    }

    // MARK: - Anonymous sign-in

    func signInAnonymously() async {
        errorMessage = nil
        isLoading = true
        do {
            try await Auth.auth().signInAnonymously()
        } catch {
            errorMessage = "Accesso locale fallito: \(error.localizedDescription)"
            isLoading = false
        }
    }

    // MARK: - Google sign-in

    func signInWithGoogle() async {
        errorMessage = nil
        guard let clientID = FirebaseApp.app()?.options.clientID else {
            errorMessage = "Configurazione Firebase mancante."
            return
        }

        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)

        do {
#if os(iOS)
            guard let rootViewController = rootViewController else {
                errorMessage = "Impossibile trovare la finestra principale."
                return
            }
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: rootViewController)
#else
            guard let window = NSApplication.shared.windows.first else {
                errorMessage = "Impossibile trovare la finestra principale."
                return
            }
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: window)
#endif
            guard let idToken = result.user.idToken?.tokenString else {
                errorMessage = "Token ID non disponibile."
                return
            }
            let credential = GoogleAuthProvider.credential(
                withIDToken: idToken,
                accessToken: result.user.accessToken.tokenString
            )

            // If the user is anonymous, link instead of replacing
            if let user = Auth.auth().currentUser, user.isAnonymous {
                try await user.link(with: credential)
            } else {
                try await Auth.auth().signIn(with: credential)
            }
        } catch let error as NSError where error.code == AuthErrorCode.credentialAlreadyInUse.rawValue {
            // Credential already linked to another account — sign in normally
            if let credential = error.userInfo[AuthErrorUserInfoUpdatedCredentialKey] as? AuthCredential {
                do {
                    try await Auth.auth().signIn(with: credential)
                } catch {
                    errorMessage = "Accesso fallito: \(error.localizedDescription)"
                }
            }
        } catch {
            errorMessage = "Accesso fallito: \(error.localizedDescription)"
        }
    }

    // MARK: - Link with Google (from Settings)

    func linkWithGoogle() async {
        await signInWithGoogle()
    }

    // MARK: - Sign out

    func signOut() {
        do {
            try Auth.auth().signOut()
            GIDSignIn.sharedInstance.signOut()
            currentUser = nil
            isAuthenticated = false
        } catch {
            errorMessage = "Errore durante il logout: \(error.localizedDescription)"
        }
    }

    // MARK: - Helpers

    var isAnonymous: Bool { currentUser?.isAnonymous == true }

    var userDisplayName: String {
        if isAnonymous { return "Account locale" }
        return currentUser?.displayName ?? currentUser?.email ?? "Utente"
    }

    var userEmail: String {
        isAnonymous ? "Nessun account collegato" : (currentUser?.email ?? "")
    }

    var userPhotoURL: URL? {
        isAnonymous ? nil : currentUser?.photoURL
    }

    // MARK: - Platform Root ViewController
    private var rootViewController: PlatformViewController? {
#if os(iOS)
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }?
            .rootViewController
#else
        NSApplication.shared.windows.first?.contentViewController
#endif
    }
}

#if os(iOS)
typealias PlatformViewController = UIViewController
#else
typealias PlatformViewController = NSViewController
#endif
