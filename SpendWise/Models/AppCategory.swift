import Foundation
import FirebaseFirestore

struct AppCategory: Codable, Hashable {
    @DocumentID var firestoreId: String?
    var userId: String
    var name: String
    var type: CategoryType
    var parentId: String?
    var color: String?
    var icon: String?

    // Non-persisted: used only for default (in-memory) categories, not saved to Firestore
    var localId: String?

    enum CategoryType: String, Codable, CaseIterable {
        case income
        case expense
    }

    // firestoreId is handled by @DocumentID — exclude from normal CodingKeys
    // localId is in-memory only — also excluded
    enum CodingKeys: String, CodingKey {
        case userId, name, type, parentId, color, icon
    }

    init(userId: String, name: String, type: CategoryType,
         parentId: String? = nil, color: String? = nil, icon: String? = nil) {
        self.userId = userId
        self.name = name
        self.type = type
        self.parentId = parentId
        self.color = color
        self.icon = icon
    }

    var isSystem: Bool { userId == "system" }
    var displayColor: String { color ?? AppCategory.categoryColors[name] ?? "#6B7280" }
    var displayIcon: String { icon ?? AppCategory.categoryIcons[name] ?? "tag" }

    /// Stable non-optional identifier: Firestore doc ID > localId > composite fallback
    var effectiveId: String { firestoreId ?? localId ?? "\(userId)_\(name)_\(type.rawValue)" }
}

// MARK: - Identifiable
extension AppCategory: Identifiable {
    var id: String { effectiveId }
}

extension AppCategory {
    static func makeDefaults() -> [AppCategory] {
        var cats: [AppCategory] = []
        let defaults: [(String, String, [String])] = [
            ("Cibo & Bevande", "expense", ["Supermercato", "Ristoranti", "Bar", "Glovo/Deliveroo"]),
            ("Casa", "expense", ["Affitto/Mutuo", "Bollette", "Manutenzione", "Mobili/Arredo"]),
            ("Shopping", "expense", ["Abbigliamento", "Elettronica", "Regali", "Altro Shopping"]),
            ("Trasporti", "expense", ["Carburante", "Mezzi Pubblici", "Auto/Parcheggi", "Viaggi"]),
            ("Oneri finanziari", "expense", ["Commissioni", "Assicurazioni", "Imposte", "Interessi"]),
            ("Salute", "expense", ["Farmacia", "Visite Mediche", "Dentista"]),
            ("Entrate", "income", ["Stipendio", "Premi", "Rimborsi", "Vendite"]),
            ("Investimenti", "income", ["Dividendi", "Cedole", "Plusvalenze"]),
            ("Investimenti", "expense", ["Acquisto titoli", "PAC"]),
            ("Altro", "expense", []),
            ("Giroconto", "expense", [])
        ]
        for (name, typeStr, subs) in defaults {
            guard let type = CategoryType(rawValue: typeStr) else { continue }
            let parentId = "default_\(name.lowercased().replacingOccurrences(of: " ", with: "_"))_\(typeStr)"
            var parent = AppCategory(userId: "system", name: name, type: type)
            parent.localId = parentId
            cats.append(parent)
            for sub in subs {
                var child = AppCategory(userId: "system", name: sub, type: type)
                child.parentId = parentId
                cats.append(child)
            }
        }
        return cats
    }
}

// MARK: - Category Icons
extension AppCategory {
    static let categoryIcons: [String: String] = [
        "Cibo & Bevande": "fork.knife",
        "Supermercato": "cart",
        "Ristoranti": "fork.knife.circle",
        "Bar": "cup.and.saucer",
        "Glovo/Deliveroo": "bag",
        "Casa": "house",
        "Affitto/Mutuo": "house.fill",
        "Bollette": "bolt",
        "Manutenzione": "wrench.and.screwdriver",
        "Mobili/Arredo": "sofa",
        "Shopping": "bag.fill",
        "Abbigliamento": "tshirt",
        "Elettronica": "iphone",
        "Regali": "gift",
        "Altro Shopping": "bag.badge.plus",
        "Trasporti": "car",
        "Carburante": "fuelpump",
        "Mezzi Pubblici": "tram",
        "Auto/Parcheggi": "car.fill",
        "Viaggi": "airplane",
        "Oneri finanziari": "banknote",
        "Commissioni": "percent",
        "Assicurazioni": "shield",
        "Imposte": "doc.text",
        "Interessi": "arrow.up.right",
        "Salute": "cross.circle",
        "Farmacia": "pills",
        "Visite Mediche": "stethoscope",
        "Dentista": "mouth",
        "Entrate": "arrow.down.circle.fill",
        "Stipendio": "briefcase.fill",
        "Premi": "star.fill",
        "Rimborsi": "arrow.uturn.left",
        "Vendite": "tag.fill",
        "Investimenti": "chart.line.uptrend.xyaxis",
        "Dividendi": "dollarsign.circle",
        "Cedole": "doc.badge.plus",
        "Plusvalenze": "arrow.up",
        "Acquisto titoli": "chart.bar",
        "PAC": "clock.arrow.2.circlepath",
        "Giroconto": "arrow.left.arrow.right",
        "Altro": "ellipsis.circle"
    ]

    static let categoryColors: [String: String] = [
        "Cibo & Bevande": "#F97316",
        "Casa": "#3B82F6",
        "Shopping": "#8B5CF6",
        "Trasporti": "#14B8A6",
        "Oneri finanziari": "#EF4444",
        "Salute": "#EC4899",
        "Entrate": "#22C55E",
        "Investimenti": "#F59E0B",
        "Giroconto": "#6B7280",
        "Altro": "#9CA3AF"
    ]
}
