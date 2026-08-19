import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: DashboardViewModel
    @EnvironmentObject var authViewModel: AuthViewModel
    @Environment(\.dismiss) private var dismiss

    @AppStorage(Constants.UserDefaultsKeys.ebAppId) private var ebAppId = ""
    @AppStorage(Constants.UserDefaultsKeys.ebAppSecret) private var ebAppSecret = ""

    @State private var showResetConfirm = false
    @State private var showDeleteImportedConfirm = false
    @State private var showCategoryManager = false
    @State private var showBilanceImport = false
    @State private var isResetting = false
    @State private var alertMessage: String?
    @State private var showAlert = false
    @State private var showAnonLogoutConfirm = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: DS.Space.sectionGap) {
                    profileHeader

                    VStack(spacing: DS.Space.sectionGap) {
                        if authViewModel.isAnonymous { linkAccountBanner }
                        aiSection
                        bankSection
                        dataSection
                        dangerSection
                        aboutSection
                    }
                    .dsGutter()
                }
                .padding(.bottom, DS.Space.x8)
            }
            .scrollIndicators(.hidden)
            .background(DS.Colors.bgApp)
            .ignoresSafeArea(edges: .top)
            .sheet(isPresented: $showCategoryManager) {
                CategoryManagerView(viewModel: viewModel)
            }
            .sheet(isPresented: $showBilanceImport) {
                BilanceImportView(viewModel: viewModel)
            }
            .alert("Errore", isPresented: $showAlert) {
                Button("OK") {}
            } message: {
                Text(alertMessage ?? "")
            }
            .confirmationDialog(
                "Sei sicuro di voler eliminare tutti i dati?",
                isPresented: $showResetConfirm,
                titleVisibility: .visible
            ) {
                Button("Reset completo", role: .destructive) {
                    Task { await performReset() }
                }
                Button("Annulla", role: .cancel) {}
            } message: {
                Text("Questa operazione eliminerà tutte le transazioni, i conti bancari e le sessioni. Non può essere annullata.")
            }
            .confirmationDialog(
                "Eliminare le transazioni importate?",
                isPresented: $showDeleteImportedConfirm,
                titleVisibility: .visible
            ) {
                Button("Elimina", role: .destructive) {
                    Task { await deleteImportedTransactions() }
                }
                Button("Annulla", role: .cancel) {}
            }
            .confirmationDialog(
                "Sei sicuro di voler uscire?",
                isPresented: $showAnonLogoutConfirm,
                titleVisibility: .visible
            ) {
                Button("Esci e cancella dati", role: .destructive) {
                    authViewModel.signOut()
                }
                Button("Annulla", role: .cancel) {}
            } message: {
                Text("Stai usando un account anonimo. Uscendo, tutti i tuoi dati (transazioni, conti, abbonamenti) verranno eliminati definitivamente e non potranno essere recuperati.\n\nPrima di uscire, considera di collegare un account Google per salvare i dati.")
            }
        }
    }

    // MARK: - Profile header
    //
    // Navy panel bleeding to the edges, avatar and identity centred under the app bar.

    private var profileHeader: some View {
        VStack(spacing: DS.Space.x4) {
            HStack {
                DSIconButton("xmark", tone: .onDark, size: 40) { dismiss() }
                Spacer()
                Text("Impostazioni").dsText(DS.Font.h3, color: DS.Colors.textOnDark)
                Spacer()
                Color.clear.frame(width: 40, height: 40)
            }

            avatar

            VStack(spacing: 2) {
                Text(authViewModel.userDisplayName)
                    .dsText(DS.Font.h3, color: DS.Colors.textOnDark)
                Text(authViewModel.userEmail)
                    .dsText(DS.Font.meta, color: DS.Colors.textOnDarkMuted)
            }

            if authViewModel.isAnonymous {
                DSBadge("Account anonimo", icon: "person.fill.questionmark", tone: .onDark)
            }
        }
        .padding(.horizontal, DS.Space.gutter)
        .padding(.top, DS.Space.x16)
        .padding(.bottom, DS.Space.x6)
        .frame(maxWidth: .infinity)
        .background(DS.Gradients.hero)
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: 0, bottomLeadingRadius: DS.Radius.xl2,
                bottomTrailingRadius: DS.Radius.xl2, topTrailingRadius: 0,
                style: .continuous
            )
        )
    }

    @ViewBuilder
    private var avatar: some View {
        if let photoURL = authViewModel.userPhotoURL {
            AsyncImage(url: photoURL) { img in
                img.resizable().scaledToFill()
            } placeholder: {
                Circle().fill(DS.Colors.scrimOnDark)
            }
            .frame(width: 72, height: 72)
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(DS.Colors.scrimOnDark, lineWidth: 2))
        } else {
            Image(systemName: authViewModel.isAnonymous ? "person.fill.questionmark" : "person.fill")
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(DS.Colors.textOnDark)
                .frame(width: 72, height: 72)
                .background(DS.Colors.scrimOnDark)
                .clipShape(Circle())
        }
    }

    // MARK: - Sections

    private var linkAccountBanner: some View {
        DSPromoBanner(
            title: "Collega il Tuo Account",
            message: "Collega un account Google per sincronizzare i dati su tutti i dispositivi e non perderli.",
            icon: "link",
            actionTitle: "Collega Google",
            action: { Task { await authViewModel.linkWithGoogle() } }
        )
    }

    private var aiSection: some View {
        VStack(alignment: .leading, spacing: DS.Space.x3) {
            DSSectionHeader("Intelligenza Artificiale")
            DSCard(.card, padding: DS.Space.cardPad) {
                DSListRow(
                    icon: "brain.head.profile",
                    label: "Apple Intelligence",
                    sublabel: appleIntelligenceStatus,
                    showChevron: false
                ) {
                    if #available(iOS 26.0, macOS 26.0, *) {
                        DSBadge("Attiva", icon: "checkmark", tone: .success)
                    } else {
                        DSBadge("Non disponibile", tone: .neutral)
                    }
                }
            }
        }
    }

    private var appleIntelligenceStatus: String {
        if #available(iOS 26.0, macOS 26.0, *) {
            return "Disponibile su questo dispositivo"
        }
        return "Richiede iOS 26+ con Apple Intelligence"
    }

    private var bankSection: some View {
        VStack(alignment: .leading, spacing: DS.Space.x3) {
            DSSectionHeader("Open Banking")
            DSCard(.card, padding: DS.Space.cardPad) {
                VStack(spacing: 0) {
                    NavigationLink {
                        EnableBankingSettingsView(viewModel: viewModel)
                    } label: {
                        DSListRow(
                            icon: "building.columns.fill",
                            label: "Connessione bancaria",
                            sublabel: ebAppId.isEmpty
                                ? "Non configurato"
                                : "App ID: \(ebAppId.prefix(8))…"
                        )
                    }
                    .buttonStyle(DSPressStyle())
                }
            }
        }
    }

    private var dataSection: some View {
        VStack(alignment: .leading, spacing: DS.Space.x3) {
            DSSectionHeader("Dati")
            DSCard(.card, padding: DS.Space.cardPad) {
                VStack(spacing: 0) {
                    DSListRow(icon: "tag", label: "Gestisci categorie") {
                        showCategoryManager = true
                    }
                    DSListRow(icon: "arrow.down.doc",
                              label: "Importa da Bilance",
                              sublabel: "Importa transazioni via CSV") {
                        showBilanceImport = true
                    }
                }
            }
        }
    }

    private var dangerSection: some View {
        VStack(alignment: .leading, spacing: DS.Space.x3) {
            DSSectionHeader("Gestione Dati")
            DSCard(.card, padding: DS.Space.cardPad) {
                VStack(spacing: 0) {
                    DSListRow(icon: "arrow.down.circle.badge.xmark",
                              iconTint: DS.Palette.amber500,
                              iconBackground: DS.Palette.amber500.opacity(0.12),
                              label: "Elimina transazioni importate") {
                        showDeleteImportedConfirm = true
                    }
                    DSListRow(icon: "trash",
                              iconTint: DS.Colors.expense,
                              iconBackground: DS.Palette.red50,
                              label: "Reset completo dati") {
                        showResetConfirm = true
                    }
                    .disabled(isResetting)
                }
            }

            DSButton(authViewModel.isAnonymous ? "Esci e Cancella Dati" : "Logout",
                     icon: "rectangle.portrait.and.arrow.right",
                     variant: .secondary,
                     size: .large,
                     block: true) {
                if authViewModel.isAnonymous {
                    showAnonLogoutConfirm = true
                } else {
                    authViewModel.signOut()
                }
            }
            .padding(.top, DS.Space.x1)
        }
    }

    private var aboutSection: some View {
        VStack(spacing: DS.Space.x1) {
            Text("SpendWise")
                .dsText(DS.Font.labelBold, color: DS.Colors.textSecondary)
            Text("Versione \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0") • Gestione finanze personali")
                .dsText(DS.Font.meta, color: DS.Colors.textMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, DS.Space.x4)
    }

    // MARK: - Actions

    private func performReset() async {
        isResetting = true
        await viewModel.resetAllData()
        isResetting = false
    }

    private func deleteImportedTransactions() async {
        guard let userId = viewModel.userId else { return }
        do {
            try await FirestoreService.shared.deleteImportedTransactions(userId: userId)
        } catch {
            alertMessage = "Errore: \(error.localizedDescription)"
            showAlert = true
        }
    }
}

#Preview {
    SettingsView(viewModel: .preview)
        .environmentObject(AuthViewModel())
}
