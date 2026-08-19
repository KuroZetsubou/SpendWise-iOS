import SwiftUI

struct CategoryManagerView: View {
    @ObservedObject var viewModel: DashboardViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var selectedType: AppCategory.CategoryType = .expense
    @State private var isImporting = false
    @State private var importedCount: Int? = nil
    @State private var showImportConfirm = false
    @State private var showAddCategory = false
    @State private var categoryToDelete: AppCategory?
    @State private var showDeleteConfirm = false

    private var userCategories: [AppCategory] {
        viewModel.categories
            .filter { $0.userId != "system" && $0.type == selectedType && $0.parentId == nil }
            .sorted { $0.name < $1.name }
    }

    private var systemCategories: [AppCategory] {
        viewModel.categories
            .filter { $0.userId == "system" && $0.type == selectedType && $0.parentId == nil }
            .sorted { $0.name < $1.name }
    }

    private var importableCount: Int {
        let defaults = AppCategory.makeDefaults().filter { $0.parentId == nil }
        let existingKeys = Set(viewModel.categories
            .filter { $0.userId != "system" }
            .map { "\($0.name)|\($0.type.rawValue)" })
        return defaults.filter { !existingKeys.contains("\($0.name)|\($0.type.rawValue)") }.count
    }

    var body: some View {
        NavigationStack {
            List {
                // Import banner
                if importableCount > 0 {
                    Section {
                        HStack(spacing: 12) {
                            Image(systemName: "square.and.arrow.down.on.square")
                                .font(.title2)
                                .foregroundStyle(Color.appPrimary)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Importa categorie predefinite")
                                    .font(.subheadline.bold())
                                Text("\(importableCount) categorie non ancora importate")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if isImporting {
                                ProgressView().scaleEffect(0.8)
                            } else {
                                Button("Importa") { showImportConfirm = true }
                                    .buttonStyle(.borderedProminent)
                                    .controlSize(.small)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                } else {
                    Section {
                        Label("Tutte le categorie predefinite sono già importate", systemImage: "checkmark.seal.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                // Type picker
                Section {
                    Picker("Tipo", selection: $selectedType) {
                        Text("Uscite").tag(AppCategory.CategoryType.expense)
                        Text("Entrate").tag(AppCategory.CategoryType.income)
                    }
                    .pickerStyle(.segmented)
                }

                // User-owned categories
                if !userCategories.isEmpty {
                    Section("Le mie categorie") {
                        ForEach(userCategories) { cat in
                            CategoryRowView(
                                category: cat,
                                children: viewModel.categories.filter { $0.parentId == cat.firestoreId },
                                onDelete: { categoryToDelete = cat; showDeleteConfirm = true }
                            )
                        }
                    }
                }

                // System categories (read-only)
                if !systemCategories.isEmpty {
                    Section("Categorie di sistema (sola lettura)") {
                        ForEach(systemCategories) { cat in
                            CategoryRowView(
                                category: cat,
                                children: viewModel.categories.filter { $0.parentId == cat.firestoreId },
                                onDelete: nil
                            )
                        }
                    }
                }

                if userCategories.isEmpty && systemCategories.isEmpty {
                    Section {
                        ContentUnavailableView(
                            "Nessuna categoria",
                            systemImage: "tag.slash",
                            description: Text("Importa le predefinite o aggiungine una nuova.")
                        )
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(DS.Colors.bgApp)
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
                AddCategoryView(viewModel: viewModel, defaultType: selectedType)
            }
            .confirmationDialog(
                "Importare \(importableCount) categorie predefinite?",
                isPresented: $showImportConfirm,
                titleVisibility: .visible
            ) {
                Button("Importa") {
                    Task {
                        isImporting = true
                        importedCount = await viewModel.importDefaultCategories()
                        isImporting = false
                    }
                }
                Button("Annulla", role: .cancel) {}
            } message: {
                Text("Verranno aggiunte le categorie mancanti. Quelle già presenti non saranno duplicate.")
            }
            .confirmationDialog(
                "Eliminare \"\(categoryToDelete?.name ?? "")\"?",
                isPresented: $showDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button("Elimina", role: .destructive) {
                    if let id = categoryToDelete?.firestoreId {
                        Task { await viewModel.deleteCategory(id: id) }
                    }
                }
                Button("Annulla", role: .cancel) {}
            } message: {
                Text("Anche le sotto-categorie collegate saranno eliminate.")
            }
            .overlay {
                if let count = importedCount {
                    importedBanner(count: count)
                }
            }
        }
    }

    private func importedBanner(count: Int) -> some View {
        VStack {
            Spacer()
            HStack(spacing: 10) {
                Image(systemName: count > 0 ? "checkmark.circle.fill" : "info.circle.fill")
                    .foregroundStyle(count > 0 ? Color.income : .secondary)
                Text(count > 0 ? "\(count) categorie importate con successo" : "Nessuna nuova categoria da importare")
                    .font(.subheadline.bold())
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(.thinMaterial, in: Capsule())
            .padding(.bottom, 32)
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                withAnimation { importedCount = nil }
            }
        }
    }
}

// MARK: - Category Row

struct CategoryRowView: View {
    let category: AppCategory
    let children: [AppCategory]
    let onDelete: (() -> Void)?

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                CategoryIconView(categoryName: category.name, size: 32, showBackground: true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(category.name).font(.subheadline)
                    if !children.isEmpty {
                        Text("\(children.count) sotto-categorie")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if category.userId == "system" {
                    Text("sistema")
                        .font(.caption2)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(.secondary.opacity(0.15))
                        .foregroundStyle(.secondary)
                        .clipShape(Capsule())
                }
                if !children.isEmpty {
                    Button { withAnimation { isExpanded.toggle() } } label: {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)
            .swipeActions(edge: .trailing) {
                if let onDelete, category.userId != "system" {
                    Button(role: .destructive, action: onDelete) {
                        Label("Elimina", systemImage: "trash")
                    }
                }
            }

            if isExpanded && !children.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(children.sorted { $0.name < $1.name }) { child in
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.turn.down.right")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            CategoryIconView(categoryName: child.name, size: 24, showBackground: false)
                            Text(child.name).font(.caption)
                            Spacer()
                        }
                        .padding(.leading, 42)
                        .padding(.vertical, 3)
                    }
                }
                .padding(.bottom, 4)
            }
        }
    }
}

// MARK: - Add Category

struct AddCategoryView: View {
    @ObservedObject var viewModel: DashboardViewModel
    var defaultType: AppCategory.CategoryType

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var selectedType: AppCategory.CategoryType = .expense
    @State private var selectedParentId: String = ""
    @State private var isLoading = false

    private var parentOptions: [AppCategory] {
        viewModel.categories.filter { $0.type == selectedType && $0.parentId == nil && $0.userId != "system" }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Nome") {
                    TextField("Nome categoria", text: $name)
                }
                Section("Tipo") {
                    Picker("Tipo", selection: $selectedType) {
                        Text("Uscita").tag(AppCategory.CategoryType.expense)
                        Text("Entrata").tag(AppCategory.CategoryType.income)
                    }
                    .pickerStyle(.segmented)
                }
                Section("Sotto-categoria di (opzionale)") {
                    Picker("Categoria padre", selection: $selectedParentId) {
                        Text("Nessuna (categoria principale)").tag("")
                        ForEach(parentOptions) { cat in
                            Text(cat.name).tag(cat.firestoreId ?? "")
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(DS.Colors.bgApp)
            .navigationTitle("Nuova Categoria")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Aggiungi") { Task { await save() } }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isLoading)
                        .bold()
                }
            }
            .onAppear { selectedType = defaultType }
        }
    }

    private func save() async {
        guard let userId = viewModel.userId else { return }
        isLoading = true
        let cat = AppCategory(
            userId: userId,
            name: name.trimmingCharacters(in: .whitespaces),
            type: selectedType,
            parentId: selectedParentId.isEmpty ? nil : selectedParentId
        )
        await viewModel.addCategory(cat)
        dismiss()
    }
}

#Preview {
    CategoryManagerView(viewModel: .preview)
}
