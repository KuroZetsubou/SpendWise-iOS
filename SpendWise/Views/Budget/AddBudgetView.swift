import SwiftUI

struct AddBudgetView: View {
    @ObservedObject var viewModel: DashboardViewModel
    var existing: Budget? = nil
    @Environment(\.dismiss) private var dismiss

    @State private var selectedCategory = ""
    @State private var limitString = ""
    @State private var isActive = true
    @State private var isLoading = false
    @State private var errorMessage: String?

    private var isEditing: Bool { existing != nil }

    private var expenseCategories: [AppCategory] {
        viewModel.categories.filter { $0.type == .expense && $0.parentId == nil }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Categoria") {
                    Picker("Categoria", selection: $selectedCategory) {
                        ForEach(expenseCategories) { cat in
                            HStack {
                                CategoryIconView(categoryName: cat.name, size: 20, showBackground: false)
                                Text(cat.name)
                            }
                            .tag(cat.name)
                        }
                    }
                }

                Section("Budget mensile") {
                    HStack {
                        Text("€")
                        TextField("Limite mensile", text: $limitString)
                            #if os(iOS)
                            .keyboardType(.decimalPad)
                            #endif
                    }
                }

                Section("Opzioni") {
                    Toggle("Attivo", isOn: $isActive)
                }

                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle(isEditing ? "Modifica Budget" : "Nuovo Budget")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "Salva" : "Aggiungi") {
                        Task { await save() }
                    }
                    .disabled(isLoading || selectedCategory.isEmpty || limitString.isEmpty)
                    .bold()
                }
            }
            .onAppear { populate() }
        }
    }

    private func populate() {
        if let e = existing {
            selectedCategory = e.category
            limitString = String(format: "%.2f", e.monthlyLimit).replacingOccurrences(of: ".", with: ",")
            isActive = e.isActive
        } else {
            selectedCategory = expenseCategories.first?.name ?? ""
        }
    }

    private func save() async {
        let clean = limitString.replacingOccurrences(of: ",", with: ".")
        guard let limit = Double(clean), limit > 0 else { errorMessage = "Importo non valido."; return }
        guard !selectedCategory.isEmpty else { errorMessage = "Seleziona una categoria."; return }
        guard let uid = viewModel.userId else { errorMessage = "Non autenticato."; return }

        isLoading = true
        defer { isLoading = false }

        let budget = Budget(id: existing?.id, userId: uid, category: selectedCategory, monthlyLimit: limit, isActive: isActive)
        if let id = existing?.id {
            await viewModel.updateBudget(id: id, updates: ["category": selectedCategory, "monthlyLimit": limit, "isActive": isActive])
        } else {
            await viewModel.addBudget(budget)
        }
        dismiss()
    }
}

#Preview("Nuovo budget") {
    AddBudgetView(viewModel: .preview)
}
