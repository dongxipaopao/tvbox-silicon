#if os(iOS)
import SwiftUI
import UniformTypeIdentifiers

/// A document picker that copies the chosen file into the app (import mode). SwiftUI's `fileImporter` opens the
/// file in place and hands the app a security-scoped URL; inside LiveContainer that handoff never completes, so
/// the picker answered with nothing at all and the pick looked dead. Import mode copies the file into the app's
/// own Inbox first, which works inside LiveContainer and on a plain install alike.
struct CopyingDocumentPicker: UIViewControllerRepresentable {
    let types: [UTType]
    let onPick: (URL) -> Void
    let onCancel: () -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        private let parent: CopyingDocumentPicker
        init(_ parent: CopyingDocumentPicker) { self.parent = parent }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            if let url = urls.first { parent.onPick(url) } else { parent.onCancel() }
        }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { parent.onCancel() }
    }
}
#endif
