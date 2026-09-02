import SwiftUI
import VisionKit

/// The system document camera, for photographing a recipe.
///
/// `VNDocumentCameraViewController` rather than a plain camera on purpose:
/// it finds the edges of the card, corrects the perspective, drops the
/// tablecloth around it, and lets someone shoot both sides of an index card
/// as two pages. All of that lands before Vision reads a single character,
/// and OCR quality is mostly a function of how square and how cropped the
/// image was. A raw camera shot of a recipe held at an angle reads far
/// worse, and no amount of cleverness downstream recovers it.
struct DocumentScanner: UIViewControllerRepresentable {
    var onScan: ([UIImage]) -> Void
    var onCancel: () -> Void = {}

    /// False in the simulator and on the rare device without the camera the
    /// scanner needs. Callers offer the photo library instead.
    static var isAvailable: Bool { VNDocumentCameraViewController.isSupported }

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        private let parent: DocumentScanner
        init(_ parent: DocumentScanner) { self.parent = parent }

        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFinishWith scan: VNDocumentCameraScan
        ) {
            let pages = (0..<scan.pageCount).map { scan.imageOfPage(at: $0) }
            parent.onScan(pages)
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            parent.onCancel()
        }

        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFailWithError error: Error
        ) {
            // A failed scan is a cancelled scan as far as the sheet is
            // concerned — the paste box is still sitting there behind it.
            parent.onCancel()
        }
    }
}
