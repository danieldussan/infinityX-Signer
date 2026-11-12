import Foundation

public enum QueueOutcome: Equatable {
    case pending, completed, failed, cancelled
}

/// "3 instaladas, 1 fallida, 1 cancelada" (zero counts omitted).
public func queueSummary(_ outcomes: [QueueOutcome]) -> String {
    func part(_ n: Int, _ word: String) -> String? {
        n == 0 ? nil : "\(n) \(word)\(n == 1 ? "" : "s")"
    }
    let parts = [
        part(outcomes.filter { $0 == .completed }.count, "instalada"),
        part(outcomes.filter { $0 == .failed }.count, "fallida"),
        part(outcomes.filter { $0 == .cancelled }.count, "cancelada"),
    ]
    return parts.compactMap { $0 }.joined(separator: ", ")
}
