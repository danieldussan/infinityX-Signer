import Foundation

/// Last errors/messages shown in Diagnostics.
@MainActor
final class AppLog: ObservableObject {
    @Published private(set) var entries: [String] = []

    func add(_ message: String) {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        entries.insert("[\(f.string(from: Date()))] \(message)", at: 0)
        if entries.count > 50 { entries.removeLast(entries.count - 50) }
    }
}
