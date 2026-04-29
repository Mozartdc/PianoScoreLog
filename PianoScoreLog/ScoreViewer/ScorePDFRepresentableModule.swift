import SwiftUI

#if os(iOS)
import UIKit

struct ScorePDFView: UIViewControllerRepresentable {
    let pieceID: UUID
    let pdfURL: URL
    @Binding var pageIndex: Int
    @Binding var pageCount: Int
    let isEditorMode: Bool
    let isViewerInteractionEnabled: Bool
    let isDrawingEnabled: Bool
    let annotationLayers: [AnnotationLayer]
    let activeLayerID: UUID?
    let selectedTool: DrawingToolMode
    let selectedColor: Color
    let strokeWidth: CGFloat
    let strokeOpacity: CGFloat
    let eraserMode: EraserMode
    let eraserSize: CGFloat
    let selectedStickerSymbolID: String?
    let stickerColor: Color
    let stickerScale: CGFloat
    let stickerOpacity: CGFloat
    let deleteStickerTrigger: Int
    let imageManagementTrigger: Int
    let photoImportMenuTrigger: Int
    let galleryImportTrigger: Int
    let fileImportTrigger: Int
    let isRulerActive: Bool
    let undoTrigger: Int
    let redoTrigger: Int
    let prevPageTrigger: Int
    let nextPageTrigger: Int
    let jumpToPageTrigger: Int
    let jumpToPageTarget: Int
    let pageTurnKeyboardProvider: KeyboardPageTurnInputProvider?
    let onCanvasTap: () -> Void
    let onStickerSelectionChanged: (Bool) -> Void
    let onLayerConfigurationChanged: ([AnnotationLayer], UUID?) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIViewController(context: Context) -> ScorePDFViewController {
        let controller = ScorePDFViewController()
        context.coordinator.bind(controller: controller)
        controller.keyboardProvider = pageTurnKeyboardProvider
        controller.onSingleTap = onCanvasTap
        controller.setEditorMode(isEditorMode)
        controller.setViewerInteractionEnabled(isViewerInteractionEnabled)
        controller.setDrawingEnabled(isDrawingEnabled)
        controller.setDrawingTool(
            selectedTool,
            color: UIColor(selectedColor),
            width: strokeWidth,
            opacity: strokeOpacity,
            eraserMode: eraserMode,
            eraserSize: eraserSize
        )
        controller.setStickerToolState(
            symbolID: selectedStickerSymbolID,
            color: UIColor(stickerColor),
            scale: stickerScale,
            opacity: stickerOpacity
        )
        controller.applyStickerDelete(trigger: deleteStickerTrigger)
        controller.applyImageManagementTrigger(imageManagementTrigger)
        controller.applyPhotoImportMenuTrigger(photoImportMenuTrigger)
        controller.applyGalleryImportTrigger(galleryImportTrigger)
        controller.applyFileImportTrigger(fileImportTrigger)
        controller.applyUndoRedo(undoTrigger: undoTrigger, redoTrigger: redoTrigger)
        controller.applyPageMove(prevTrigger: prevPageTrigger, nextTrigger: nextPageTrigger)
        controller.applyPageJump(trigger: jumpToPageTrigger, target: jumpToPageTarget)
        controller.setRulerActive(isRulerActive)
        return controller
    }

    func updateUIViewController(_ uiViewController: ScorePDFViewController, context: Context) {
        uiViewController.configure(with: pdfURL, pieceID: pieceID, startPageIndex: pageIndex)
        uiViewController.setEditorMode(isEditorMode)
        uiViewController.setViewerInteractionEnabled(isViewerInteractionEnabled)
        uiViewController.setDrawingEnabled(isDrawingEnabled)
        if context.coordinator.shouldApplyLayerConfiguration(for: pieceID) {
            uiViewController.setLayerConfiguration(annotationLayers, activeLayerID: activeLayerID)
        }
        uiViewController.setDrawingTool(
            selectedTool,
            color: UIColor(selectedColor),
            width: strokeWidth,
            opacity: strokeOpacity,
            eraserMode: eraserMode,
            eraserSize: eraserSize
        )
        uiViewController.setStickerToolState(
            symbolID: selectedStickerSymbolID,
            color: UIColor(stickerColor),
            scale: stickerScale,
            opacity: stickerOpacity
        )
        uiViewController.applyStickerDelete(trigger: deleteStickerTrigger)
        uiViewController.applyImageManagementTrigger(imageManagementTrigger)
        uiViewController.applyPhotoImportMenuTrigger(photoImportMenuTrigger)
        uiViewController.applyGalleryImportTrigger(galleryImportTrigger)
        uiViewController.applyFileImportTrigger(fileImportTrigger)
        uiViewController.applyUndoRedo(undoTrigger: undoTrigger, redoTrigger: redoTrigger)
        uiViewController.applyPageMove(prevTrigger: prevPageTrigger, nextTrigger: nextPageTrigger)
        uiViewController.applyPageJump(trigger: jumpToPageTrigger, target: jumpToPageTarget)
        uiViewController.setRulerActive(isRulerActive)
    }

    static func dismantleUIViewController(_ uiViewController: ScorePDFViewController, coordinator: Coordinator) {
        uiViewController.persistCurrentPageDrawing()
    }

    final class Coordinator {
        private var parent: ScorePDFView
        private var lastPieceID: UUID?

        init(_ parent: ScorePDFView) {
            self.parent = parent
        }

        func bind(controller: ScorePDFViewController) {
            controller.onPageChanged = { [weak self] current, total in
                self?.parent.pageIndex = current
                self?.parent.pageCount = total
            }
            controller.onLayerConfigurationChanged = { [weak self] layers, active in
                self?.parent.onLayerConfigurationChanged(layers, active)
            }
            controller.onStickerSelectionChanged = { [weak self] isSelected in
                self?.parent.onStickerSelectionChanged(isSelected)
            }
        }

        func shouldApplyLayerConfiguration(for pieceID: UUID) -> Bool {
            defer { lastPieceID = pieceID }
            return lastPieceID == pieceID
        }
    }
}
#endif
