import PDFKit
#if os(iOS)
import PencilKit
import UIKit

final class ScorePDFViewController: UIViewController, PDFPageOverlayViewProvider, PKCanvasViewDelegate, UITextViewDelegate {
    let pdfView = PDFView()
    private var singleTapRecognizer: UITapGestureRecognizer?
    private var pendingConfiguration: ScorePDFPendingConfiguration?
    private var hasInitialLayout = false
    private var lastViewSize: CGSize = .zero

    var currentPieceID: UUID?
    var activePageIndex: Int = 0
    private var currentURL: URL?
    var isEditorMode = false
    var isViewerInteractionEnabled = false
    var isDrawingEnabled = false
    var drawingCache: [ScorePDFDrawingKey: PKDrawing] = [:]

    private var lastUndoTrigger = 0
    private var lastRedoTrigger = 0
    private var lastPrevPageTrigger = 0
    private var lastNextPageTrigger = 0
    private var lastJumpToPageTrigger = 0
    private var isTransitioningPage = false
    var overlayViews: [Int: ScorePDFLayeredPageOverlayView] = [:]
    var currentCanvasView: PKCanvasView?

    var currentToolMode: DrawingToolMode = .pen
    var currentColor: UIColor = .label
    var currentWidth: CGFloat = 4
    var currentOpacity: CGFloat = 1
    var currentEraserMode: EraserMode = .bitmap
    var currentEraserSize: CGFloat = 0.5
    var selectedStickerSymbolID: String?
    var currentStickerColor: UIColor = .label
    var currentStickerScale: CGFloat = 1.0
    var currentStickerOpacity: CGFloat = 1.0
    var hoverGlyphView: UIImageView? = nil
    var hoverGlyphContainer: UIView? = nil
    var hoverDotView: UIView? = nil
    private var lastDeleteStickerTrigger = 0
    var pendingStickerGestureSnapshot: ([StickerPlacement], UUID?)?

    var annotationLayers: [AnnotationLayer] = [AnnotationLayer(name: "레이어 1", isVisible: true)]
    var activeLayerID: UUID? = nil
    var stickerPlacements: [StickerPlacement] = []
    var selectedStickerID: UUID?

    // MARK: - Text tool state
    weak var activeTextEditor: UITextView?
    var activeTextEditorPageIndex: Int?
    var editingAnnotation: PDFAnnotation?

    var onSingleTap: (() -> Void)?
    var onPageChanged: ((Int, Int) -> Void)?
    var onStickerSelectionChanged: ((Bool) -> Void)?
    var onLayerConfigurationChanged: (([AnnotationLayer], UUID?) -> Void)?


    /// PDFKit 내부 UIScrollView를 재귀 탐색한다.
    /// usePageViewController(true) 환경에서는 내부 뷰 계층이 페이지 전환 시
    /// 재구성될 수 있으므로, 캐싱하지 않고 호출 시점에만 탐색한다.
    private func collectScrollViews(in view: UIView) -> [UIScrollView] {
        var result: [UIScrollView] = []
        if let scroll = view as? UIScrollView {
            result.append(scroll)
        }
        for child in view.subviews {
            result.append(contentsOf: collectScrollViews(in: child))
        }
        return result
    }

    /// panning on/off 와 bounces 만 제어한다.
    /// exclusion height 보정은 pdfTopConstraint 로 처리하므로
    /// contentInset / verticalScrollIndicatorInsets 는 여기서 건드리지 않는다.
    private func setPDFPanningEnabled(_ enabled: Bool) {
        let scrollViews = collectScrollViews(in: pdfView)
        for scrollView in scrollViews {
            scrollView.isScrollEnabled = enabled
            scrollView.bounces = enabled
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        pdfView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(pdfView)
        NSLayoutConstraint.activate([
            pdfView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            pdfView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            pdfView.topAnchor.constraint(equalTo: view.topAnchor),
            pdfView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        pdfView.autoScales = true
        pdfView.displayMode = .singlePage
        pdfView.displayDirection = .horizontal
        pdfView.usePageViewController(true, withViewOptions: nil)
        pdfView.displaysPageBreaks = false
        pdfView.pageOverlayViewProvider = self
        pdfView.isInMarkupMode = true
        activeLayerID = annotationLayers.first?.id

        let singleTap = UITapGestureRecognizer(target: self, action: #selector(handleSingleTap))
        singleTap.cancelsTouchesInView = false
        pdfView.addGestureRecognizer(singleTap)
        singleTapRecognizer = singleTap

        let globalTap = UITapGestureRecognizer(target: self, action: #selector(handleGlobalTapForTextCommit(_:)))
        globalTap.cancelsTouchesInView = false
        view.addGestureRecognizer(globalTap)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handlePageChanged),
            name: Notification.Name.PDFViewPageChanged,
            object: pdfView
        )
        if view.gestureRecognizers?.contains(where: { $0 is UIHoverGestureRecognizer }) != true {
            let hover = UIHoverGestureRecognizer(target: self, action: #selector(handleStickerHover(_:)))
            view.addGestureRecognizer(hover)
        }
        applyEditorMode()
        applyPendingConfigurationIfNeeded()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if view.bounds.size != lastViewSize {
            lastViewSize = view.bounds.size
            refreshAllOverlayViews()
        }
        if !hasInitialLayout, view.bounds.width > 0, view.bounds.height > 0 {
            hasInitialLayout = true
            applyPendingConfigurationIfNeeded()
        }
        updateMinimumZoomScaleIfNeeded(forceScaleToFit: false)
        // setPDFPanningEnabled 는 여기서 매 레이아웃 패스마다 호출하지 않는다.
        // 상태 변화(applyEditorMode)가 발생할 때만 호출되도록 applyEditorMode 에서 담당한다.
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func configure(with url: URL, pieceID: UUID, startPageIndex: Int) {
        guard isViewLoaded, hasInitialLayout else {
            pendingConfiguration = ScorePDFPendingConfiguration(url: url, pieceID: pieceID, startPageIndex: startPageIndex)
            return
        }
        guard currentURL != url || currentPieceID != pieceID else { return }
        applyConfiguration(url: url, pieceID: pieceID, startPageIndex: startPageIndex)
    }

    func setLayerConfiguration(_ layers: [AnnotationLayer], activeLayerID: UUID?) {
        let resolved = layers.isEmpty ? [AnnotationLayer(name: "레이어 1", isVisible: true)] : layers
        let resolvedActive: UUID? = {
            if let activeLayerID, resolved.contains(where: { $0.id == activeLayerID }) {
                return activeLayerID
            }
            return resolved.first?.id
        }()

        if annotationLayers == resolved && self.activeLayerID == resolvedActive {
            return
        }

        persistVisibleCanvases()
        annotationLayers = resolved
        self.activeLayerID = resolvedActive
        persistLayerMetadata()
        refreshAllOverlayViews()
    }

    private func applyPendingConfigurationIfNeeded() {
        guard let pending = pendingConfiguration, isViewLoaded, hasInitialLayout else { return }
        pendingConfiguration = nil
        applyConfiguration(url: pending.url, pieceID: pending.pieceID, startPageIndex: pending.startPageIndex)
    }

    private func applyConfiguration(url: URL, pieceID: UUID, startPageIndex: Int) {
        currentURL = url
        currentPieceID = pieceID
        drawingCache.removeAll(keepingCapacity: true)
        currentCanvasView = nil
        overlayViews.removeAll(keepingCapacity: true)
        stickerPlacements = ScoreFileStore.loadStickerPlacements(pieceID: pieceID)
        setSelectedSticker(nil)

        if let stored = ScoreFileStore.loadAnnotationLayersMetadata(pieceID: pieceID), !stored.layers.isEmpty {
            annotationLayers = stored.layers
            if let storedActive = stored.activeLayerID,
               stored.layers.contains(where: { $0.id == storedActive }) {
                activeLayerID = storedActive
            } else {
                activeLayerID = stored.layers.first?.id
            }
        } else {
            annotationLayers = [AnnotationLayer(name: "레이어 1", isVisible: true)]
            activeLayerID = annotationLayers.first?.id
        }
        onLayerConfigurationChanged?(annotationLayers, activeLayerID)
        persistLayerMetadata()

        let document = PDFDocument(url: url)
        pdfView.document = document
        pdfView.autoScales = true
        pdfView.maxScaleFactor = 5.0

        let count = document?.pageCount ?? 0
        let safeStart = max(0, min(startPageIndex, max(0, count - 1)))
        activePageIndex = safeStart
        let capturedStart = safeStart
        let capturedCount = count
        DispatchQueue.main.async { [weak self] in
            self?.onPageChanged?(capturedStart, capturedCount)
        }
        goToPage(index: safeStart)
        updateMinimumZoomScaleIfNeeded(forceScaleToFit: true)
        prefetchDrawingIfNeeded(for: safeStart - 1)
        prefetchDrawingIfNeeded(for: safeStart + 1)
        endPageTransition()
    }

    private func updateMinimumZoomScaleIfNeeded(forceScaleToFit: Bool) {
        guard pdfView.document != nil else { return }
        let fit = pdfView.scaleFactorForSizeToFit
        guard fit.isFinite, fit > 0 else { return }
        pdfView.minScaleFactor = fit

        // Keep the clamp only when truly needed; avoid repeatedly overriding
        // the current zoom during page transition/layout churn.
        if !forceScaleToFit && isTransitioningPage {
            return
        }

        let current = pdfView.scaleFactor
        if !current.isFinite || current < (fit - 0.01) {
            pdfView.scaleFactor = fit
        }
    }

    func goToPage(index: Int) {
        guard let document = pdfView.document else { return }
        guard index >= 0 && index < document.pageCount else { return }
        guard let page = document.page(at: index) else { return }
        if pdfView.currentPage != page {
            beginPageTransition()
        }
        pdfView.go(to: page)
    }

    func setEditorMode(_ enabled: Bool) {
        guard isEditorMode != enabled else { return }
        if isEditorMode, !enabled {
            persistVisibleCanvases()
            persistStickerPlacements()
        }
        isEditorMode = enabled
        applyEditorMode()
    }

    func setDrawingEnabled(_ enabled: Bool) {
        guard isDrawingEnabled != enabled else { return }
        isDrawingEnabled = enabled
        applyEditorMode()
    }

    func setViewerInteractionEnabled(_ enabled: Bool) {
        guard isViewerInteractionEnabled != enabled else { return }
        isViewerInteractionEnabled = enabled
        applyEditorMode()
    }

    // setToolbarExclusionHeight 는 제거됨.
    // 레이아웃 책임은 ScoreViewerScreen(VStack)이 갖고, PDFKit은 남은 영역을 순정으로 사용한다.

    func setDrawingTool(
        _ tool: DrawingToolMode,
        color: UIColor,
        width: CGFloat,
        opacity: CGFloat,
        eraserMode: EraserMode,
        eraserSize: CGFloat
    ) {
        let sameTool = currentToolMode == tool
        let sameColor = currentColor.isEqual(color)
        let sameWidth = abs(currentWidth - width) < 0.0001
        let sameOpacity = abs(currentOpacity - opacity) < 0.0001
        let sameEraserMode = currentEraserMode == eraserMode
        let sameEraserSize = abs(currentEraserSize - eraserSize) < 0.0001
        if sameTool && sameColor && sameWidth && sameOpacity && sameEraserMode && sameEraserSize {
            return
        }

        let wasStickerMode = currentToolMode == .sticker
        currentToolMode = tool
        currentColor = color
        currentWidth = width
        currentOpacity = opacity
        currentEraserMode = eraserMode
        currentEraserSize = eraserSize
        if wasStickerMode && tool != .sticker {
            setSelectedSticker(nil)
            refreshAllOverlayViews()
            return
        }
        for overlay in overlayViews.values {
            applyCurrentTool(to: overlay.canvasView)
        }
        applyEditorMode()
    }

    func setStickerToolState(symbolID: String?, color: UIColor, scale: CGFloat, opacity: CGFloat) {
        let normalizedScale = max(0.2, min(scale, 3.0))
        let normalizedOpacity = max(0.1, min(opacity, 1.0))
        let sameSymbol = selectedStickerSymbolID == symbolID
        let sameColor = currentStickerColor.isEqual(color)
        let sameScale = abs(currentStickerScale - normalizedScale) < 0.0001
        let sameOpacity = abs(currentStickerOpacity - normalizedOpacity) < 0.0001
        if sameSymbol && sameColor && sameScale && sameOpacity {
            return
        }

        selectedStickerSymbolID = symbolID
        currentStickerColor = color
        currentStickerScale = normalizedScale
        currentStickerOpacity = normalizedOpacity
    }

    func applyStickerDelete(trigger: Int) {
        guard trigger != lastDeleteStickerTrigger else { return }
        lastDeleteStickerTrigger = trigger
        deleteSelectedSticker()
    }

    func applyUndoRedo(undoTrigger: Int, redoTrigger: Int) {
        if undoTrigger != lastUndoTrigger {
            lastUndoTrigger = undoTrigger
            if let manager = currentCanvasView?.undoManager, manager.canUndo {
                manager.undo()
            }
        }
        if redoTrigger != lastRedoTrigger {
            lastRedoTrigger = redoTrigger
            if let manager = currentCanvasView?.undoManager, manager.canRedo {
                manager.redo()
            }
        }
    }


    func applyPageMove(prevTrigger: Int, nextTrigger: Int) {
        if prevTrigger != lastPrevPageTrigger {
            lastPrevPageTrigger = prevTrigger
            let target = max(0, activePageIndex - 1)
            guard target != activePageIndex else { return }
            goToPage(index: target)
            activePageIndex = target
        }
        if nextTrigger != lastNextPageTrigger {
            lastNextPageTrigger = nextTrigger
            let maxIndex = max(0, (pdfView.document?.pageCount ?? 1) - 1)
            let target = min(maxIndex, activePageIndex + 1)
            guard target != activePageIndex else { return }
            goToPage(index: target)
            activePageIndex = target
        }
    }

    func applyPageJump(trigger: Int, target: Int) {
        guard trigger != lastJumpToPageTrigger else { return }
        lastJumpToPageTrigger = trigger
        let maxIndex = max(0, (pdfView.document?.pageCount ?? 1) - 1)
        let safe = max(0, min(target, maxIndex))
        goToPage(index: safe)
        activePageIndex = safe
    }

    func persistCurrentPageDrawing() {
        saveDrawing(for: activePageIndex)
        persistStickerPlacements()
    }

    @objc private func handleSingleTap() {
        onSingleTap?()
    }

    @objc private func handlePageChanged() {
        guard let document = pdfView.document else {
            DispatchQueue.main.async { [weak self] in
                self?.onPageChanged?(0, 0)
            }
            endPageTransition()
            return
        }

        let total = document.pageCount
        guard total > 0 else {
            DispatchQueue.main.async { [weak self] in
                self?.onPageChanged?(0, 0)
            }
            endPageTransition()
            return
        }

        let fallbackPage = document.page(at: 0)
        guard let page = pdfView.currentPage ?? fallbackPage else {
            endPageTransition()
            return
        }

        let current = max(0, document.index(for: page))
        activePageIndex = current
        currentCanvasView = overlayViews[current]?.canvasView
        prefetchDrawingIfNeeded(for: current - 1)
        prefetchDrawingIfNeeded(for: current + 1)
        DispatchQueue.main.async { [weak self] in
            self?.onPageChanged?(current, total)
        }
        endPageTransition()
        refreshAllOverlayViews()
    }

    func applyEditorMode() {
        singleTapRecognizer?.isEnabled = !isEditorMode
        // 레이아웃 오프셋 없음. ScoreViewerScreen(VStack)이 PDFView 영역을 결정한다.
        // 여기서는 입력 정책(패닝, 드로잉, 스티커)만 관리한다.
        setPDFPanningEnabled(true)
        for overlay in overlayViews.values {
            // 오버레이는 항상 isUserInteractionEnabled = true.
            // hitTest 패스스루로 손가락 패닝은 PDFKit 에 전달되고,
            // 서브뷰(canvasView, stickerContainerView) 만 모드에 따라 켜고 끈다.
            overlay.isUserInteractionEnabled = true
            let canDrawNow = isEditorMode && isDrawingEnabled
                && currentToolMode != .sticker
                && currentToolMode != .text
            let canInteractOverlay = isEditorMode && isDrawingEnabled
                && (currentToolMode == .sticker || currentToolMode == .text)
            overlay.canvasView.isUserInteractionEnabled = canDrawNow
            overlay.canvasView.drawingGestureRecognizer.isEnabled = canDrawNow
            overlay.stickerContainerView.isUserInteractionEnabled = canInteractOverlay
        }
        if currentToolMode != .sticker {
            hideHoverGlyph()
        }
        if isEditorMode && isDrawingEnabled {
            hideDotCursor()
        }
        if currentToolMode != .text {
            commitTextEditing()
        }
    }

    private func beginPageTransition() {
        if !isTransitioningPage {
            isTransitioningPage = true
            saveDrawing(for: activePageIndex)
        }
    }

    private func endPageTransition() {
        isTransitioningPage = false
    }

    private func saveDrawing(for pageIndex: Int) {
        guard let layerID = activeLayerID else { return }
        let key = ScorePDFDrawingKey(pageIndex: pageIndex, layerID: layerID)
        guard let drawing = overlayViews[pageIndex]?.canvasView.drawing ?? drawingCache[key] else { return }
        persistDrawing(drawing, for: key)
    }

    private func persistVisibleCanvases() {
        guard let layerID = activeLayerID else { return }
        for (pageIndex, overlay) in overlayViews {
            let key = ScorePDFDrawingKey(pageIndex: pageIndex, layerID: layerID)
            persistDrawing(overlay.canvasView.drawing, for: key)
        }
    }

    func persistLayerMetadata() {
        guard let currentPieceID else { return }
        ScoreFileStore.saveAnnotationLayersMetadata(
            layers: annotationLayers,
            activeLayerID: activeLayerID,
            pieceID: currentPieceID
        )
    }

    func persistStickerPlacements() {
        guard let currentPieceID else { return }
        ScoreFileStore.saveStickerPlacements(stickerPlacements, pieceID: currentPieceID)
    }

}
#endif
