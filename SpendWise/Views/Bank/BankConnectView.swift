import SwiftUI
import FirebaseFirestore
import AuthenticationServices

struct BankConnectView: View {
    @ObservedObject var viewModel: DashboardViewModel
    @State private var institutions: [BankInstitution] = []
    @State private var isLoadingInstitutions = false
    @State private var isConnecting = false
    @State private var errorMessage: String?
    @State private var showInstitutionPicker = false
    @State private var selectedCountry = "IT"
    @State private var searchInstitution = ""
    @State private var showDeleteSessionConfirm = false
    @State private var sessionToDelete: String?

    private let bankService = BankAPIService.shared
    private let firestoreService = FirestoreService.shared

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 20) {
                    // Connected Accounts
                    if !viewModel.bankAccounts.isEmpty {
                        connectedAccountsSection
                    }

                    // Connect New Bank
                    connectBankSection

                    if let error = errorMessage {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.caption)
                            .padding(.horizontal)
                    }
                }
                .padding(.vertical, 8)
            }
            .navigationTitle("Banca")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task { await syncBankAccounts() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(isConnecting)
                }
            }
            .sheet(isPresented: $showInstitutionPicker) {
                institutionPickerSheet
            }
            .onAppear {
                Task {
                    await loadInstitutions()
                    // Reload saved bank accounts from Firestore
                    if let userId = viewModel.userId {
                        if let accounts = try? await firestoreService.getBankAccounts(userId: userId) {
                            viewModel.bankAccounts = accounts
                        }
                    }
                }
            }
        }
    }

    // MARK: - Connected Accounts Section
    private var connectedAccountsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Conti collegati")
                .font(.headline)
                .padding(.horizontal)

            ForEach(viewModel.bankAccounts) { account in
                BankAccountCardView(
                    account: account,
                    settings: viewModel.accountSettings[account.id],
                    onSettingsUpdate: { settings in
                        Task {
                            guard let userId = viewModel.userId else { return }
                            try? await firestoreService.updateAccountSettings(
                                accountId: account.id,
                                userId: userId,
                                settings: settings
                            )
                        }
                    }
                )
                .padding(.horizontal)
            }
        }
    }

    // MARK: - Connect Bank Section
    private var connectBankSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Collega un conto bancario")
                .font(.headline)
                .padding(.horizontal)

            VStack(spacing: 16) {
                Image(systemName: "building.columns.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(Color.appPrimary)

                Text("Connetti il tuo conto bancario tramite Open Banking sicuro per sincronizzare automaticamente le transazioni.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                // Country Picker
                HStack {
                    Text("Paese:")
                        .font(.subheadline)
                    Picker("Paese", selection: $selectedCountry) {
                        Text("🇮🇹 Italia").tag("IT")
                        Text("🇩🇪 Germania").tag("DE")
                        Text("🇫🇷 Francia").tag("FR")
                        Text("🇪🇸 Spagna").tag("ES")
                        Text("🇳🇱 Paesi Bassi").tag("NL")
                    }
                    .pickerStyle(.menu)
                    .onChange(of: selectedCountry) { _, _ in
                        Task { await loadInstitutions() }
                    }
                }

                Button {
                    showInstitutionPicker = true
                } label: {
                    if isLoadingInstitutions {
                        Label("Caricamento banche...", systemImage: "building.columns")
                    } else {
                        Label("Seleziona la tua banca", systemImage: "building.columns")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isLoadingInstitutions || isConnecting)
            }
            .padding()
            .cardStyle()
            .padding(.horizontal)
        }
    }

    // MARK: - Institution Picker Sheet
    private var institutionPickerSheet: some View {
        NavigationStack {
            List {
                if institutions.isEmpty {
                    if isLoadingInstitutions {
                        HStack {
                            ProgressView()
                            Text("Caricamento banche...")
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text("Nessuna banca disponibile")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    ForEach(filteredInstitutions, id: \.name) { inst in
                        Button {
                            Task { await connectBank(institution: inst) }
                            showInstitutionPicker = false
                        } label: {
                            HStack {
                                if let logoURL = inst.logo, let url = URL(string: logoURL) {
                                    AsyncImage(url: url) { img in
                                        img.resizable().scaledToFit()
                                    } placeholder: {
                                        Image(systemName: "building.columns")
                                            .foregroundStyle(.secondary)
                                    }
                                    .frame(width: 32, height: 32)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                } else {
                                    Image(systemName: "building.columns")
                                        .font(.title3)
                                        .frame(width: 32, height: 32)
                                        .foregroundStyle(Color.appPrimary)
                                }
                                VStack(alignment: .leading) {
                                    Text(inst.displayName)
                                        .font(.subheadline.bold())
                                        .foregroundStyle(.primary)
                                    if let bic = inst.bic {
                                        Text(bic)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Seleziona la tua banca")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .searchable(text: $searchInstitution, prompt: "Cerca banca...")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") { showInstitutionPicker = false }
                }
            }
        }
    }

    private var filteredInstitutions: [BankInstitution] {
        if searchInstitution.isEmpty { return institutions }
        return institutions.filter {
            $0.displayName.localizedCaseInsensitiveContains(searchInstitution)
        }
    }

    // MARK: - Actions

    private func loadInstitutions() async {
        isLoadingInstitutions = true
        errorMessage = nil
        do {
            institutions = try await bankService.getInstitutions(country: selectedCountry)
        } catch {
            errorMessage = "Errore caricamento banche: \(error.localizedDescription)"
        }
        isLoadingInstitutions = false
    }

    private func connectBank(institution: BankInstitution) async {
        isConnecting = true
        errorMessage = nil
        do {
            // ASWebAuthenticationSession handles any scheme including custom ones
            // Enable Banking requires https:// redirect URLs.
            // This GitHub Pages page receives the code and redirects to spendwise://
            // ASWebAuthenticationSession then intercepts the spendwise:// callback.
            let redirectURL = "https://KuroZetsubou.github.io/spendwise-callback/"
            let authURL = try await bankService.initiateLink(
                aspspName: institution.name,
                country: selectedCountry,
                redirectURL: redirectURL
            )
            guard let url = URL(string: authURL) else {
                throw URLError(.badURL)
            }

            // Start OAuth session in-app — intercepts spendwise:// automatically
            let callbackURL = try await startWebAuthSession(url: url, callbackScheme: "spendwise")

            // Extract code from callback URL
            guard let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
                  let code = components.queryItems?.first(where: { $0.name == "code" })?.value
            else {
                throw EBError.invalidResponse("Missing auth code in callback URL: \(callbackURL)")
            }

            // Exchange code for session token
            guard let userId = viewModel.userId else { return }
            let session = try await bankService.exchangeCode(code)
            let sessionData: [String: Any] = [
                "accessToken": session.access_token ?? "",
                "sessionId": session.session_id ?? "",
                "createdAt": Date().timeIntervalSince1970
            ]
            try await firestoreService.saveBankSession(userId: userId, session: sessionData)
            await syncBankAccounts()
        } catch ASWebAuthenticationSessionError.canceledLogin {
            errorMessage = nil // user cancelled, no error needed
        } catch {
            errorMessage = "Errore connessione: \(error.localizedDescription)"
        }
        isConnecting = false
    }

    @MainActor
    private func startWebAuthSession(url: URL, callbackScheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            #if os(iOS)
            // Keep a strong reference to context inside the closure so ARC doesn't
            // deallocate it before ASWebAuthenticationSession (which holds it weakly) uses it.
            let context = WebAuthPresentationContext()
            #endif

            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: callbackScheme
            ) { callbackURL, error in
                #if os(iOS)
                _ = context // retain until session completes
                #endif
                if let error { continuation.resume(throwing: error); return }
                guard let callbackURL else {
                    continuation.resume(throwing: EBError.invalidResponse("No callback URL"))
                    return
                }
                continuation.resume(returning: callbackURL)
            }
            session.prefersEphemeralWebBrowserSession = false
            #if os(iOS)
            session.presentationContextProvider = context
            #endif
            session.start()
        }
    }
}

// MARK: - ASWebAuthenticationSession presentation context

#if os(iOS)
private final class WebAuthPresentationContext: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow } ?? ASPresentationAnchor()
    }
}
#endif

extension BankConnectView {

    private func syncBankAccounts() async {
        guard let userId = viewModel.userId else { return }
        isConnecting = true
        errorMessage = nil
        do {
            let sessions = try await firestoreService.getBankSessions(userId: userId)
            for session in sessions {
                guard let token = session["accessToken"] as? String else { continue }
                let ebAccounts = try await bankService.getAccounts(sessionToken: token)
                let sessionId = session["sessionId"] as? String
                var bankAccounts: [BankAccount] = ebAccounts.map { eb in
                    let bankBalances = (eb.balances ?? []).map { b in
                        BankBalance(amount: b.amountDouble, currency: b.currency, type: b.balance_type)
                    }
                    return BankAccount(
                        id: eb.id,
                        name: eb.name ?? eb.account_id?.iban ?? eb.id,
                        officialName: eb.details,
                        type: eb.cash_account_type ?? "CACC",
                        subtype: nil,
                        balances: bankBalances,
                        institutionId: nil,
                        institutionName: nil,
                        isCreditCard: nil,
                        creditLimit: nil,
                        paymentDay: nil,
                        excludeFromTotal: nil,
                        customName: nil,
                        warningThreshold: nil,
                        dangerThreshold: nil,
                        sessionId: sessionId,
                        currency: eb.currency,
                        calculatedBalance: nil,
                        cashAccountType: eb.cash_account_type
                    )
                }
                for i in bankAccounts.indices {
                    if let ebBalances = try? await bankService.getBalances(accountId: bankAccounts[i].id, sessionToken: token) {
                        bankAccounts[i].balances = ebBalances.map {
                            BankBalance(amount: $0.amountDouble, currency: $0.currency, type: $0.balance_type)
                        }
                    }
                }
                let encoded: [[String: Any]] = bankAccounts.compactMap { account in
                    try? Firestore.Encoder().encode(account)
                }
                try await firestoreService.saveBankAccounts(userId: userId, accounts: encoded)
                viewModel.bankAccounts = bankAccounts
            }
        } catch {
            errorMessage = "Errore sincronizzazione: \(error.localizedDescription)"
        }
        isConnecting = false
    }
}

// MARK: - Bank Account Card
struct BankAccountCardView: View {
    let account: BankAccount
    let settings: BankAccountSettings?
    var onSettingsUpdate: ((BankAccountSettings) -> Void)?

    @State private var showSettings = false

    private var balanceColor: Color {
        switch account.balanceStatus {
        case .normal: return Color.income
        case .warning: return Color(hex: "#F59E0B")
        case .danger: return Color.expense
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: iconForAccountType(account.cashAccountType ?? account.type))
                    .font(.title2)
                    .foregroundStyle(Color.appPrimary)
                    .frame(width: 44, height: 44)
                    .background(Color.appPrimary.opacity(0.1))
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(account.displayName)
                        .font(.subheadline.bold())
                    if let inst = account.institutionName {
                        Text(inst)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(account.currentBalance.currencyFormatted(code: account.displayCurrency))
                        .font(.subheadline.bold())
                        .foregroundStyle(balanceColor)
                    Text(account.type.capitalized)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()

            if account.isCreditCard == true, let limit = account.creditLimit {
                let used = limit - account.currentBalance
                let ratio = min(max(used / limit, 0), 1)
                VStack(spacing: 4) {
                    ProgressView(value: ratio)
                        .tint(ratio > 0.8 ? Color.expense : Color.appPrimary)
                    HStack {
                        Text("Usato: \(used.euroFormatted)")
                        Spacer()
                        Text("Limite: \(limit.euroFormatted)")
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
                .padding([.horizontal, .bottom])
            }
        }
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.08), radius: 6, x: 0, y: 2)
        .overlay(
            account.isExcluded
            ? RoundedRectangle(cornerRadius: 12).strokeBorder(Color.secondary.opacity(0.3), lineWidth: 1)
            : nil
        )
        .opacity(account.isExcluded ? 0.6 : 1.0)
    }

    private func iconForAccountType(_ type: String) -> String {
        switch type.uppercased() {
        case "CACC", "SVGS": return "building.columns"
        case "CARD": return "creditcard"
        case "CASH": return "banknote"
        case "LOAN": return "dollarsign.circle"
        default: return "building.columns"
        }
    }
}

#Preview {
    BankConnectView(viewModel: DashboardViewModel())
        .environmentObject(AuthViewModel())
}
