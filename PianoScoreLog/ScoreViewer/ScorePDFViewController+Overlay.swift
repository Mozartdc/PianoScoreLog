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
            let horizontalPadding: CGFloat = 8
            let verticalPadding: CGFloat = 6
            let width = max(minSide, ceil(contentSize.width) + horizontalPadding)
            let height = max(minSide, ceil(contentSize.height) + verticalPadding)
            label.frame = CGRect(origin: .zero, size: CGSize(width: width, height: height))
            if selectedStickerID == sticker.id {
                label.layer.borderColor = UIColor.systemBlue.withAlphaComponent(0.45).cgColor
                label.layer.borderWidth = 1
                label.layer.cornerRadius = 6
                label.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.08)

                let pan = UIPanGestureRecognizer(target: self, action: #selector(handleStickerPan(_:)))
                pan.cancelsTouchesInView = false
                label.addGestureRecognizer(pan)

                let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handleStickerPinch(_:)))
                pinch.cancelsTouchesInView = false
                label.addGestureRecognizer(pinch)
            }

            let x = CGFloat(sticker.normalizedX) * bounds.width
            let y = CGFloat(sticker.normalizedY) * bounds.height
            label.center = CGPoint(x: x, y: y)
            overlay.stickerContainerView.addSubview(label)
            if selectedStickerID == sticker.id {
                let deleteButton = ScorePDFStickerDeleteButton(stickerID: sticker.id)
                deleteButton.setImage(UIImage(systemName: "xmark"), for: .normal)
                deleteButton.tintColor = .white
                deleteButton.backgroundColor = UIColor.systemRed.withAlphaComponent(0.95)
                deleteButton.layer.cornerRadius = 9
                deleteButton.frame = CGRect(x: label.frame.maxX, y: label.frame.minY - 18, width: 18, height: 18)
                deleteButton.imageView?.contentMode = .scaleAspectFit
                deleteButton.addTarget(self, action: #selector(handleStickerDeleteButtonTap(_:)), for: .touchUpInside)
                overlay.stickerContainerView.addSubview(deleteButton)
            }
        }
    }

    func refreshOverlayView(_ overlay: ScorePDFLayeredPageOverlayView, pageIndex: Int) {
        guard let activeLayerID else {
            overlay.canvasView.drawing = PKDrawing()
            overlay.passiveImageView.image = nil
            rebuildStickerViews(for: pageIndex, overlay: overlay)
            overlay.canvasView.isUserInteractionEnabled = false
            overlay.canvasView.drawingGestureRecognizer.isEnabled = false
            overlay.stickerContainerView.isUserInteractionEnabled = false
            return
        }
        let activeLayerVisible = annotationLayers.first(where: { $0.id == activeLayerID })?.isVisible ?? false
        overlay.canvasView.delegate = self
        overlay.canvasView.drawing = activeLayerVisible ? drawing(for: pageIndex, layerID: activeLayerID) : PKDrawing()
        rebuildPassiveImage(for: pageIndex, overlay: overlay)
        rebuildStickerViews(for: pageIndex, overlay: overlay)
        applyCurrentTool(to: overlay.canvasView)
        let canDrawNow = isEditorMode && isDrawingEnabled && currentToolMode != .sticker
        let canPlaceSticker = isEditorMode && isDrawingEnabled && currentToolMode == .sticker
        overlay.canvasView.isUserInteractionEnabled = canDrawNow
        overlay.canvasView.drawingGestureRecognizer.isEnabled = canDrawNow
        overlay.stickerContainerView.isUserInteractionEnabled = canPlaceSticker
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
