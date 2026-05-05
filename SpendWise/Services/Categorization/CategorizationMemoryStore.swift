import Foundation
import FirebaseFirestore
import OSLog

private let memLog = Logger(subsystem: "com.kurozetsubou.spendwise", category: "CategorizationMemory")

// MARK: - Models

struct ExactMatchEntry: Codable {
    var category: String
    var confidence: Double
    var isInternalTransfer: Bool
    var needsReview: Bool
    var shortReason: String
    var source: String
    var updatedAt: String
}

struct LearnedPattern: Codable {
    var canonicalText: String
    var category: String
    var createdAt: String
}

struct AccountEntry: Codable {
    var iban: String
    var name: String
}

struct MemoryData: Codable {
    var exactMatches: [String: ExactMatchEntry]
    var learnedPatterns: [LearnedPattern]
    var accountRegistry: [AccountEntry]
    static var empty: MemoryData { .init(exactMatches: [:], learnedPatterns: [], accountRegistry: []) }
}

// MARK: - Memory Store

@MainActor
final class CategorizationMemoryStore {
    private let db = Firestore.firestore(database: "ai-studio-4c91960a-949c-4665-a4a0-0be7bfe458bd")
    private var data: MemoryData = .empty
    private let userId: String

    init(userId: String) { self.userId = userId }

    private var docRef: DocumentReference {
        db.collection("users").document(userId)
            .collection("private").document("transaction_memory")
    }

    func load() async {
        do {
            let snap = try await docRef.getDocument()
            guard snap.exists, let raw = snap.data() else { return }
            let jsonData = try JSONSerialization.data(withJSONObject: raw)
            var loaded = try JSONDecoder().decode(MemoryData.self, from: jsonData)

            // Clean legacy Puter error entries
            let before = loaded.exactMatches.count
            loaded.exactMatches = loaded.exactMatches.filter { _, v in
                !(v.category == "uncategorized" && v.shortReason.contains("Puter"))
            }
            if loaded.exactMatches.count < before {
                memLog.info("🧹 Removed \(before - loaded.exactMatches.count) stale entries")
                try await docRef.setData(try JSONSerialization.jsonObject(
                    with: JSONEncoder().encode(loaded)) as? [String: Any] ?? [:])
            }
            self.data = loaded
            memLog.info("📥 Loaded: \(loaded.exactMatches.count) matches, \(loaded.learnedPatterns.count) patterns")
        } catch { memLog.warning("⚠️ Memory load failed: \(error.localizedDescription)") }
    }

    private func persist() async {
        guard let dict = try? JSONSerialization.jsonObject(
            with: (try? JSONEncoder().encode(data)) ?? Data()) as? [String: Any]
        else { return }
        try? await docRef.setData(dict)
    }

    func findExact(_ fingerprint: String) -> ExactMatchEntry? { data.exactMatches[fingerprint] }

    func saveExact(_ fingerprint: String, entry: ExactMatchEntry) async {
        var e = entry; e.updatedAt = ISO8601DateFormatter().string(from: Date())
        data.exactMatches[fingerprint] = e
        await persist()
    }

    func addLearnedPattern(canonicalText: String, category: String) async {
        data.learnedPatterns.append(LearnedPattern(
            canonicalText: canonicalText, category: category,
            createdAt: ISO8601DateFormatter().string(from: Date())))
        await persist()
    }

    var learnedPatterns: [LearnedPattern] { data.learnedPatterns }
    var accountRegistry: [AccountEntry] { data.accountRegistry }

    func registerAccount(iban: String, name: String) async {
        guard !data.accountRegistry.contains(where: { $0.iban == iban }) else { return }
        data.accountRegistry.append(AccountEntry(iban: iban, name: name))
        await persist()
    }
}
