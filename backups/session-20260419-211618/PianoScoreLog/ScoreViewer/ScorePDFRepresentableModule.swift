import SwiftUI

#if os(iOS)
import UIKit

struct ScorePDFView: UIViewControllerRepresentable {
    let pieceID: UUID
    let pdfURL: URL
    @Binding var pageIndex: Int
    @Binding var pageCount: Int
    let isEditorMode: Bool
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
    let toolbarHeight: CGFloat
    let undoTrigger: Int
    let redoTrigger: Int
    let prevPageTrigger: Int
    let nextPageTrigger: Int
    let onCanvasTap: () -> Void
    let onStickerSelectionChanged: (Bool) -> Void
    let onLayerConfigurationChanged: ([AnnotationLayer], UUID?) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIViewController(context: Context) -> ScorePDFViewController {
        let controller = ScorePDFViewController()
        context.coordinator.bind(controller: controller)
        controller.onSingleTap = onCanvasTap
        controller.setEditorMode(isEditorMode)
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
        controller.setToolbarExclusionHeight(toolbarHeight)
        controller.applyUndoRedo(undoTrigger: undoTrigger, redoTrigger: redoTrigger)
        controller.applyPageMove(prevTrigger: prevPageTrigger, nextTrigger: nextPageTrigger)
        return controller
    }

    func updateUIViewController(_ uiViewController: ScorePDFViewController, context: Context) {
        uiViewController.configure(with: pdfURL, pieceID: pieceID, startPageIndex: pageIndex)
        uiViewController.setEditorMode(isEditorMode)
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
        uiViewController.setToolbarExclusionHeight(toolbarHeight)
        uiViewController.applyUndoRedo(undoTrigger: undoTrigger, redoTrigger: redoTrigger)
        uiViewController.applyPageMove(prevTrigger: prevPageTrigger, nextTrigger: nextPageTrigger)
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
