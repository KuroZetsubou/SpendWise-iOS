import Foundation

struct FinancialInsight: Codable, Identifiable {
    var id = UUID()
    var title: String
    var advice: String
    var impact: ImpactLevel

    enum ImpactLevel: String, Codable {
        case low, medium, high

        var label: String {
            switch self {
            case .low:    return "Basso"
            case .medium: return "Medio"
            case .high:   return "Alto"
            }
        }

        var color: String {
            switch self {
            case .low:    return "#22C55E"
            case .medium: return "#F59E0B"
            case .high:   return "#EF4444"
            }
        }
    }

    enum CodingKeys: String, CodingKey {
        case title, advice, impact
    }
}

struct ReceiptScanResult: Codable {
    var items: [ReceiptItem]
    var total: Double
}
