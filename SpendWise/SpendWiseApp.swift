import SwiftUI
import FirebaseCore
import GoogleSignIn

@main
struct SpendWiseApp: App {
    @StateObject private var authViewModel = AuthViewModel()

    init() {
        configureFirebase()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(authViewModel)
        }
#if os(macOS)
        .defaultSize(width: 1100, height: 700)
#endif
    }

    // MARK: - Firebase Configuration
    private func configureFirebase() {
        FirebaseApp.configure()

        // Configure Google Sign-In with Firebase client ID
        if let clientID = FirebaseApp.app()?.options.clientID {
            GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
        }
    }
}

// MARK: - iOS URL Handling (for OAuth callbacks and Google Sign-In)
#if os(iOS)
extension SpendWiseApp {
    // Handle URL callback for Google Sign-In and bank OAuth redirect
    // Add this to your SceneDelegate or use the newer approach below
}

// For SwiftUI lifecycle, handle Open URL:
struct URLHandlerModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .onOpenURL { url in
                // Handle Google Sign-In callback
                GIDSignIn.sharedInstance.handle(url)
                // Handle bank OAuth callback (spendwise://bank-callback)
                if url.scheme == "spendwise" {
                    handleBankCallback(url: url)
                }
            }
    }

    private func handleBankCallback(url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let code = components.queryItems?.first(where: { $0.name == "code" })?.value else {
            return
        }
        NotificationCenter.default.post(
            name: .bankOAuthCallback,
            object: nil,
            userInfo: ["code": code]
        )
    }
}

extension Notification.Name {
    static let bankOAuthCallback = Notification.Name("bankOAuthCallback")
}
#endif
