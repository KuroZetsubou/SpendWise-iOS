import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: DashboardViewModel
    @EnvironmentObject var authViewModel: AuthViewModel

    @AppStorage(Constants.UserDefaultsKeys.ebAppId) private var ebAppId = ""
    @AppStorage(Constants.UserDefaultsKeys.ebAppSecret) private var ebAppSecret = ""

    @State private var showResetConfirm = false
    @State private var showDeleteImportedConfirm = false
    @State private var showCategoryManager = false
    @State private var isResetting = false
    @State private var alertMessage: String?
    @State private var showAlert = false

    var body: some View {
        NavigationStack {
            Form {
                profileSection
                aiSettingsSection
                bankAPISection
                categoriesSection
                dataManagementSection
                aboutSection
            }
            .navigationTitle("Impostazioni")
            .sheet(isPresented: $showCategoryManager) {
                CategoryManagerView(viewModel: viewModel)
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
        }
    }

    // MARK: - Sections

    private var profileSection: some View {
        Section("Profilo") {
            HStack(spacing: 12) {
                if let photoURL = authViewModel.userPhotoURL {
                    AsyncImage(url: photoURL) { img in
                        img.resizable().scaledToFill()
                    } placeholder: {
                        Image(systemName: "person.circle.fill")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: 50, height: 50)
                    .clipShape(Circle())
                } else {
                    Image(systemName: authViewModel.isAnonymous ? "person.fill.questionmark" : "person.circle.fill")
                        .font(.system(size: 50))
                        .foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(authViewModel.userDisplayName)
                        .font(.headline)
                    Text(authViewModel.userEmail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)

            // Link Google account banner (only for anonymous users)
            if authViewModel.isAnonymous {
                Button {
                    Task { await authViewModel.linkWithGoogle() }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "link.circle.fill")
                            .foregroundStyle(Color.appPrimary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Collega account Google")
                                .font(.subheadline.bold())
                            Text("Sincronizza i dati su tutti i dispositivi")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .foregroundStyle(.primary)
            }

            Button(role: .destructive) {
                authViewModel.signOut()
            } label: {
                Label(
                    authViewModel.isAnonymous ? "Esci (i dati locali andranno persi)" : "Logout",
                    systemImage: "rectangle.portrait.and.arrow.right"
                )
            }
        }
    }

    private var aiSettingsSection: some View {
        Section("Intelligenza Artificiale") {
            HStack(spacing: 12) {
                Image(systemName: "brain.head.profile")
                    .font(.title2)
                    .foregroundStyle(Color.appPrimary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Apple Intelligence")
                        .font(.subheadline.bold())
                    if #available(iOS 26.0, macOS 26.0, *) {
                        Label("Disponibile su questo dispositivo", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    } else {
                        Text("Richiede iOS 26+ con Apple Intelligence abilitato")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.vertical, 4)

            if #unavailable(iOS 26.0, macOS 26.0) {
                Link(destination: URL(string: "https://support.apple.com/apple-intelligence")!) {
                    Label("Scopri Apple Intelligence", systemImage: "arrow.up.right.square")
                        .font(.caption)
                }
            }
        }
    }

    private var bankAPISection: some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                Text("App ID (Enable Banking)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("App ID", text: $ebAppId)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Private Key RSA (PEM)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                SecureField("-----BEGIN PRIVATE KEY-----", text: $ebAppSecret)
            }
            Link(destination: URL(string: "https://enablebanking.com/docs/")!) {
                Label("Documentazione Enable Banking", systemImage: "arrow.up.right.square")
                    .font(.caption)
            }
        } header: {
            Text("Open Banking")
        } footer: {
            Text("Le chiamate API avvengono direttamente dal dispositivo verso api.enablebanking.com — nessun server intermedio richiesto.")
                .font(.caption2)
        }
    }

    private var categoriesSection: some View {
        Section("Categorie") {
            Button {
                showCategoryManager = true
            } label: {
                Label("Gestisci categorie", systemImage: "tag")
            }
        }
    }

    private var dataManagementSection: some View {
        Section("Gestione Dati") {
            Button {
                showDeleteImportedConfirm = true
            } label: {
                Label("Elimina transazioni importate", systemImage: "arrow.down.circle.badge.xmark")
                    .foregroundStyle(.orange)
            }

            Button(role: .destructive) {
                showResetConfirm = true
            } label: {
                Label("Reset completo dati", systemImage: "trash")
            }
            .disabled(isResetting)
        }
    }

    private var aboutSection: some View {
        Section("Info") {
            HStack {
                Text("Versione")
                Spacer()
                Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0")
                    .foregroundStyle(.secondary)
            }
            HStack {
                Text("SpendWise")
                    .foregroundStyle(.secondary)
                Spacer()
                Text("Gestione finanze personali")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Actions

    private func performReset() async {
        isResetting = true
        do {
            await viewModel.resetAllData()
        }
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

// MARK: - Category Manager
struct CategoryManagerView: View {
    @ObservedObject var viewModel: DashboardViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showAddCategory = false
    @State private var newCategoryName = ""
    @State private var newCategoryType: AppCategory.CategoryType = .expense
    @State private var newParentId: String? = nil

    var body: some View {
        NavigationStack {
            List {
                ForEach(AppCategory.CategoryType.allCases, id: \.self) { type in
                    Section(type == .income ? "Entrate" : "Uscite") {
                        let parents = viewModel.allCategories(ofType: type)
                        ForEach(parents) { parent in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    CategoryIconView(categoryName: parent.name, size: 28)
                                    Text(parent.name)
                                        .font(.subheadline.bold())
                                    Spacer()
                                    if !parent.isSystem {
                                        Button {
                                            if let id = parent.firestoreId {
                                                Task { await viewModel.deleteCategory(id: id) }
                                            }
                                        } label: {
                                            Image(systemName: "minus.circle.fill")
                                                .foregroundStyle(.red)
                                        }
                                    }
                                }

                        let subs = viewModel.subCategories(ofParent: parent.effectiveId)
                                if !subs.isEmpty {
                                    ForEach(subs) { sub in
                                        HStack {
                                            Text("  ·  \(sub.name)")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                            Spacer()
                                            if !sub.isSystem {
                                                Button {
                                                    if let id = sub.firestoreId {
                                                        Task { await viewModel.deleteCategory(id: id) }
                                                    }
                                                } label: {
                                                    Image(systemName: "minus.circle.fill")
                                                        .foregroundStyle(.red)
                                                        .font(.caption)
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Categorie")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Chiudi") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { showAddCategory = true } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showAddCategory) {
                addCategorySheet
            }
        }
    }

    private var addCategorySheet: some View {
        NavigationStack {
            Form {
                Section("Tipo") {
                    Picker("Tipo", selection: $newCategoryType) {
                        Text("Entrata").tag(AppCategory.CategoryType.income)
                        Text("Uscita").tag(AppCategory.CategoryType.expense)
                    }
                    .pickerStyle(.segmented)
                }
                Section("Nome") {
                    TextField("Nome categoria", text: $newCategoryName)
                }
                Section("Categoria padre (opzionale)") {
                    Picker("Padre", selection: $newParentId) {
                        Text("Nessuna (categoria principale)").tag(String?.none)
                        ForEach(viewModel.allCategories(ofType: newCategoryType)) { cat in
                                            Text(cat.name).tag(cat.firestoreId as String?)
                                        }
                    }
                }
            }
            .navigationTitle("Nuova Categoria")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") { showAddCategory = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Aggiungi") {
                        Task { await saveNewCategory() }
                        showAddCategory = false
                    }
                    .disabled(newCategoryName.trimmingCharacters(in: .whitespaces).isEmpty)
                    .bold()
                }
            }
        }
    }

    private func saveNewCategory() async {
        guard let userId = viewModel.userId,
              !newCategoryName.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        let category = AppCategory(
            userId: userId,
            name: newCategoryName.trimmingCharacters(in: .whitespaces),
            type: newCategoryType,
            parentId: newParentId
        )
        await viewModel.addCategory(category)
        newCategoryName = ""
        newParentId = nil
    }
}
