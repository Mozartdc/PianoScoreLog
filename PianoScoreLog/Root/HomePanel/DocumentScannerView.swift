import SwiftUI
import VisionKit
import PDFKit

#if os(iOS)

/// VNDocumentCameraViewController wrapper.
/// 스캔 결과를 PDF Data로 변환하여 onCompletion 콜백으로 전달한다.
/// 사용자가 X(취소) 버튼을 누르면 onCancel이 호출된다.
struct DocumentScannerView: UIViewControllerRepresentable {

    /// true이면 이 기기에서 문서 스캔을 지원한다 (카메라 필요).
    static var isSupported: Bool { VNDocumentCameraViewController.isSupported }

    /// 스캔 성공 시 PDF Data를 전달한다.
    let onCompletion: (Result<Data, Error>) -> Void
    /// 사용자가 취소(X 버튼)했을 때 호출된다.
    let onCancel: () -> Void

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let vc = VNDocumentCameraViewController()
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ vc: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    // MARK: - Coordinator

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let parent: DocumentScannerView

        init(_ parent: DocumentScannerView) { self.parent = parent }

        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFinishWith scan: VNDocumentCameraScan
        ) {
            let pdfData = scan.makePDFData()
            parent.onCompletion(.success(pdfData))
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            // X 버튼 → 호출자(ScoreLibrarySection)가 fullScreenCover를 내린다.
            parent.onCancel()
        }

        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFailWithError error: Error
        ) {
            parent.onCompletion(.failure(error))
        }
    }
}

// MARK: - VNDocumentCameraScan → PDF Data

private extension VNDocumentCameraScan {
    func makePDFData() -> Data {
        let pdfDocument = PDFDocument()
        for i in 0..<pageCount {
            let image = imageOfPage(at: i)
            if let page = PDFPage(image: image) {
                pdfDocument.insert(page, at: i)
            }
        }
        return pdfDocument.dataRepresentation() ?? Data()
    }
}

#endif
