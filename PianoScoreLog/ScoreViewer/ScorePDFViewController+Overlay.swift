import PDFKit
#if os(iOS)
import PencilKit
import UIKit

extension ScorePDFViewController {
    func prefetchDrawingIfNeeded(for pageIndex: Int) {
        guard pageIndex >= 0 else { return }
        guard let document = pdfView.document, pageIndex < document.pageCount else { return }
        for layer in annotationLayers {
            let key = ScorePDFDrawingKey(pageIndex: pageIndex, layerID: layer.id)
            guard drawingCache[key] == nil else { continue }
            drawingCache[key] = loadDrawingFromStore(key: key)
        }
    }

    private func configureCanvasGestureTouchTypes(_ canvas: PKCanvasView) {
        canvas.drawingPolicy = .pencilOnly
        canvas.isScrollEnabled = false
        canvas.drawingGestureRecognizer.cancelsTouchesInView = false
    }

    private func configureStickerTapGesture(_ overlay: ScorePDFLayeredPageOverlayView) {
        if overlay.stickerContainerView.gestureRecognizers?.contains(where: { $0 is UITapGestureRecognizer }) == true {
            return
        }
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleStickerTap(_:)))
        tap.cancelsTouchesInView = false
        overlay.stickerContainerView.addGestureRecognizer(tap)
    }

    private func loadDrawingFromStore(key: ScorePDFDrawingKey) -> PKDrawing {
        if let cached = drawingCache[key] {
            return cached
        }
        guard let pieceID = currentPieceID else {
            let empty = PKDrawing()
            drawingCache[key] = empty
            return empty
        }
        let data: Data? = {
            if let layered = ScoreFileStore.loadAnnotationData(pieceID: pieceID, layerID: key.layerID, pageIndex: key.pageIndex) {
                return layered
            }
            // Backward compatibility: legacy 단일 레이어 데이터는 첫 레이어에서만 읽음.
            if annotationLayers.first?.id == key.layerID {
                return ScoreFileStore.loadAnnotationData(pieceID: pieceID, pageIndex: key.pageIndex)
            }
            return nil
        }()
        guard let data, let drawing = try? PKDrawing(data: data) else {
            let empty = PKDrawing()
            drawingCache[key] = empty
            return empty
        }
        drawingCache[key] = drawing
        return drawing
    }

    func persistDrawing(_ drawing: PKDrawing, for key: ScorePDFDrawingKey) {
        guard let pieceID = currentPieceID else { return }
        drawingCache[key] = drawing
        if drawing.strokes.isEmpty {
            ScoreFileStore.removeAnnotationData(pieceID: pieceID, layerID: key.layerID, pageIndex: key.pageIndex)
        } else {
            ScoreFileStore.saveAnnotationData(drawing.dataRepresentation(), pieceID: pieceID, layerID: key.layerID, pageIndex: key.pageIndex)
        }
    }

    private func pageIndex(for canvasView: PKCanvasView) -> Int? {
        overlayViews.first { $0.value.canvasView === canvasView }?.key
    }

    func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
        guard let layerID = activeLayerID,
              let pageIndex = pageIndex(for: canvasView) else { return }
        let key = ScorePDFDrawingKey(pageIndex: pageIndex, layerID: layerID)
        persistDrawing(canvasView.drawing, for: key)
    }

    private func drawing(for pageIndex: Int, layerID: UUID) -> PKDrawing {
        let key = ScorePDFDrawingKey(pageIndex: pageIndex, layerID: layerID)
        if let cached = drawingCache[key] {
            return cached
        }
        let loaded = loadDrawingFromStore(key: key)
        drawingCache[key] = loaded
        return loaded
    }

    private func rebuildPassiveImage(for pageIndex: Int, overlay: ScorePDFLayeredPageOverlayView) {
        guard let document = pdfView.document,
              let page = document.page(at: pageIndex),
              let activeLayerID else {
            overlay.passiveImageView.image = nil
            return
        }

        let passiveLayers = annotationLayers.filter { $0.isVisible && $0.id != activeLayerID }
        guard !passiveLayers.isEmpty else {
            overlay.passiveImageView.image = nil
            return
        }

        let rect = page.bounds(for: pdfView.displayBox)
        guard rect.width > 0, rect.height > 0 else {
            overlay.passiveImageView.image = nil
            return
        }

        let renderer = UIGraphicsImageRenderer(size: rect.size)
        let image = renderer.image { _ in
            let scale = overlay.window?.screen.scale ?? overlay.traitCollection.displayScale
            for layer in passiveLayers {
                let drawing = drawing(for: pageIndex, layerID: layer.id)
                let rendered = drawing.image(from: CGRect(origin: .zero, size: rect.size), scale: scale)
                rendered.draw(in: CGRect(origin: .zero, size: rect.size))
            }
        }
        overlay.passiveImageView.image = image
    }

    func rebuildImageViews(for pageIndex: Int, overlay: ScorePDFLayeredPageOverlayView) {
        let container = overlay.imageContainerView
        let bounds = container.bounds
        guard bounds.width > 0, bounds.height > 0 else { return }

        container.subviews.forEach { $0.removeFromSuperview() }

        let visibleLayerIDs = Set(annotationLayers.filter(\.isVisible).map(\.id))
        let images = imagePlacements.filter {
            $0.pageIndex == pageIndex && visibleLayerIDs.contains($0.layerID)
        }

        // Pass 1 — add all image views
        for placement in images {
            let imgView = ScorePDFImageView(imageID: placement.id)
            if let pieceID = currentPieceID {
                imgView.imageView.image = ScoreFileStore.loadImageFile(
                    filename: placement.imageFilename, pieceID: pieceID
                )
            }
            let w = CGFloat(placement.normalizedWidth) * bounds.width
            let h = CGFloat(placement.normalizedHeight) * bounds.height
            let cx = CGFloat(placement.normalizedX) * bounds.width
            let cy = CGFloat(placement.normalizedY) * bounds.height
            imgView.frame = CGRect(x: cx - w / 2, y: cy - h / 2, width: w, height: h)

            if placement.id == selectedImageID {
                imgView.layer.borderColor = UIColor.systemBlue.cgColor
                imgView.layer.borderWidth = 1
                imgView.layer.cornerRadius = 2
                if isEditorMode {
                    let pan = UIPanGestureRecognizer(target: self, action: #selector(handleImagePan(_:)))
                    pan.cancelsTouchesInView = false
                    imgView.addGestureRecognizer(pan)
                }
            }

            if isEditorMode {
                let tap = UITapGestureRecognizer(target: self, action: #selector(handleImageTap(_:)))
                tap.cancelsTouchesInView = false
                imgView.addGestureRecognizer(tap)
            }

            container.addSubview(imgView)
        }

        // Pass 2 — add accessories for selected image, or all images in management mode
        let accessoryTargetIDs: [UUID]
        if isImageManagementMode && selectedImageID == nil {
            // 관리 모드: 현재 페이지의 모든 이미지에 핸들 표시
            accessoryTargetIDs = images.map(\.id)
        } else if let selectedID = selectedImageID {
            accessoryTargetIDs = [selectedID]
        } else {
            accessoryTargetIDs = []
        }

        if isEditorMode && !accessoryTargetIDs.isEmpty {
            let xConfig = UIImage.SymbolConfiguration(pointSize: 6, weight: .bold)
            for targetID in accessoryTargetIDs {
                guard let imgView = container.subviews
                    .compactMap({ $0 as? ScorePDFImageView })
                    .first(where: { $0.imageID == targetID }) else { continue }

                let deleteBtn = ScorePDFImageDeleteButton(imageID: targetID)
                deleteBtn.setImage(UIImage(systemName: "xmark", withConfiguration: xConfig), for: .normal)
                deleteBtn.tintColor = .white
                deleteBtn.backgroundColor = .systemRed
                deleteBtn.layer.cornerRadius = 7
                deleteBtn.clipsToBounds = true
                deleteBtn.frame = CGRect(
                    x: imgView.frame.maxX - 7, y: imgView.frame.minY - 7, width: 14, height: 14
                )
                deleteBtn.addTarget(self, action: #selector(handleImageDeleteButtonTap(_:)), for: .touchUpInside)
                container.addSubview(deleteBtn)

                let resizeHandle = ScorePDFImageResizeHandleView(imageID: targetID)
                resizeHandle.frame = CGRect(
                    x: imgView.frame.maxX - 6, y: imgView.frame.maxY - 6, width: 12, height: 12
                )
                let resizePan = UIPanGestureRecognizer(target: self, action: #selector(handleImageResizeHandlePan(_:)))
                resizePan.cancelsTouchesInView = true
                resizeHandle.addGestureRecognizer(resizePan)
                container.addSubview(resizeHandle)
            }
        }
    }

    func rebuildStickerViews(for pageIndex: Int, overlay: ScorePDFLayeredPageOverlayView) {
        let bounds = overlay.stickerContainerView.bounds
        guard bounds.width > 0, bounds.height > 0 else { return }

        for view in overlay.stickerContainerView.subviews {
            view.removeFromSuperview()
        }

        let visibleLayerIDs = Set(annotationLayers.filter(\.isVisible).map(\.id))
        guard !visibleLayerIDs.isEmpty else { return }

        let stickers = stickerPlacements.filter {
            $0.pageIndex == pageIndex && visibleLayerIDs.contains($0.layerID)
        }

        // Pass 1 — add all glyph labels first
        for sticker in stickers {
            let label = ScorePDFStickerGlyphView(stickerID: sticker.id)
            label.textColor = UIColor(hex: sticker.colorHex) ?? currentStickerColor
            label.alpha = CGFloat(sticker.opacity)
            let scale = CGFloat(sticker.scale)
            let pointSize = stickerSymbolPointSize(symbolID: sticker.symbolID, baseSize: 30) * scale
            if let sfName = stickerSFSymbolName(from: sticker.text),
               let image = UIImage(
                systemName: sfName,
                withConfiguration: UIImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold)
               )?.withTintColor(label.textColor, renderingMode: .alwaysOriginal) {
                let attachment = NSTextAttachment()
                attachment.image = image
                attachment.bounds = CGRect(origin: .zero, size: image.size)
                label.attributedText = NSAttributedString(attachment: attachment)
            } else if sticker.text.hasPrefix("U+"), let bravura = UIFont(name: "Bravura", size: pointSize) {
                if let image = renderedBravuraGlyphImage(value: sticker.text, font: bravura, color: label.textColor) {
                    let attachment = NSTextAttachment()
                    attachment.image = image
                    attachment.bounds = CGRect(origin: .zero, size: image.size)
                    label.attributedText = NSAttributedString(attachment: attachment)
                } else {
                    label.attributedText = nil
                    label.text = stickerDisplayText(from: sticker.text)
                    label.font = bravura
                }
            } else if ["rit", "aTempo", "rall", "DC", "DS", "fine"].contains(sticker.symbolID) {
                label.attributedText = nil
                label.text = stickerDisplayText(from: sticker.text)
                label.font = UIFont.italicSystemFont(ofSize: stickerSymbolPointSize(symbolID: sticker.symbolID, baseSize: 28) * scale)
            } else {
                label.attributedText = nil
                label.text = stickerDisplayText(from: sticker.text)
                label.font = UIFont.systemFont(ofSize: stickerSymbolPointSize(symbolID: sticker.symbolID, baseSize: 28) * scale, weight: .semibold)
            }
            let contentSize: CGSize = {
                if let attributed = label.attributedText, !attributed.string.isEmpty {
                    return attributed.size()
                }
                let textSize = (label.text ?? "").size(withAttributes: [.font: label.font as Any])
                return textSize
            }()
            let minSide: CGFloat = 22
            let width = max(minSide, ceil(contentSize.width) + 8)
            let height = max(minSide, ceil(contentSize.height) + 6)
            label.frame = CGRect(origin: .zero, size: CGSize(width: width, height: height))
            if selectedStickerID == sticker.id {
                label.layer.borderColor = UIColor.systemBlue.cgColor
                label.layer.borderWidth = 0.5
                label.layer.cornerRadius = 0
                label.backgroundColor = .clear
                let pan = UIPanGestureRecognizer(target: self, action: #selector(handleStickerPan(_:)))
                pan.cancelsTouchesInView = false
                label.addGestureRecognizer(pan)
            }
            let x = CGFloat(sticker.normalizedX) * bounds.width
            let y = CGFloat(sticker.normalizedY) * bounds.height
            label.center = CGPoint(x: x, y: y)
            overlay.stickerContainerView.addSubview(label)
        }

        // Pass 2 — add accessories for selected sticker on top of all labels
        if let selectedID = selectedStickerID,
           let label = overlay.stickerContainerView.subviews
               .compactMap({ $0 as? ScorePDFStickerGlyphView })
               .first(where: { $0.stickerID == selectedID }) {

            let deleteButton = ScorePDFStickerDeleteButton(stickerID: selectedID)
            let xConfig = UIImage.SymbolConfiguration(pointSize: 6, weight: .bold)
            deleteButton.setImage(UIImage(systemName: "xmark", withConfiguration: xConfig), for: .normal)
            deleteButton.tintColor = .white
            deleteButton.backgroundColor = .systemRed
            deleteButton.layer.cornerRadius = 7
            deleteButton.clipsToBounds = true
            deleteButton.frame = CGRect(x: label.frame.maxX - 7, y: label.frame.minY - 7, width: 14, height: 14)
            deleteButton.addTarget(self, action: #selector(handleStickerDeleteButtonTap(_:)), for: .touchUpInside)
            overlay.stickerContainerView.addSubview(deleteButton)

            let resizeHandle = ScorePDFStickerResizeHandleView(stickerID: selectedID)
            resizeHandle.frame = CGRect(x: label.frame.maxX - 3, y: label.frame.maxY - 3, width: 6, height: 6)
            let resizePan = UIPanGestureRecognizer(target: self, action: #selector(handleResizeHandlePan(_:)))
            resizePan.cancelsTouchesInView = true
            resizeHandle.addGestureRecognizer(resizePan)
            overlay.stickerContainerView.addSubview(resizeHandle)
        }
    }

    func rebuildTextViews(for pageIndex: Int, overlay: ScorePDFLayeredPageOverlayView) {
        let container = overlay.stickerContainerView
        let bounds = container.bounds
        guard bounds.width > 0, bounds.height > 0 else { return }

        // Remove all text-related accessory views
        container.subviews
            .filter {
                $0 is ScorePDFTextBoxView
                || $0 is ScorePDFTextDeleteButton
                || $0 is ScorePDFTextResizeHandleView
            }
            .forEach { $0.removeFromSuperview() }

        let visibleLayerIDs = Set(annotationLayers.filter(\.isVisible).map(\.id))
        let editingID  = activeTextEditorPlacement?.id
        let selectedID = selectedTextBoxID

        // Pass 1 — add all text box views first
        var selectedText: TextPlacement? = nil
        var selectedBoxFrame: CGRect = .zero

        for text in textPlacements where text.pageIndex == pageIndex && visibleLayerIDs.contains(text.layerID) {
            if text.id == editingID { continue }

            let isSelected = text.id == selectedID
            let boxView = ScorePDFTextBoxView(textID: text.id)
            let boxWidth = text.normalizedWidth * bounds.width

            if !text.rtfData.isEmpty,
               let attributed = try? NSAttributedString(
                   data: text.rtfData,
                   options: [.documentType: NSAttributedString.DocumentType.rtf],
                   documentAttributes: nil
               ) {
                boxView.textView.attributedText = attributed
            }

            let fittingHeight = boxView.textView.sizeThatFits(
                CGSize(width: boxWidth, height: .greatestFiniteMagnitude)
            ).height
            let boxHeight = max(36, fittingHeight)
            boxView.frame = CGRect(
                x: text.normalizedX * bounds.width - boxWidth / 2,
                y: text.normalizedY * bounds.height - boxHeight / 2,
                width: boxWidth,
                height: boxHeight
            )

            if isSelected {
                boxView.layer.borderColor = UIColor.systemBlue.cgColor
                boxView.layer.borderWidth = 0.5
                let pan = UIPanGestureRecognizer(target: self, action: #selector(handleTextBoxPan(_:)))
                pan.cancelsTouchesInView = false
                boxView.addGestureRecognizer(pan)
                selectedText = text
                selectedBoxFrame = boxView.frame
            }

            let tap = UITapGestureRecognizer(target: self, action: #selector(handleTextBoxTap(_:)))
            tap.cancelsTouchesInView = false
            boxView.addGestureRecognizer(tap)

            container.addSubview(boxView)
        }

        // Pass 2 — add accessories for selected box on top of all boxes
        if let text = selectedText {
            addTextSelectionAccessories(for: text, boxFrame: selectedBoxFrame, in: container)
        }
    }

    /// Adds delete button + left/right resize handles for the selected text box.
    private func addTextSelectionAccessories(
        for text: TextPlacement,
        boxFrame: CGRect,
        in container: UIView
    ) {
        // Delete button — top-right
        let btn = ScorePDFTextDeleteButton(textID: text.id)
        let xConfig = UIImage.SymbolConfiguration(pointSize: 6, weight: .bold)
        btn.setImage(UIImage(systemName: "xmark", withConfiguration: xConfig), for: .normal)
        btn.tintColor = .white
        btn.backgroundColor = .systemRed
        btn.layer.cornerRadius = 7
        btn.clipsToBounds = true
        btn.frame = CGRect(x: boxFrame.maxX - 7, y: boxFrame.minY - 7, width: 14, height: 14)
        btn.addTarget(self, action: #selector(handleTextDeleteButtonTap(_:)), for: .touchUpInside)
        container.addSubview(btn)

        // Left resize handle
        let leftHandle = ScorePDFTextResizeHandleView(textID: text.id, side: .left)
        leftHandle.frame = CGRect(x: boxFrame.minX - 6, y: boxFrame.midY - 6, width: 12, height: 12)
        let leftPan = UIPanGestureRecognizer(target: self, action: #selector(handleTextResizeHandlePan(_:)))
        leftPan.cancelsTouchesInView = true
        leftHandle.addGestureRecognizer(leftPan)
        container.addSubview(leftHandle)

        // Right resize handle
        let rightHandle = ScorePDFTextResizeHandleView(textID: text.id, side: .right)
        rightHandle.frame = CGRect(x: boxFrame.maxX - 6, y: boxFrame.midY - 6, width: 12, height: 12)
        let rightPan = UIPanGestureRecognizer(target: self, action: #selector(handleTextResizeHandlePan(_:)))
        rightPan.cancelsTouchesInView = true
        rightHandle.addGestureRecognizer(rightPan)
        container.addSubview(rightHandle)
    }

    func refreshOverlayView(_ overlay: ScorePDFLayeredPageOverlayView, pageIndex: Int) {
        guard let activeLayerID else {
            overlay.canvasView.drawing = PKDrawing()
            overlay.passiveImageView.image = nil
            rebuildImageViews(for: pageIndex, overlay: overlay)
            rebuildStickerViews(for: pageIndex, overlay: overlay)
            overlay.isUserInteractionEnabled = true   // hitTest 패스스루로 실질적 통과
            overlay.canvasView.isUserInteractionEnabled = false
            overlay.canvasView.drawingGestureRecognizer.isEnabled = false
            overlay.stickerContainerView.isUserInteractionEnabled = false
            overlay.imageContainerView.isUserInteractionEnabled = false
            return
        }
        let activeLayerVisible = annotationLayers.first(where: { $0.id == activeLayerID })?.isVisible ?? false
        overlay.canvasView.delegate = self
        overlay.canvasView.drawing = activeLayerVisible ? drawing(for: pageIndex, layerID: activeLayerID) : PKDrawing()
        rebuildPassiveImage(for: pageIndex, overlay: overlay)
        rebuildImageViews(for: pageIndex, overlay: overlay)
        rebuildStickerViews(for: pageIndex, overlay: overlay)
        rebuildTextViews(for: pageIndex, overlay: overlay)
        applyCurrentTool(to: overlay.canvasView)
        // 오버레이는 항상 interactive. hitTest 패스스루가 손가락 패닝을 PDFKit 에 전달한다.
        overlay.isUserInteractionEnabled = true
        let canDrawNow = isEditorMode && isDrawingEnabled
            && currentToolMode != .sticker && currentToolMode != .text
        let canInteractOverlay = isEditorMode && isDrawingEnabled
            && (currentToolMode == .sticker || currentToolMode == .text)
        overlay.canvasView.isUserInteractionEnabled = canDrawNow || isRulerActive
        overlay.canvasView.drawingGestureRecognizer.isEnabled = canDrawNow && !isRulerActive
        overlay.canvasView.isRulerActive = isRulerActive
        let stickerContainerActive = canInteractOverlay
            || (isEditorMode && !canDrawNow && (selectedImageID != nil || isImageManagementMode))
        overlay.stickerContainerView.isUserInteractionEnabled = stickerContainerActive
        overlay.imageContainerView.isUserInteractionEnabled = isEditorMode && !canDrawNow
    }

    func refreshAllOverlayViews() {
        for (pageIndex, overlay) in overlayViews {
            refreshOverlayView(overlay, pageIndex: pageIndex)
        }
        currentCanvasView = overlayViews[activePageIndex]?.canvasView
        applyEditorMode()
    }

    // MARK: - PDFPageOverlayViewProvider
    func pdfView(_ view: PDFView, overlayViewFor page: PDFPage) -> UIView? {
        guard let document = view.document else { return nil }
        let pageIndex = document.index(for: page)
        guard pageIndex >= 0 else { return nil }

        let overlay = ScorePDFLayeredPageOverlayView()
        let canvas = overlay.canvasView
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        configureCanvasGestureTouchTypes(canvas)
        configureStickerTapGesture(overlay)
        refreshOverlayView(overlay, pageIndex: pageIndex)

        overlayViews[pageIndex] = overlay
        if pageIndex == activePageIndex {
            currentCanvasView = canvas
        }
        return overlay
    }

    func pdfView(_ pdfView: PDFView, willDisplayOverlayView overlayView: UIView, for page: PDFPage) {
        guard let overlay = overlayView as? ScorePDFLayeredPageOverlayView,
              let document = pdfView.document else { return }
        let pageIndex = document.index(for: page)
        guard pageIndex >= 0 else { return }

        overlayViews[pageIndex] = overlay
        configureCanvasGestureTouchTypes(overlay.canvasView)
        configureStickerTapGesture(overlay)
        refreshOverlayView(overlay, pageIndex: pageIndex)
        DispatchQueue.main.async { [weak self, weak overlay] in
            guard let self, let overlay else { return }
            self.refreshOverlayView(overlay, pageIndex: pageIndex)
        }
        if pageIndex == activePageIndex {
            currentCanvasView = overlay.canvasView
        }
    }

    func pdfView(_ pdfView: PDFView, willEndDisplayingOverlayView overlayView: UIView, for page: PDFPage) {
        guard let overlay = overlayView as? ScorePDFLayeredPageOverlayView,
              let document = pdfView.document else { return }
        let pageIndex = document.index(for: page)
        guard pageIndex >= 0 else { return }

        if let activeLayerID {
            let key = ScorePDFDrawingKey(pageIndex: pageIndex, layerID: activeLayerID)
            persistDrawing(overlay.canvasView.drawing, for: key)
        }
        if hoverGlyphContainer === overlay.stickerContainerView {
            hideHoverGlyph()
        }
        overlayViews.removeValue(forKey: pageIndex)
        if currentCanvasView === overlay.canvasView {
            currentCanvasView = nil
        }
    }
}
#endif
