import Foundation

/// Bridges the external Safari OAuth callback (spendwise://callback?code=xxx)
/// to an async/await continuation in the bank connection flow.
@MainActor
final class AuthCallbackHandler {
    static let shared = AuthCallbackHandler()
    private var continuation: CheckedContinuation<String, Error>?

    private init() {}

    /// Waits for the OAuth callback code. Times out after `timeout` seconds.
    func waitForCode(timeout: TimeInterval = 300) async throws -> String {
        try await withTimeout(seconds: timeout) { [weak self] in
            try await withCheckedThrowingContinuation { cont in
                Task { @MainActor [weak self] in
                    self?.continuation = cont
                }
            }
        }
    }

    /// Called from SpendWiseApp when spendwise://callback?code=xxx is received.
    func receive(url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let code = components.queryItems?.first(where: { $0.name == "code" })?.value
        else {
            continuation?.resume(throwing: EBError.invalidResponse("No code in callback URL"))
            continuation = nil
            return
        }
        continuation?.resume(returning: code)
        continuation = nil
    }

    func cancel() {
        continuation?.resume(throwing: CancellationError())
        continuation = nil
    }
}

// MARK: - Timeout helper

private func withTimeout<T: Sendable>(seconds: TimeInterval, operation: @escaping @Sendable () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw EBError.networkError("Timeout: nessun callback ricevuto dopo \(Int(seconds))s")
        }
        guard let result = try await group.next() else {
            throw EBError.networkError("Task group vuoto")
        }
        group.cancelAll()
        return result
    }
}
