import SwiftUI

struct AccountSettingsEditView: View {
    let account: BankAccount
    @ObservedObject var viewModel: DashboardViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var customName: String = ""
    @State private var isCreditCard: Bool = false
    @State private var creditLimitString: String = ""
    @State private var paymentDay: Int = 1
    @State private var excludeFromTotal: Bool = false
    @State private var syncDisabled: Bool = false
    @State private var warningThresholdString: String = ""
    @State private var dangerThresholdString: String = ""
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Form {
                // MARK: - Nome conto
                Section("Nome visualizzato") {
                    TextField("Nome personalizzato", text: $customName)
                        .autocorrectionDisabled()
                    if !account.name.isEmpty && customName != account.name {
                        Text("Nome originale: \(account.name)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                // MARK: - Tipo conto
                Section("Tipo conto") {
                    Toggle("Carta di credito / pagamento", isOn: $isCreditCard)

                    if isCreditCard {
                        HStack {
                            Text("Plafond (€)")
                                .foregroundStyle(.secondary)
                            Spacer()
                            TextField("0,00", text: $creditLimitString)
                                #if os(iOS)
                                .keyboardType(.decimalPad)
                                #endif
                                .multilineTextAlignment(.trailing)
                                .frame(maxWidth: 120)
                        }

                        Picker("Giorno di pagamento", selection: $paymentDay) {
                            ForEach(1...28, id: \.self) { day in
                                Text("Giorno \(day)").tag(day)
                            }
                        }
                    }

                    Toggle("Escludi dal totale patrimonio", isOn: $excludeFromTotal)
                    if account.isManual != true {
                        Toggle("Non aggiornare transazioni automaticamente", isOn: $syncDisabled)
                    }
                }

                // MARK: - Soglie di attenzione
                Section {
                    HStack {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(Color(hex: "#F59E0B"))
                            .frame(width: 24)
                        Text("Soglia attenzione (€)")
                            .foregroundStyle(.secondary)
                        Spacer()
                        TextField("Es. 500", text: $warningThresholdString)
                            #if os(iOS)
                            .keyboardType(.decimalPad)
                            #endif
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 100)
                    }
                    HStack {
                        Image(systemName: "exclamationmark.octagon")
                            .foregroundStyle(Color.expense)
                            .frame(width: 24)
                        Text("Soglia pericolo (€)")
                            .foregroundStyle(.secondary)
                        Spacer()
                        TextField("Es. 100", text: $dangerThresholdString)
                            #if os(iOS)
                            .keyboardType(.decimalPad)
                            #endif
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 100)
                    }
                } header: {
                    Text("Soglie saldo")
                } footer: {
                    Text("Ricevi un avviso colorato quando il saldo scende sotto queste soglie.")
                        .font(.caption2)
                }
            }
            .navigationTitle("Impostazioni conto")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salva") {
                        Task { await save() }
                    }
                    .bold()
                    .disabled(isSaving)
                }
            }
            .onAppear { populate() }
        }
    }

    // MARK: - Populate from existing settings
    private func populate() {
        let s = viewModel.accountSettings[account.id]
        customName = s?.customName ?? account.customName ?? account.name
        isCreditCard = s?.isCreditCard ?? (account.isCreditCard == true)
        let rawLimit = s?.creditLimit ?? account.creditLimit ?? 0
        creditLimitString = rawLimit > 0 ? String(format: "%.2f", rawLimit).replacingOccurrences(of: ".", with: ",") : ""
        paymentDay = s?.paymentDay ?? account.paymentDay ?? 1
        excludeFromTotal = s?.excludeFromTotal ?? (account.excludeFromTotal == true)
        syncDisabled = s?.syncDisabled ?? false
        if let w = s?.warningThreshold ?? account.warningThreshold, w > 0 {
            warningThresholdString = String(format: "%.0f", w)
        }
        if let d = s?.dangerThreshold ?? account.dangerThreshold, d > 0 {
            dangerThresholdString = String(format: "%.0f", d)
        }
    }

    // MARK: - Save
    private func save() async {
        guard let userId = viewModel.userId else { return }
        isSaving = true
        defer { isSaving = false }

        let cleanLimit = creditLimitString.replacingOccurrences(of: ",", with: ".")
        let cleanWarning = warningThresholdString.replacingOccurrences(of: ",", with: ".")
        let cleanDanger = dangerThresholdString.replacingOccurrences(of: ",", with: ".")

        var settings = BankAccountSettings(
            id: account.id,
            userId: userId,
            isCreditCard: isCreditCard,
            creditLimit: Double(cleanLimit) ?? 0,
            paymentDay: paymentDay,
            excludeFromTotal: excludeFromTotal,
            customName: customName.trimmingCharacters(in: .whitespaces).isEmpty ? nil : customName.trimmingCharacters(in: .whitespaces)
        )
        settings.warningThreshold = Double(cleanWarning)
        settings.dangerThreshold = Double(cleanDanger)
        settings.syncDisabled = syncDisabled ? true : nil

        do {
            try await FirestoreService.shared.updateAccountSettings(accountId: account.id, userId: userId, settings: settings)
            dismiss()
        } catch {
            // Error is shown via viewModel error system
        }
    }
}

#Preview {
    AccountSettingsEditView(account: MockData.bankAccount, viewModel: .preview)
}
