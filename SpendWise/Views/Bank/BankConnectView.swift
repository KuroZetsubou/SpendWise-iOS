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
            ScrollView {
                VStack(spacing: DS.Space.sectionGap) {
                    heroHeader

                    VStack(spacing: DS.Space.sectionGap) {
                        if !viewModel.bankSessions.isEmpty {
                            connectedBanksSection
                            syncSection
                        }
                        connectBankSection
                        tradeRepublicSection

                        if let error = errorMessage {
                            DSCard(.card, padding: DS.Space.cardPad) {
                                HStack(spacing: DS.Space.x2) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundStyle(DS.Colors.expense)
                                    Text(error).dsText(DS.Font.body, color: DS.Colors.expense)
                                }
                            }
                        }
                    }
                    .dsGutter()
                }
                .padding(.bottom, DS.Space.x8)
            }
            .scrollIndicators(.hidden)
            .background(DS.Colors.bgApp)
            .ignoresSafeArea(edges: .top)
            .navigationDestination(for: BankSession.self) { session in
                BankSessionDetailView(session: session, viewModel: viewModel) {
                    Task { await reconnectSession(session) }
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
                    if viewModel.userId != nil {
                        await viewModel.refreshBankSessions()
                    }
                }
            }
        }
    }

    // MARK: - Hero
    //
    // Navy panel carrying the net worth figure, per the kit's balance header.

    private var heroHeader: some View {
        VStack(alignment: .leading, spacing: DS.Space.x5) {
            HStack(spacing: DS.Space.x3) {
                Text("Banca").dsText(DS.Font.h2, color: DS.Colors.textOnDark)
                Spacer(minLength: DS.Space.x2)
                DSIconButton(isConnecting ? "hourglass" : "arrow.clockwise",
                             tone: .onDark, size: 44) {
                    Task { await syncBankAccounts() }
                }
                .disabled(isConnecting)
            }

            if viewModel.resolvedBankAccounts.isEmpty {
                VStack(alignment: .leading, spacing: DS.Space.x2) {
                    Text("Nessun conto collegato")
                        .dsText(DS.Font.h3, color: DS.Colors.textOnDark)
                    Text("Collega il tuo conto bancario per tracciare le spese automaticamente e in un unico posto.")
                        .dsText(DS.Font.body, color: DS.Colors.textOnDarkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                DSBalanceHeader(
                    label: "Patrimonio netto",
                    amount: totalNetWorth.dsAmount,
                    caption: "\(viewModel.resolvedBankAccounts.count) conti • \(viewModel.bankSessions.count) banche"
                )
            }
        }
        .padding(.horizontal, DS.Space.gutter)
        .padding(.top, DS.Space.x16)
        .padding(.bottom, DS.Space.x6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.Gradients.hero)
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: 0, bottomLeadingRadius: DS.Radius.xl2,
                bottomTrailingRadius: DS.Radius.xl2, topTrailingRadius: 0,
                style: .continuous
            )
        )
    }

    // MARK: - Connected banks

    private var connectedBanksSection: some View {
        VStack(alignment: .leading, spacing: DS.Space.x4) {
            DSSectionHeader("Banche Collegate")

            VStack(spacing: DS.Space.rowGap) {
                ForEach(viewModel.bankSessions) { session in
                    let isManual  = session.isManual == true
                    let isExpired = !isManual && ["EXPIRED", "REVOKED", "UNAUTHORIZED"].contains(session.status?.uppercased() ?? "")
                    if isExpired {
                        VStack(spacing: DS.Space.x3) {
                            bankSessionRow(session)
                            DSButton("Riconnetti", icon: "arrow.clockwise",
                                     variant: .secondary, size: .small, block: true) {
                                Task { await reconnectSession(session) }
                            }
                        }
                        .padding(DS.Space.cardPad)
                        .background(DS.Colors.surfaceSunken)
                        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
                    } else {
                        NavigationLink(value: session) {
                            bankSessionRow(session)
                                .padding(DS.Space.cardPad)
                                .background(DS.Colors.surfaceSunken)
                                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card,
                                                            style: .continuous))
                        }
                        .buttonStyle(DSPressStyle())
                    }
                }
            }
        }
    }

    // MARK: - Sync

    private var syncSection: some View {
        VStack(alignment: .leading, spacing: DS.Space.x4) {
            DSSectionHeader("Sincronizza Transazioni")

            DSCard(.card) {
                VStack(alignment: .leading, spacing: DS.Space.x4) {
                    Text("Scarica le transazioni degli ultimi \(syncDays) giorni dai conti collegati.")
                        .dsText(DS.Font.body, color: DS.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Menu {
                        Button("7 giorni")   { syncDays = 7 }
                        Button("30 giorni")  { syncDays = 30 }
                        Button("90 giorni")  { syncDays = 90 }
                        Button("180 giorni") { syncDays = 180 }
                        Button("1 anno")     { syncDays = 365 }
                    } label: {
                        HStack(spacing: DS.Space.x3) {
                            Image(systemName: "calendar")
                                .font(.system(size: 17, weight: .medium))
                                .foregroundStyle(DS.Colors.textMuted)
                            Text("Periodo").dsText(DS.Font.body, color: DS.Colors.textSecondary)
                            Spacer(minLength: DS.Space.x2)
                            Text(syncDays == 365 ? "1 anno" : "\(syncDays) giorni")
                                .dsText(DS.Font.bodyMedium, color: DS.Colors.textBody)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(DS.Palette.gray400)
                        }
                        .padding(.horizontal, DS.Space.cardPad)
                        .frame(height: 52)
                        .background(DS.Colors.surfaceSunken)
                        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.field, style: .continuous))
                    }

                    if viewModel.isSyncingTransactions, let progress = viewModel.syncProgress {
                        VStack(alignment: .leading, spacing: DS.Space.x2) {
                            Text(progress.currentAccount)
                                .dsText(DS.Font.meta, color: DS.Colors.textMuted)
                                .lineLimit(1)
                            DSProgressBar(
                                value: progress.totalAccounts > 0
                                    ? Double(progress.accountIndex) / Double(progress.totalAccounts)
                                    : 0,
                                leftLabel: "Conto \(progress.accountIndex + 1) di \(progress.totalAccounts)",
                                rightLabel: "\(progress.transactionsImported) importate"
                            )
                        }
                    }

                    DSButton(viewModel.isSyncingTransactions ? "Sincronizzazione…" : "Sincronizza Ora",
                             icon: "arrow.down.circle",
                             variant: .primary, size: .large, block: true) {
                        Task {
                            lastSyncResult = await viewModel.syncBankTransactions(days: syncDays)
                            showSyncResult = true
                        }
                    }
                    .disabled(viewModel.isSyncingTransactions)
                }
            }
        }
    }

    // MARK: - Connect a new bank

    private var connectBankSection: some View {
        VStack(alignment: .leading, spacing: DS.Space.x4) {
            DSSectionHeader("Collega una Banca")
            connectBankContent
        }
    }

    // MARK: - Trade Republic

    private var tradeRepublicSection: some View {
        VStack(alignment: .leading, spacing: DS.Space.x4) {
            DSSectionHeader("Trade Republic")

            DSCard(.card, padding: DS.Space.cardPad) {
                VStack(spacing: 0) {
                    DSListRow(icon: "chart.line.uptrend.xyaxis",
                              iconTint: DS.Colors.income,
                              iconBackground: DS.Palette.green50,
                              label: "Collega Trade Republic",
                              sublabel: "Open Banking • 26 paesi EU") {
                        showTRCountryPicker = true
                    }
                    DSListRow(icon: "doc.text",
                              iconTint: DS.Colors.income,
                              iconBackground: DS.Palette.green50,
                              label: "Importa CSV",
                              sublabel: "Importa account_transactions.csv") {
                        showTRImport = true
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
        let tint: Color = isExpired ? DS.Palette.amber500 : DS.Colors.actionPrimary

        return HStack(spacing: DS.Space.x3) {
            DSIconTile(isManual ? "square.and.pencil"
                       : isExpired ? "exclamationmark.triangle.fill" : "building.columns.fill",
                       size: 44,
                       background: DS.Colors.surfaceCard,
                       foreground: tint)

            VStack(alignment: .leading, spacing: DS.Space.x1) {
                Text(session.displayInstitutionName ?? "Banca")
                    .dsText(DS.Font.h3, color: DS.Colors.textBody)
                    .lineLimit(1)

                HStack(spacing: DS.Space.x2) {
                    Text(isManual ? "1 conto" : "\(accountsForSession.count) conti")
                        .dsText(DS.Font.meta, color: DS.Colors.textMuted)

                    if isManual {
                        DSBadge("Manuale", tone: .info)
                    } else if isExpired {
                        DSBadge("Scaduta", tone: .warning)
                    } else if let status = session.status {
                        DSBadge(status == "AUTHORIZED" ? "Attiva" : status,
                                tone: status == "AUTHORIZED" ? .success : .neutral)
                    }
                }
            }

            Spacer(minLength: DS.Space.x2)

            if !isExpired {
                VStack(alignment: .trailing, spacing: 1) {
                    Text(totalBalance.dsAmount)
                        .dsText(DS.Font.Style(size: 16, weight: .bold, lineHeight: 22),
                                color: totalBalance >= 0 ? DS.Colors.income : DS.Colors.expense)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(isManual ? "saldo" : "totale")
                        .dsText(DS.Font.meta, color: DS.Colors.textMuted)
                }
            }
        }
        .opacity(isExpired ? 0.85 : 1.0)
    }

    // MARK: - Connect Bank Content

    private var connectBankContent: some View {
        DSCard(.card) {
            VStack(alignment: .leading, spacing: DS.Space.x4) {
                Text("Connetti il tuo conto per un tracciamento delle spese automatico, senza inserimenti manuali.")
                    .dsText(DS.Font.body, color: DS.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                Menu {
                    Button("🇮🇹 Italia")       { selectedCountry = "IT" }
                    Button("🇩🇪 Germania")     { selectedCountry = "DE" }
                    Button("🇫🇷 Francia")      { selectedCountry = "FR" }
                    Button("🇪🇸 Spagna")       { selectedCountry = "ES" }
                    Button("🇳🇱 Paesi Bassi")  { selectedCountry = "NL" }
                } label: {
                    HStack(spacing: DS.Space.x3) {
                        Image(systemName: "globe")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(DS.Colors.textMuted)
                        Text("Paese").dsText(DS.Font.body, color: DS.Colors.textSecondary)
                        Spacer(minLength: DS.Space.x2)
                        Text(countryLabel(selectedCountry))
                            .dsText(DS.Font.bodyMedium, color: DS.Colors.textBody)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(DS.Palette.gray400)
                    }
                    .padding(.horizontal, DS.Space.cardPad)
                    .frame(height: 52)
                    .background(DS.Colors.surfaceSunken)
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.field, style: .continuous))
                }
                .onChange(of: selectedCountry) { _, _ in
                    Task { await loadInstitutions() }
                }

                DSButton(isLoadingInstitutions ? "Caricamento Banche…" : "Seleziona la Tua Banca",
                         icon: "building.columns",
                         variant: .primary, size: .large, block: true) {
                    showInstitutionPicker = true
                }
                .disabled(isLoadingInstitutions || isConnecting)
            }
        }
    }

    private func countryLabel(_ code: String) -> String {
        switch code {
        case "IT": return "🇮🇹 Italia"
        case "DE": return "🇩🇪 Germania"
        case "FR": return "🇫🇷 Francia"
        case "ES": return "🇪🇸 Spagna"
        case "NL": return "🇳🇱 Paesi Bassi"
        default:   return code
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
            .scrollContentBackground(.hidden)
            .background(DS.Colors.bgApp)
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
        case .normal:  return DS.Colors.income
        case .warning: return DS.Palette.amber500
        case .danger:  return DS.Colors.expense
        }
    }

    var body: some View {
        DSCard(account.isExcluded ? .outline : .card) {
            VStack(spacing: DS.Space.x4) {
                HStack(spacing: DS.Space.x3) {
                    DSIconTile(iconForAccountType(account.cashAccountType ?? account.type),
                               size: 44)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(account.displayName)
                            .dsText(DS.Font.h3, color: DS.Colors.textBody)
                            .lineLimit(1)
                        if let inst = account.institutionName {
                            Text(inst).dsText(DS.Font.meta, color: DS.Colors.textMuted).lineLimit(1)
                        }
                    }

                    Spacer(minLength: DS.Space.x2)

                    VStack(alignment: .trailing, spacing: 1) {
                        Text(account.currentBalance.currencyFormatted(code: account.displayCurrency))
                            .dsText(DS.Font.Style(size: 16, weight: .bold, lineHeight: 22),
                                    color: balanceColor)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Text(account.accountTypeLabel)
                            .dsText(DS.Font.meta, color: DS.Colors.textMuted)
                    }
                }

                if account.isCreditCard == true, let limit = account.creditLimit {
                    let used = limit - account.currentBalance
                    let ratio = min(max(used / limit, 0), 1)
                    DSProgressBar(
                        value: ratio,
                        color: ratio > 0.8 ? DS.Colors.expense : DS.Colors.actionPrimary,
                        leftLabel: "Usato \(used.dsAmount)",
                        rightLabel: "Limite \(limit.dsAmount)"
                    )
                }
            }
        }
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
