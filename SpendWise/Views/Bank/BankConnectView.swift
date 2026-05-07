import SwiftUI
import FirebaseFirestore

struct BankConnectView: View {
    @ObservedObject var viewModel: DashboardViewModel
    @State private var institutions: [BankInstitution] = []
    @State private var isLoadingInstitutions = false
    @State private var isConnecting = false
    @State private var errorMessage: String?
    @State private var showInstitutionPicker = false
    @State private var selectedCountry = "IT"
    @State private var searchInstitution = ""
    @State private var showSyncResult = false
    @State private var lastSyncResult: TransactionSyncService.SyncResult?
    @State private var syncDays = 30
    @State private var showTRImport = false
    @State private var showTRCountryPicker = false

    // Countries where Trade Republic holds a banking licence and is reachable via Enable Banking
    private let trCountries: [(code: String, flag: String, name: String)] = [
        ("AT", "🇦🇹", "Austria"),
        ("BE", "🇧🇪", "Belgio"),
        ("BG", "🇧🇬", "Bulgaria"),
        ("HR", "🇭🇷", "Croazia"),
        ("CZ", "🇨🇿", "Repubblica Ceca"),
        ("DK", "🇩🇰", "Danimarca"),
        ("EE", "🇪🇪", "Estonia"),
        ("FI", "🇫🇮", "Finlandia"),
        ("FR", "🇫🇷", "Francia"),
        ("DE", "🇩🇪", "Germania"),
        ("GR", "🇬🇷", "Grecia"),
        ("HU", "🇭🇺", "Ungheria"),
        ("IE", "🇮🇪", "Irlanda"),
        ("IT", "🇮🇹", "Italia"),
        ("LV", "🇱🇻", "Lettonia"),
        ("LT", "🇱🇹", "Lituania"),
        ("LU", "🇱🇺", "Lussemburgo"),
        ("NL", "🇳🇱", "Paesi Bassi"),
        ("NO", "🇳🇴", "Norvegia"),
        ("PL", "🇵🇱", "Polonia"),
        ("PT", "🇵🇹", "Portogallo"),
        ("RO", "🇷🇴", "Romania"),
        ("SK", "🇸🇰", "Slovacchia"),
        ("SI", "🇸🇮", "Slovenia"),
        ("ES", "🇪🇸", "Spagna"),
        ("SE", "🇸🇪", "Svezia"),
    ]

    private let bankService = BankAPIService.shared
    private let firestoreService = FirestoreService.shared

    var body: some View {
        NavigationStack {
            List {
                // ── Patrimonio totale ───────────────────────────────
                if !viewModel.resolvedBankAccounts.isEmpty {
                    Section {
                        VStack(spacing: 8) {
                            Text("Patrimonio netto")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(totalNetWorth.euroFormatted)
                                .font(.title.bold())
                                .foregroundStyle(totalNetWorth >= 0 ? Color.income : Color.expense)
                            Text("\(viewModel.resolvedBankAccounts.count) conti · \(viewModel.bankSessions.count) banche")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                    }
                }
                
                // ── Connected Institutions ──────────────────────────
                if !viewModel.bankSessions.isEmpty {
                    Section("Banche collegate") {
                        ForEach(viewModel.bankSessions) { session in
                            let isManual  = session.isManual == true
                            let isExpired = !isManual && ["EXPIRED", "REVOKED", "UNAUTHORIZED"].contains(session.status?.uppercased() ?? "")
                            if isExpired {
                                bankSessionRow(session)
                                    .overlay(alignment: .bottomTrailing) {
                                        Button {
                                            Task { await reconnectSession(session) }
                                        } label: {
                                            Label("Riconnetti", systemImage: "arrow.clockwise.circle.fill")
                                                .font(.caption.bold())
                                                .padding(.horizontal, 8).padding(.vertical, 4)
                                                .background(Color.orange)
                                                .foregroundStyle(.white)
                                                .clipShape(Capsule())
                                        }
                                        .offset(y: 4)
                                    }
                            } else {
                                NavigationLink(value: session) {
                                    bankSessionRow(session)
                                }
                            }
                        }
                    }
                }

                // ── Sync Transactions ────────────────────────────────
                if !viewModel.bankSessions.isEmpty {
                    Section("Sincronizza transazioni") {
                        HStack {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .foregroundStyle(Color.appPrimary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Importa transazioni bancarie")
                                    .font(.subheadline)
                                Text("Scarica le transazioni dagli ultimi \(syncDays) giorni")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if viewModel.isSyncingTransactions {
                                ProgressView()
                            }
                        }

                        Picker("Periodo", selection: $syncDays) {
                            Text("7 giorni").tag(7)
                            Text("30 giorni").tag(30)
                            Text("90 giorni").tag(90)
                            Text("180 giorni").tag(180)
                            Text("1 anno").tag(365)
                        }
                        .pickerStyle(.menu)

                        Button {
                            Task {
                                lastSyncResult = await viewModel.syncBankTransactions(days: syncDays)
                                showSyncResult = true
                            }
                        } label: {
                            HStack {
                                Spacer()
                                Label("Sincronizza ora", systemImage: "arrow.down.circle.fill")
                                    .font(.subheadline.bold())
                                Spacer()
                            }
                        }
                        .disabled(viewModel.isSyncingTransactions)

                        if viewModel.isSyncingTransactions, let progress = viewModel.syncProgress {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Conto: \(progress.currentAccount)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                HStack {
                                    Text("Account \(progress.accountIndex + 1)/\(progress.totalAccounts)")
                                    Spacer()
                                    Text("\(progress.transactionsImported) importate")
                                }
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                if progress.totalAccounts > 0 {
                                    ProgressView(value: Double(progress.accountIndex), total: Double(progress.totalAccounts))
                                        .tint(Color.appPrimary)
                                }
                            }
                        }
                    }
                }

                // ── Connect New Bank ────────────────────────────────
                Section {
                    connectBankContent
                } header: {
                    Label("Collega un conto bancario", systemImage: "eurosign.bank.building")
                }

                // ── Trade Republic ───────────────────────────────────
                Section {
//                    Button {
//                        showTRCountryPicker = true
//                    } label: {
//                        HStack(spacing: 12) {
//                            ZStack {
//                                Circle()
//                                    .fill(Color.green.opacity(0.12))
//                                    .frame(width: 40, height: 40)
//                                Text("🟢")
//                                    .font(.title3)
//                            }
//                            VStack(alignment: .leading, spacing: 2) {
//                                Text("Collega Trade Republic")
//                                    .font(.subheadline.bold())
//                                    .foregroundStyle(.primary)
//                                Text("Open Banking · 26 paesi EU")
//                                    .font(.caption)
//                                    .foregroundStyle(.secondary)
//                            }
//                            Spacer()
//                            Image(systemName: "chevron.right")
//                                .font(.caption)
//                                .foregroundStyle(.secondary)
//                        }
//                    }

                    Button {
                        showTRImport = true
                    } label: {
                        HStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(Color.green.opacity(0.12))
                                    .frame(width: 40, height: 40)
                                Image(systemName: "doc.text")
                                    .font(.title3)
                                    .foregroundStyle(.green)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Importa CSV Trade Republic")
                                    .font(.subheadline.bold())
                                    .foregroundStyle(.primary)
                                Text("Importa account_transactions.csv")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Label("Trade Republic", systemImage: "chart.line.uptrend.xyaxis")
                }

                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("Banca")
            .navigationDestination(for: BankSession.self) { session in
                BankSessionDetailView(session: session, viewModel: viewModel) {
                    Task { await reconnectSession(session) }
                }
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task { await syncBankAccounts() }
                    } label: {
                        if isConnecting {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .disabled(isConnecting)
                }
            }
            .sheet(isPresented: $showInstitutionPicker) {
                institutionPickerSheet
            }
            .sheet(isPresented: $showTRImport) {
                TradeRepublicImportView(viewModel: viewModel)
            }
            .confirmationDialog("Seleziona il tuo paese", isPresented: $showTRCountryPicker, titleVisibility: .visible) {
                ForEach(trCountries, id: \.code) { country in
                    Button("\(country.flag) \(country.name)") {
                        selectedCountry = country.code
                        Task {
                            await loadInstitutions()
                            searchInstitution = "Trade Republic"
                            showInstitutionPicker = true
                        }
                    }
                }
                Button("Annulla", role: .cancel) {}
            }
            .alert("Sincronizzazione completata", isPresented: $showSyncResult) {
                Button("OK") {}
            } message: {
                if let r = lastSyncResult {
                    let msg = "\(r.imported) transazioni importate da \(r.accountsProcessed) conti."
                    if r.errors.isEmpty {
                        Text(msg)
                    } else {
                        Text("\(msg)\n\nErrori: \(r.errors.joined(separator: ", "))")
                    }
                }
            }
            .onAppear {
                Task {
                    await loadInstitutions()
                    if let userId = viewModel.userId {
                        await viewModel.refreshBankSessions()
                    }
                }
            }
        }
    }

    // MARK: - Total Net Worth

    private var totalNetWorth: Double {
        viewModel.resolvedBankAccounts
            .filter { !$0.isExcluded }
            .reduce(0) { $0 + $1.currentBalance }
    }

    // MARK: - Session Row

    private func bankSessionRow(_ session: BankSession) -> some View {
        let accountsForSession = viewModel.resolvedBankAccounts.filter { $0.sessionId == session.sessionId }
        let totalBalance = accountsForSession.reduce(0) { $0 + $1.currentBalance }
        let isManual  = session.isManual == true
        let isExpired = !isManual && ["EXPIRED", "REVOKED", "UNAUTHORIZED"].contains(session.status?.uppercased() ?? "")

        return HStack(spacing: 12) {
            Image(systemName: isManual ? "square.and.pencil" : isExpired ? "exclamationmark.triangle.fill" : "building.columns.fill")
                .font(.title2)
                .foregroundStyle(isManual ? Color.appPrimary : isExpired ? .orange : Color.appPrimary)
                .frame(width: 44, height: 44)
                .background((isExpired ? Color.orange : Color.appPrimary).opacity(0.1))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(session.displayInstitutionName ?? "Banca")
                    .font(.subheadline.bold())
                HStack(spacing: 6) {
                    Text(isManual ? "1 conto" : "\(accountsForSession.count) conti")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if isManual {
                        Text("Manuale")
                            .font(.caption2.bold())
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background(Color.appPrimary.opacity(0.15))
                            .foregroundStyle(Color.appPrimary)
                            .clipShape(Capsule())
                    } else if isExpired {
                        Text("Scaduta — Riconnetti")
                            .font(.caption2.bold())
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background(Color.orange.opacity(0.15))
                            .foregroundStyle(Color.orange)
                            .clipShape(Capsule())
                    } else if let status = session.status {
                        Text(status == "AUTHORIZED" ? "Attiva" : status)
                            .font(.caption2)
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background(status == "AUTHORIZED" ? Color.income.opacity(0.15) : Color.secondary.opacity(0.15))
                            .foregroundStyle(status == "AUTHORIZED" ? Color.income : Color.secondary)
                            .clipShape(Capsule())
                    }
                }
                if isExpired {
                    Text("Tocca 'Riconnetti' per rinnovare l'accesso")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if !isExpired {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(totalBalance.euroFormatted)
                        .font(.subheadline.bold())
                        .foregroundStyle(totalBalance >= 0 ? Color.income : Color.expense)
                    Text(isManual ? "saldo" : "totale")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
        .opacity(isExpired ? 0.8 : 1.0)
    }

    // MARK: - Connect Bank Content

    private var connectBankContent: some View {
        VStack(spacing: 24) {
            HStack {
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

            if #available(iOS 26.0, *) {
                Button {
                    showInstitutionPicker = true
                } label: {
                    Label(
                        isLoadingInstitutions ? "Caricamento banche..." : "Seleziona la tua banca", systemImage: "arrow.2.circlepath.plus"
                    )
                }
                .buttonStyle(.glassProminent)
                .foregroundColor(.white)
                .disabled(isLoadingInstitutions || isConnecting)
            } else {
                // Fallback on earlier versions
                Button {
                    showInstitutionPicker = true
                } label: {
                    Label(
                        isLoadingInstitutions ? "Caricamento banche..." : "Seleziona la tua banca", systemImage: "arrow.2.circlepath.circle"
                    )
                }
                .buttonStyle(.bordered)
                .disabled(isLoadingInstitutions || isConnecting)
            }
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
            let code = try await startBankAuth(aspspName: institution.name, country: selectedCountry)
            guard let userId = viewModel.userId else { return }
            try await finishBankAuth(code: code, aspspName: institution.name, country: selectedCountry, userId: userId)
        } catch is CancellationError {
            errorMessage = nil
        } catch {
            errorMessage = "Errore connessione: \(error.localizedDescription)"
        }
        isConnecting = false
    }

    private func reconnectSession(_ session: BankSession) async {
        guard let aspspName = session.displayInstitutionName,
              let userId = viewModel.userId else { return }
        isConnecting = true
        errorMessage = nil
        do {
            let country = session.aspsp?.country ?? "IT"
            let code = try await startBankAuth(aspspName: aspspName, country: country)
            // Delete old expired session
            if let oldSessionId = session.sessionId {
                try? await firestoreService.deleteBankSession(userId: userId, sessionId: oldSessionId)
            }
            try await finishBankAuth(code: code, aspspName: aspspName, country: country, userId: userId)
        } catch is CancellationError {
            errorMessage = nil
        } catch {
            errorMessage = "Errore riconnessione: \(error.localizedDescription)"
        }
        isConnecting = false
    }

    /// Opens the Enable Banking OAuth page in **external Safari** (avoids bank popup blocks).
    /// Returns the auth code once the user completes the flow and is redirected back.
    private func startBankAuth(aspspName: String, country: String) async throws -> String {
        // Use spendwise://callback as redirect — iOS intercepts it and calls onOpenURL
        let redirectURL = "https://kurozetsubou.github.io/spendwise-callback/"
        let authURL = try await bankService.initiateLink(
            aspspName: aspspName,
            country: country,
            redirectURL: redirectURL
        )
        guard let url = URL(string: authURL) else { throw URLError(.badURL) }

        // Open in external Safari (works with banks that block in-app browsers)
        #if canImport(UIKit)
        await UIApplication.shared.open(url)
        #else
        NSWorkspace.shared.open(url)
        #endif

        // Wait for spendwise://callback?code=... from AuthCallbackHandler
        return try await AuthCallbackHandler.shared.waitForCode(timeout: 300)
    }

    private func finishBankAuth(code: String, aspspName: String, country: String, userId: String) async throws {
        let session = try await bankService.exchangeCode(code)
        let accountsData: [[String: Any]] = session.accounts?.compactMap { acc -> [String: Any]? in
            guard let uid = acc.uid else { return nil }
            var entry: [String: Any] = ["uid": uid, "currency": acc.currency ?? "EUR",
                                        "cash_account_type": acc.cash_account_type ?? ""]
            if let name = acc.name { entry["name"] = name }
            if let iban = acc.account_id?.iban { entry["account_id"] = ["iban": iban] }
            return entry
        } ?? []
        let sessionData: [String: Any] = [
            "accessToken": session.access_token as Any,
            "accounts": accountsData,
            "sessionId": session.session_id ?? "",
            "aspsp": ["name": aspspName, "country": country],
            "description": "Connection to \(aspspName)",
            "status": "AUTHORIZED",
            "createdAt": ISO8601DateFormatter().string(from: Date())
        ]
        try await firestoreService.saveBankSession(userId: userId, session: sessionData)
        await viewModel.refreshBankSessions()
        await syncBankAccounts()
    }
}

extension BankConnectView {
    func syncBankAccounts() async {
        guard let userId = viewModel.userId else { return }
        isConnecting = true
        errorMessage = nil
        do {
            let sessions = try await firestoreService.getBankSessions(userId: userId)
            for session in sessions {
                let token = session["accessToken"] as? String
                let effectiveToken: String? = (token != nil && !token!.isEmpty) ? token : nil
                let sessionId = session["sessionId"] as? String
                let aspspName = (session["aspsp"] as? [String: Any])?["name"] as? String

                // Get accounts: prefer stored in session, fallback to API
                var ebAccounts: [EBAccount] = []
                if let sessionAccounts = session["accounts"] as? [[String: Any]] {
                    // Decode accounts from session doc
                    for acc in sessionAccounts {
                        let uid = acc["uid"] as? String
                        let iban = (acc["account_id"] as? [String: Any])?["iban"] as? String
                        let name = acc["name"] as? String
                        let currency = acc["currency"] as? String
                        let cashType = acc["cash_account_type"] as? String
                        if let uid {
                            ebAccounts.append(EBAccount(
                                uid: uid,
                                account_id: iban.map { EBAccount.AccountId(iban: $0) },
                                name: name,
                                cash_account_type: cashType,
                                currency: currency
                            ))
                        }
                    }
                }
                if ebAccounts.isEmpty {
                    ebAccounts = try await bankService.getAccounts(sessionToken: effectiveToken)
                }

                var bankAccounts: [BankAccount] = ebAccounts.map { eb in
                    let bankBalances = (eb.balances ?? []).map { b in
                        BankBalance(amount: b.amountDouble, currency: b.currency, type: b.balance_type)
                    }
                    return BankAccount(
                        id: eb.id,
                        name: eb.name ?? eb.account_id?.iban ?? eb.id,
                        officialName: eb.account_id?.iban ?? eb.details,
                        type: eb.cash_account_type ?? "CACC",
                        subtype: nil,
                        balances: bankBalances,
                        institutionId: nil,
                        institutionName: aspspName,
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
                    if let ebBalances = try? await bankService.getBalances(accountId: bankAccounts[i].id, sessionToken: effectiveToken) {
                        bankAccounts[i].balances = ebBalances.map {
                            BankBalance(amount: $0.amountDouble, currency: $0.currency, type: $0.balance_type)
                        }
                    }
                }
                let encoded: [[String: Any]] = bankAccounts.compactMap { account in
                    try? Firestore.Encoder().encode(account)
                }
                try await firestoreService.saveBankAccounts(userId: userId, accounts: encoded)
            }
        } catch {
            errorMessage = "Errore sincronizzazione: \(error.localizedDescription)"
        }
        isConnecting = false
    }
}

// MARK: - Bank Account Card (reusable)

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
                    Text(account.accountTypeLabel)
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


#Preview("BankConnectView") {
    // Create a lightweight preview view model. Adjust the initializer if your DashboardViewModel requires different params.
    let dashboardVM = DashboardViewModel()
    return BankConnectView(viewModel: dashboardVM)
        .environmentObject(AuthViewModel())
}
