import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// System document picker (same approach as Feather): opens a temporary COPY of the file, so no
/// security scope is needed, and only files with the allowed extensions are selectable.
struct DocumentPicker: UIViewControllerRepresentable {
    let allowedContentTypes: [UTType]
    let onPick: ([URL]) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick, onCancel: onCancel)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: allowedContentTypes, asCopy: true)
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        picker.shouldShowFileExtensions = true
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: ([URL]) -> Void
        let onCancel: () -> Void

        init(onPick: @escaping ([URL]) -> Void, onCancel: @escaping () -> Void) {
            self.onPick = onPick
            self.onCancel = onCancel
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            onPick(urls)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onCancel()
        }
    }
}

extension ImportKind {
    /// Only these extensions are selectable in the picker.
    var contentTypes: [UTType] {
        var types: [UTType] = []
        if let t = UTType(filenameExtension: rawValue, conformingTo: .data) { types.append(t) }
        if self == .certificate { types.append(.pkcs12) }
        return types.isEmpty ? [.data] : types
    }
}

/// One picker presentation per screen: set `picking` to a kind to open it.
struct ImportPickerModifier: ViewModifier {
    @Binding var picking: ImportKind?
    @EnvironmentObject var store: ImportStore
    @EnvironmentObject var log: AppLog
    @EnvironmentObject var toaster: Toaster

    func body(content: Content) -> some View {
        content.sheet(item: $picking) { kind in
            DocumentPicker(allowedContentTypes: kind.contentTypes,
                           onPick: { urls in
                               picking = nil
                               handle(urls, kind: kind)
                           },
                           onCancel: { picking = nil })
                .ignoresSafeArea()
        }
    }

    private func handle(_ urls: [URL], kind: ImportKind) {
        // The temp copy lives in tmp/ until the system cleans it; copying right away on the main actor is safe.
        Task { @MainActor in
            guard let url = urls.first else {
                let msg = "No se recibió ningún archivo."
                log.add("Importar: \(msg)")
                toaster.show(msg, isError: true)
                Haptics.error()
                return
            }
            do {
                let name = try store.importFile(from: url, kind: kind)
                toaster.show("\(kind.importedLabel): \(name)")
                Haptics.light()
            } catch {
                let msg = error.localizedDescription
                log.add("Importar \(url.lastPathComponent): \(msg)")
                toaster.show(msg, isError: true)
                Haptics.error()
            }
        }
    }
}

extension View {
    func importPicker(_ picking: Binding<ImportKind?>) -> some View {
        modifier(ImportPickerModifier(picking: picking))
    }
}
