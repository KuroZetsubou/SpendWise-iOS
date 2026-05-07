import Foundation
import FirebaseFirestore

struct Budget: Identifiable, Codable {
    @DocumentID var id: String?
    var userId: String
    var category: String
    var monthlyLimit: Double
    var isActive: Bool
    @ServerTimestamp var createdAt: Timestamp?
}
