import SwiftUI

struct EnableBankingSettingsView: View {
    @AppStorage(Constants.UserDefaultsKeys.ebAppId) private var ebAppId = ""
    @AppStorage(Constants.UserDefaultsKeys.ebAppSecret) private var ebAppSecret = ""
    @State private var showTestResult: String? = nil
    @State private var isTesting = false
    @ObservedObject var viewModel: DashboardViewModel

    var body: some View {
        Form {
            // MARK: - Cos'è Enable Banking
            Section {
                HStack(spacing: 14) {
                    Image(systemName: "building.columns.fill")
                        .font(.largeTitle)
                        .foregroundStyle(Color.appPrimary)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Open Banking via Enable Banking")
                            .font(.headline)
                        Text("Connetti i tuoi conti bancari europei in modo sicuro e privato. Le chiamate API avvengono direttamente dal dispositivo — nessun server intermedio.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 6)
            }

            // MARK: - Guida registrazione
            Section("Come registrarsi") {
                stepRow("1", "Vai su enablebanking.com/register e crea un account gratuito.")
                stepRow("2", "Nell'area riservata, crea una nuova applicazione.")
                stepRow("3", "Scarica l'App ID e genera la coppia di chiavi RSA.")
                stepRow("4", "Copia l'App ID e la chiave privata RSA (PEM) qui sotto.")
                Link(destination: URL(string: "https://enablebanking.com/docs/")!) {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.up.right.square")
                            .foregroundStyle(Color.appPrimary)
                        Text("Apri la documentazione Enable Banking")
                            .font(.subheadline)
                    }
                }
                Link(destination: URL(string: "https://enablebanking.com/register")!) {
                    HStack(spacing: 8) {
                        Image(systemName: "person.badge.plus")
                            .foregroundStyle(Color.appPrimary)
                        Text("Registrati su enablebanking.com")
                            .font(.subheadline)
                    }
                }
            }

            // MARK: - Credenziali
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text("App ID")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("App ID", text: $ebAppId)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                        .font(.system(.subheadline, design: .monospaced))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Chiave privata RSA (PEM)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    SecureField("-----BEGIN PRIVATE KEY-----", text: $ebAppSecret)
                        .font(.system(.subheadline, design: .monospaced))
                }
            } header: {
                Text("Credenziali API")
            } footer: {
                Text("Le credenziali sono salvate localmente nel Portachiavi del dispositivo e non vengono trasmesse ai server di SpendWise.")
                    .font(.caption2)
            }

            // MARK: - Test connessione
            if !ebAppId.isEmpty && !ebAppSecret.isEmpty {
                Section {
                    Button {
                        Task { await testConnection() }
                    } label: {
                        HStack {
                            Spacer()
                            if isTesting {
                                ProgressView().padding(.trailing, 4)
                                Text("Verifica in corso…")
                            } else {
                                Label("Verifica connessione", systemImage: "checkmark.shield")
                                    .font(.subheadline.bold())
                            }
                            Spacer()
                        }
                    }
                    .disabled(isTesting)

                    if let result = showTestResult {
                        Text(result)
                            .font(.caption)
                            .foregroundStyle(result.hasPrefix("✅") ? Color.income : Color.expense)
                    }
                }
            }

            // MARK: - Privacy
            Section("Privacy") {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "lock.shield")
                        .foregroundStyle(.green)
                        .frame(width: 20)
                    Text("SpendWise non memorizza le tue credenziali bancarie. Tutti i dati rimangono sul dispositivo o nel tuo account Firebase personale.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Open Banking")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    // MARK: - Helpers
    @ViewBuilder
    private func stepRow(_ num: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(num)
                .font(.caption2.bold())
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(Color.appPrimary, in: Circle())
            Text(text)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 2)
    }

    private func testConnection() async {
        isTesting = true
        defer { isTesting = false }
        do {
            let _ = try await EnableBankingService.shared.getInstitutions(country: "IT")
            showTestResult = "✅ Connessione riuscita!"
        } catch {
            showTestResult = "❌ Errore: \(error.localizedDescription)"
        }
    }
}

#Preview {
    NavigationStack {
        EnableBankingSettingsView(viewModel: .preview)
    }
}
