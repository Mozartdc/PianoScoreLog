import PDFKit

#if os(iOS)
import PencilKit
import UIKit

extension ScorePDFViewController {
    func stickerUndoManager() -> UndoManager? {
        currentCanvasView?.undoManager ?? undoManager
    }

    func setSelectedSticker(_ stickerID: UUID?) {
        guard selectedStickerID != stickerID else { return }
        selectedStickerID = stickerID
        onStickerSelectionChanged?(stickerID != nil)
    }

    func applyStickerState(
        _ newPlacements: [StickerPlacement],
        selectedStickerID newSelectedID: UUID?,
        actionName: String,
        undoManager manager: UndoManager?,
        registeringOppositeWith oppositePlacements: [StickerPlacement],
        oppositeSelectedStickerID: UUID?
    ) {
        manager?.registerUndo(withTarget: self) { target in
            target.applyStickerState(
                oppositePlacements,
                selectedStickerID: oppositeSelectedStickerID,
                actionName: actionName,
                undoManager: manager,
                registeringOppositeWith: newPlacements,
                oppositeSelectedStickerID: newSelectedID
            )
        }
        manager?.setActionName(actionName)
        stickerPlacements = newPlacements
        setSelectedSticker(newSelectedID)
        persistStickerPlacements()
        refreshAllOverlayViews()
    }

    func commitStickerStateChange(
        from oldPlacements: [StickerPlacement],
        oldSelectedStickerID: UUID?,
        actionName: String
    ) {
        let newPlacements = stickerPlacements
        let newSelectedID = selectedStickerID
        guard oldPlacements != newPlacements || oldSelectedStickerID != newSelectedID else { return }
        let manager = stickerUndoManager()
        manager?.registerUndo(withTarget: self) { target in
            target.applyStickerState(
                oldPlacements,
                selectedStickerID: oldSelectedStickerID,
                actionName: actionName,
                undoManager: manager,
                registeringOppositeWith: newPlacements,
                oppositeSelectedStickerID: newSelectedID
            )
        }
        manager?.setActionName(actionName)
        persistStickerPlacements()
        refreshAllOverlayViews()
    }

    func deleteSelectedSticker() {
        guard let selectedStickerID,
              stickerPlacements.contains(where: { $0.id == selectedStickerID }) else { return }
        let oldPlacements = stickerPlacements
        let oldSelected = self.selectedStickerID
        stickerPlacements.removeAll { $0.id == selectedStickerID }
        setSelectedSticker(nil)
        commitStickerStateChange(
            from: oldPlacements,
            oldSelectedStickerID: oldSelected,
            actionName: "Delete Sticker"
        )
    }

    @objc func handleStickerTap(_ recognizer: UITapGestureRecognizer) {
        if currentToolMode == .text {
            handleTextTap(recognizer)
            return
        }

        // 이미지가 선택됐거나 관리 모드 상태에서 빈 공간 탭하면 선택/모드 해제
        if selectedImageID != nil || isImageManagementMode {
            selectedImageID = nil
            isImageManagementMode = false
            refreshAllOverlayViews()
            return
        }

        guard currentToolMode == .sticker else { return }
        guard isEditorMode && isDrawingEnabled else { return }
        guard let container = recognizer.view else { return }
        let location = recognizer.location(in: container)
        guard container.bounds.width > 0, container.bounds.height > 0 else { return }
        if container.hitTest(location, with: nil) is UIControl { return }

        if let hitSticker = container.subviews
            .reversed()
            .compactMap({ $0 as? ScorePDFStickerGlyphView })
            .first(where: { $0.frame.insetBy(dx: -8, dy: -8).contains(location) }) {
            setSelectedSticker(hitSticker.stickerID)
            hideHoverGlyph()
            refreshAllOverlayViews()
            return
        }

        let pageIndex = overlayViews.first(where: { $0.value.stickerContainerView === container })?.key ?? activePageIndex
        let visibleLayerIDs = Set(annotationLayers.filter(\.isVisible).map(\.id))

        if let selectedID = selectedStickerID {
            let selectedOnCurrentPage = stickerPlacements.contains {
                $0.id == selectedID && $0.pageIndex == pageIndex && visibleLayerIDs.contains($0.layerID)
            }
            if selectedOnCurrentPage {
                setSelectedSticker(nil)
                hideHoverGlyph()
                refreshAllOverlayViews()
                return
            }
            setSelectedSticker(nil)
        }

        guard let symbolID = selectedStickerSymbolID,
              let symbol = ScoreEditorState.stickerSymbols.first(where: { $0.id == symbolID }),
              let layerID = (activeLayerID ?? annotationLayers.first(where: { $0.isVisible })?.id ?? annotationLayers.first?.id)
        else { return }
        if activeLayerID == nil {
            activeLayerID = layerID
            onLayerConfigurationChanged?(annotationLayers, activeLayerID)
            persistLayerMetadata()
        }

        let normalizedX = min(max(location.x / container.bounds.width, 0), 1)
        let normalizedY = min(max(location.y / container.bounds.height, 0), 1)
        let placement = StickerPlacement(
            symbolID: symbolID,
            text: symbol.value,
            pageIndex: pageIndex,
            layerID: layerID,
            normalizedX: Double(normalizedX),
            normalizedY: Double(normalizedY),
            scale: Double(currentStickerScale),
            colorHex: currentStickerColor.hexString,
            opacity: Double(currentStickerOpacity)
        )
        let oldPlacements = stickerPlacements
        let oldSelected = selectedStickerID
        stickerPlacements.append(placement)
        setSelectedSticker(placement.id)
        commitStickerStateChange(
            from: oldPlacements,
            oldSelectedStickerID: oldSelected,
            actionName: "Add Sticker"
        )
    }

    @objc func handleStickerHover(_ recognizer: UIHoverGestureRecognizer) {
        guard let rootView = recognizer.view else { return }

        switch recognizer.state {
        case .began, .changed:
            let locationInRoot = recognizer.location(in: rootView)

            if isEditorMode && isDrawingEnabled && currentToolMode == .sticker {
                hideDotCursor()
                guard let overlay = overlayViews[activePageIndex] else {
                    hideHoverGlyph()
                    return
                }
                let container = overlay.stickerContainerView
                let locationInContainer = rootView.convert(locationInRoot, to: container)
                guard container.bounds.contains(locationInContainer) else {
                    hideHoverGlyph()
                    return
                }
                guard selectedStickerID == nil else {
                    hideHoverGlyph()
                    return
                }
                showHoverGlyph(at: locationInContainer, in: container)

            } else if isEditorMode && isDrawingEnabled {
                hideHoverGlyph()
                hideDotCursor()

            } else {
                hideHoverGlyph()
                hideDotCursor()
            }
        case .ended, .cancelled:
            hideHoverGlyph()
            hideDotCursor()
        default:
            break
        }
    }

    func showHoverGlyph(at location: CGPoint, in container: UIView) {
        guard let symbolID = selectedStickerSymbolID,
              let symbol = ScoreEditorState.stickerSymbols.first(where: { $0.id == symbolID }) else {
            hideHoverGlyph()
            return
        }

        if hoverGlyphContainer !== container {
            hoverGlyphView?.removeFromSuperview()
            hoverGlyphView = nil
            hoverGlyphContainer = nil
        }

        if hoverGlyphView == nil {
            let imageView = UIImageView()
            imageView.contentMode = .center
            imageView.alpha = 0.4
            imageView.isUserInteractionEnabled = false
            container.addSubview(imageView)
            container.bringSubviewToFront(imageView)
            hoverGlyphView = imageView
            hoverGlyphContainer = container
        }

        let pointSize = stickerSymbolPointSize(symbolID: symbolID, baseSize: 30) * currentStickerScale
        let image: UIImage?
        if let sfName = stickerSFSymbolName(from: symbol.value) {
            image = UIImage(
                systemName: sfName,
                withConfiguration: UIImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold)
            )?.withTintColor(currentStickerColor, renderingMode: .alwaysOriginal)
        } else if symbol.value.hasPrefix("U+"),
                  let bravura = UIFont(name: "Bravura", size: pointSize) {
            image = renderedBravuraGlyphImage(value: symbol.value, font: bravura, color: currentStickerColor)
        } else {
            hideHoverGlyph()
            return
        }

        guard let image else {
            hideHoverGlyph()
            return
        }

        hoverGlyphView?.image = image
        hoverGlyphView?.frame = CGRect(
            origin: CGPoint(x: location.x - image.size.width / 2, y: location.y - image.size.height / 2),
            size: image.size
        )
    }

    func hideHoverGlyph() {
        hoverGlyphView?.removeFromSuperview()
        hoverGlyphView = nil
        hoverGlyphContainer = nil
    }

    func showDotCursor(at location: CGPoint) {
        if hoverDotView == nil {
            let dot = UIView(frame: CGRect(x: 0, y: 0, width: 10, height: 10))
            dot.layer.cornerRadius = 5
            dot.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.5)
            dot.isUserInteractionEnabled = false
            view.addSubview(dot)
            hoverDotView = dot
        }
        hoverDotView?.center = location
    }

    func hideDotCursor() {
        hoverDotView?.removeFromSuperview()
        hoverDotView = nil
    }

    @objc func handleStickerPan(_ recognizer: UIPanGestureRecognizer) {
        guard currentToolMode == .sticker else { return }
        guard isEditorMode && isDrawingEnabled else { return }
        guard let label = recognizer.view as? ScorePDFStickerGlyphView,
              let container = label.superview else { return }
        let stickerID = label.stickerID
        guard let idx = stickerPlacements.firstIndex(where: { $0.id == stickerID }) else { return }
        let pageIndex = stickerPlacements[idx].pageIndex
        guard container.bounds.width > 0, container.bounds.height > 0 else { return }

        let shouldFinalizeGesture: Bool
        switch recognizer.state {
        case .began:
            setSelectedSticker(stickerID)
            hideHoverGlyph()
            pendingStickerGestureSnapshot = (stickerPlacements, selectedStickerID)
            shouldFinalizeGesture = false
        case .changed:
            shouldFinalizeGesture = false
        case .ended, .cancelled:
            shouldFinalizeGesture = true
        default:
            return
        }

        let translation = recognizer.translation(in: container)
        recognizer.setTranslation(.zero, in: container)
        let dx = Double(translation.x / container.bounds.width)
        let dy = Double(translation.y / container.bounds.height)
        stickerPlacements[idx].normalizedX = min(max(stickerPlacements[idx].normalizedX + dx, 0), 1)
        stickerPlacements[idx].normalizedY = min(max(stickerPlacements[idx].normalizedY + dy, 0), 1)
        label.center = CGPoint(
            x: CGFloat(stickerPlacements[idx].normalizedX) * container.bounds.width,
            y: CGFloat(stickerPlacements[idx].normalizedY) * container.bounds.height
        )
        if let deleteButton = container.subviews.compactMap({ $0 as? ScorePDFStickerDeleteButton }).first(where: { $0.stickerID == stickerID }) {
            deleteButton.frame = CGRect(x: label.frame.maxX - 7, y: label.frame.minY - 7, width: 14, height: 14)
        }
        if let resizeHandle = container.subviews.compactMap({ $0 as? ScorePDFStickerResizeHandleView }).first(where: { $0.stickerID == stickerID }) {
            resizeHandle.frame = CGRect(x: label.frame.maxX - 3, y: label.frame.maxY - 3, width: 6, height: 6)
        }
        if shouldFinalizeGesture,
           let snapshot = pendingStickerGestureSnapshot {
            commitStickerStateChange(
                from: snapshot.0,
                oldSelectedStickerID: snapshot.1,
                actionName: "Move Sticker"
            )
            if let overlay = overlayViews[pageIndex] {
                rebuildStickerViews(for: pageIndex, overlay: overlay)
            }
            pendingStickerGestureSnapshot = nil
        }
    }

    @objc func handleResizeHandlePan(_ recognizer: UIPanGestureRecognizer) {
        guard currentToolMode == .sticker else { return }
        guard isEditorMode && isDrawingEnabled else { return }
        guard let handle = recognizer.view as? ScorePDFStickerResizeHandleView,
              let container = handle.superview else { return }
        let stickerID = handle.stickerID
        guard let idx = stickerPlacements.firstIndex(where: { $0.id == stickerID }) else { return }
        let pageIndex = stickerPlacements[idx].pageIndex

        switch recognizer.state {
        case .began:
            pendingStickerGestureSnapshot = (stickerPlacements, selectedStickerID)
            resizeHandleInitialScale = CGFloat(stickerPlacements[idx].scale)
            let stickerCenter = CGPoint(
                x: CGFloat(stickerPlacements[idx].normalizedX) * container.bounds.width,
                y: CGFloat(stickerPlacements[idx].normalizedY) * container.bounds.height
            )
            resizeHandleInitialDistance = hypot(
                handle.center.x - stickerCenter.x,
                handle.center.y - stickerCenter.y
            )

        case .changed:
            guard resizeHandleInitialDistance > 1 else { return }
            let location = recognizer.location(in: container)
            let stickerCenter = CGPoint(
                x: CGFloat(stickerPlacements[idx].normalizedX) * container.bounds.width,
                y: CGFloat(stickerPlacements[idx].normalizedY) * container.bounds.height
            )
            let currentDistance = hypot(location.x - stickerCenter.x, location.y - stickerCenter.y)
            let rawScale = resizeHandleInitialScale * currentDistance / resizeHandleInitialDistance
            let newScale = min(max(rawScale, 0.2), 3.0)
            stickerPlacements[idx].scale = Double(newScale)
            currentStickerScale = newScale

            if let label = container.subviews
                .compactMap({ $0 as? ScorePDFStickerGlyphView })
                .first(where: { $0.stickerID == stickerID }) {
                let ratio = resizeHandleInitialScale > 0 ? (newScale / resizeHandleInitialScale) : 1
                if ratio.isFinite, ratio > 0 {
                    label.transform = CGAffineTransform(scaleX: ratio, y: ratio)
                }
                handle.frame = CGRect(x: label.frame.maxX - 3, y: label.frame.maxY - 3, width: 6, height: 6)
                if let deleteBtn = container.subviews
                    .compactMap({ $0 as? ScorePDFStickerDeleteButton })
                    .first(where: { $0.stickerID == stickerID }) {
                    deleteBtn.frame = CGRect(x: label.frame.maxX - 7, y: label.frame.minY - 7, width: 14, height: 14)
                }
            }

        case .ended, .cancelled:
            if let snapshot = pendingStickerGestureSnapshot {
                commitStickerStateChange(
                    from: snapshot.0,
                    oldSelectedStickerID: snapshot.1,
                    actionName: "Resize Sticker"
                )
                pendingStickerGestureSnapshot = nil
            }
            if let overlay = overlayViews[pageIndex] {
                rebuildStickerViews(for: pageIndex, overlay: overlay)
            }

        default:
            return
        }
    }

    @objc func handleStickerDeleteButtonTap(_ sender: ScorePDFStickerDeleteButton) {
        setSelectedSticker(sender.stickerID)
        deleteSelectedSticker()
    }

    func applyCurrentTool(to canvas: PKCanvasView) {
        switch currentToolMode {
        case .pen:
            canvas.tool = PKInkingTool(.pen, color: currentColor.withAlphaComponent(currentOpacity), width: currentWidth)
        case .pencil:
            canvas.tool = PKInkingTool(.pencil, color: currentColor.withAlphaComponent(currentOpacity), width: currentWidth)
        case .marker:
            canvas.tool = PKInkingTool(.marker, color: currentColor.withAlphaComponent(currentOpacity), width: max(3, currentWidth + 1))
        case .eraser:
            canvas.tool = PKEraserTool(currentEraserMode == .bitmap ? .bitmap : .vector)
            _ = currentEraserSize
        case .sticker, .text:
            break
        }
    }
}
#endif
