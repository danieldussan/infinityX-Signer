import SwiftUI
import UIKit

struct ToastMessage: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let isError: Bool
}

/// One visible toast at a time; errors stay longer than successes.
@MainActor
final class Toaster: ObservableObject {
    @Published private(set) var current: ToastMessage?
    private var hideTask: Task<Void, Never>?

    func show(_ text: String, isError: Bool = false) {
        let message = ToastMessage(text: text, isError: isError)
        current = message
        hideTask?.cancel()
        let seconds: Double = isError ? 4.5 : 2.2
        hideTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            if Task.isCancelled { return }
            if self?.current == message { self?.current = nil }
        }
    }

    func dismiss() {
        hideTask?.cancel()
        current = nil
    }
}

@MainActor
enum Haptics {
    static func light() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func error() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }
}

enum Fmt {
    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "es")
        f.dateFormat = "d MMM yyyy"
        return f
    }()

    static func date(_ date: Date) -> String {
        dateFormatter.string(from: date)
    }

    static func size(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
