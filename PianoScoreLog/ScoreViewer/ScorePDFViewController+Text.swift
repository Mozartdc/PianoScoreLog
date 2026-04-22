import PDFKit

#if os(iOS)
import UIKit

extension ScorePDFViewController {

    // MARK: - Tap routing (container background tap)

    func handleTextTap(_ recognizer: UITapGestureRecognizer) {
        guard isEditorMode && isDrawingEnabled && currentToolMode == .text else { return }
        guard let container = recognizer.view else { return }
        let location = recognizer.location(in: container)
        let pageIndex = overlayViews.first(where: { $0.value.stickerContainerView === container })?.key
            ?? activePageIndex

        // Tapped on a committed/selected text box → delegate to handleTextBoxTap
        if container.subviews
            .reversed()
            .compactMap({ $0 as? ScorePDFTextBoxView })
            .first(where: { $0.frame.contains(location) }) != nil {
            return  // handleTextBoxTap fires on the box itself
        }

        // Tapped on blank area while editing → commit
        if activeTextEditorPlacement != nil {
            commitTextEditing()
            return
        }

        // Tapped on blank area while something is selected → deselect
        if selectedTextBoxID != nil {
            selectedTextBoxID = nil
            refreshAllOverlayViews()
            return
        }

        // Blank tap with nothing active → create new text box
        guard let layerID = resolvedTextLayerID() else { return }
        beginNewTextEditing(at: location, in: container, pageIndex: pageIndex, layerID: layerID)
    }

    /// Tap on a committed or selected text box view.
    @objc func handleTextBoxTap(_ recognizer: UITapGestureRecognizer) {
        guard currentToolMode == .text, isEditorMode, isDrawingEnabled else { return }
        guard let boxView = recognizer.view as? ScorePDFTextBoxView,
              let container = boxView.superview else { return }
        let pageIndex = overlayViews.first(where: { $0.value.stickerContainerView === container })?.key
            ?? activePageIndex

        if activeTextEditorPlacement != nil {
            // Already editing a different box → commit it first
            commitTextEditing()
        }

        if selectedTextBoxID == boxView.textID {
            // Already selected → enter editing
            beginEditingExistingText(textBoxView: boxView, pageIndex: pageIndex)
        } else {
            // Not yet selected → select it
            selectedTextBoxID = boxView.textID
            refreshAllOverlayViews()
        }
    }

    @objc func handleTextDeleteButtonTap(_ sender: ScorePDFTextDeleteButton) {
        if activeTextEditorPlacement?.id == sender.textID {
            let textView = activeTextEditor
            activeTextEditorPlacement = nil
            activeTextEditor = nil
            activeTextEditorPageIndex = nil
            textView?.resignFirstResponder()
            textView?.superview?.removeFromSuperview()
        }
        selectedTextBoxID = nil
        textPlacements.removeAll { $0.id == sender.textID }
        persistTextPlacements()
        refreshAllOverlayViews()
    }

    @objc func handleGlobalTapForTextCommit(_ recognizer: UITapGestureRecognizer) {
        guard activeTextEditor != nil else { return }
        if let editingView = activeTextEditor?.superview {
            let loc = recognizer.location(in: editingView)
            if editingView.bounds.contains(loc) { return }
        }
        commitTextEditing()
    }

    // MARK: - Begin editing

    private func beginNewTextEditing(
        at location: CGPoint,
        in container: UIView,
        pageIndex: Int,
        layerID: UUID
    ) {
        let containerWidth = container.bounds.width
        let boxWidth = containerWidth * 0.4
        let boxX = max(0, min(location.x - boxWidth / 2, containerWidth - boxWidth))
        // Height = one line of the default 14pt font + top/bottom insets (4+4)
        let oneLineHeight = ceil(UIFont.systemFont(ofSize: 14).lineHeight) + 8
        let boxY = location.y - oneLineHeight / 2
        let initialFrame = CGRect(x: boxX, y: boxY, width: boxWidth, height: oneLineHeight)

        let placement = TextPlacement(
            pageIndex: pageIndex,
            layerID: layerID,
            normalizedX: Double((boxX + boxWidth / 2) / containerWidth),
            normalizedY: Double((boxY + oneLineHeight / 2) / container.bounds.height),
            normalizedWidth: Double(boxWidth / containerWidth)
        )

        selectedTextBoxID = nil
        let editingView = makeEditingView(for: placement, frame: initialFrame)
        container.addSubview(editingView)
        addTextDeleteButton(for: placement, relativeTo: editingView, in: container)

        activeTextEditorPlacement = placement
        activeTextEditor = editingView.textView
        activeTextEditorPageIndex = pageIndex

        DispatchQueue.main.async { editingView.textView.becomeFirstResponder() }
    }

    private func beginEditingExistingText(
        textBoxView: ScorePDFTextBoxView,
        pageIndex: Int
    ) {
        guard let container = textBoxView.superview,
              let idx = textPlacements.firstIndex(where: { $0.id == textBoxView.textID }) else { return }
        let placement = textPlacements[idx]
        let frame = textBoxView.frame

        // Remove selected-state accessories
        container.subviews
            .filter {
                ($0 as? ScorePDFTextResizeHandleView)?.textID == placement.id
                || ($0 as? ScorePDFTextDeleteButton)?.textID == placement.id
            }
            .forEach { $0.removeFromSuperview() }
        textBoxView.removeFromSuperview()

        selectedTextBoxID = nil

        let editingView = makeEditingView(for: placement, frame: frame)
        if !placement.rtfData.isEmpty,
           let attributed = try? NSAttributedString(
               data: placement.rtfData,
               options: [.documentType: NSAttributedString.DocumentType.rtf],
               documentAttributes: nil
           ) {
            editingView.textView.attributedText = attributed
        }
        container.addSubview(editingView)
        addTextDeleteButton(for: placement, relativeTo: editingView, in: container)

        activeTextEditorPlacement = placement
        activeTextEditor = editingView.textView
        activeTextEditorPageIndex = pageIndex

        DispatchQueue.main.async { editingView.textView.becomeFirstResponder() }
    }

    private func makeEditingView(for placement: TextPlacement, frame: CGRect) -> ScorePDFTextBoxView {
        let boxView = ScorePDFTextBoxView(textID: placement.id)
        boxView.frame = frame
        boxView.layer.borderColor = UIColor.systemBlue.cgColor
        boxView.layer.borderWidth = 0.5
        boxView.textView.isEditable = true
        boxView.textView.isSelectable = true
        boxView.textView.allowsEditingTextAttributes = true
        boxView.textView.delegate = self
        boxView.textView.font = .systemFont(ofSize: 14)
        boxView.textView.textColor = .black
        boxView.textView.typingAttributes = [
            .font: UIFont.systemFont(ofSize: 14),
            .foregroundColor: UIColor.black
        ]
        return boxView
    }

    private func addTextDeleteButton(
        for placement: TextPlacement,
        relativeTo view: UIView,
        in container: UIView
    ) {
        container.subviews
            .compactMap({ $0 as? ScorePDFTextDeleteButton })
            .filter({ $0.textID == placement.id })
            .forEach({ $0.removeFromSuperview() })

        let btn = ScorePDFTextDeleteButton(textID: placement.id)
        let xConfig = UIImage.SymbolConfiguration(pointSize: 6, weight: .bold)
        btn.setImage(UIImage(systemName: "xmark", withConfiguration: xConfig), for: .normal)
        btn.tintColor = .white
        btn.backgroundColor = .systemRed
        btn.layer.cornerRadius = 7
        btn.clipsToBounds = true
        btn.frame = CGRect(x: view.frame.maxX - 7, y: view.frame.minY - 7, width: 14, height: 14)
        btn.addTarget(self, action: #selector(handleTextDeleteButtonTap(_:)), for: .touchUpInside)
        container.addSubview(btn)
    }

    // MARK: - Move (body pan, selected state only)

    @objc func handleTextBoxPan(_ recognizer: UIPanGestureRecognizer) {
        guard isEditorMode && isDrawingEnabled && currentToolMode == .text else { return }
        guard let boxView = recognizer.view as? ScorePDFTextBoxView,
              let container = boxView.superview else { return }
        guard let idx = textPlacements.firstIndex(where: { $0.id == boxView.textID }) else { return }

        let translation = recognizer.translation(in: container)
        recognizer.setTranslation(.zero, in: container)

        let newOrigin = CGPoint(
            x: max(0, min(boxView.frame.origin.x + translation.x,
                          container.bounds.width - boxView.frame.width)),
            y: max(0, min(boxView.frame.origin.y + translation.y,
                          container.bounds.height - boxView.frame.height))
        )
        boxView.frame.origin = newOrigin
        repositionTextAccessories(for: boxView.textID, boxFrame: boxView.frame, in: container)

        let w = container.bounds.width, h = container.bounds.height
        guard w > 0, h > 0 else { return }
        textPlacements[idx].normalizedX = Double(boxView.frame.midX / w)
        textPlacements[idx].normalizedY = Double(boxView.frame.midY / h)

        if recognizer.state == .ended || recognizer.state == .cancelled {
            persistTextPlacements()
        }
    }

    // MARK: - Resize (handle pan)

    @objc func handleTextResizeHandlePan(_ recognizer: UIPanGestureRecognizer) {
        guard isEditorMode && isDrawingEnabled && currentToolMode == .text else { return }
        guard let handle = recognizer.view as? ScorePDFTextResizeHandleView,
              let container = handle.superview else { return }
        guard let boxView = container.subviews
            .compactMap({ $0 as? ScorePDFTextBoxView })
            .first(where: { $0.textID == handle.textID }) else { return }
        guard let idx = textPlacements.firstIndex(where: { $0.id == handle.textID }) else { return }

        let translation = recognizer.translation(in: container)
        recognizer.setTranslation(.zero, in: container)
        let minWidth: CGFloat = 60

        var frame = boxView.frame

        switch handle.side {
        case .left:
            let newX = max(0, min(frame.origin.x + translation.x, frame.maxX - minWidth))
            let newWidth = frame.maxX - newX
            frame.origin.x = newX
            frame.size.width = newWidth

        case .right:
            let newWidth = max(minWidth, min(frame.width + translation.x,
                                             container.bounds.width - frame.origin.x))
            frame.size.width = newWidth
        }

        // Re-fit height to new width
        let neededHeight = boxView.textView.sizeThatFits(
            CGSize(width: frame.width, height: .greatestFiniteMagnitude)
        ).height
        frame.size.height = max(36, neededHeight)

        boxView.frame = frame
        repositionTextAccessories(for: handle.textID, boxFrame: frame, in: container)

        let w = container.bounds.width, h = container.bounds.height
        guard w > 0, h > 0 else { return }
        textPlacements[idx].normalizedX = Double(frame.midX / w)
        textPlacements[idx].normalizedY = Double(frame.midY / h)
        textPlacements[idx].normalizedWidth = Double(frame.width / w)

        if recognizer.state == .ended || recognizer.state == .cancelled {
            persistTextPlacements()
        }
    }

    // MARK: - Accessory repositioning helper

    private func repositionTextAccessories(for textID: UUID, boxFrame: CGRect, in container: UIView) {
        for sub in container.subviews {
            if let btn = sub as? ScorePDFTextDeleteButton, btn.textID == textID {
                btn.frame = CGRect(x: boxFrame.maxX - 7, y: boxFrame.minY - 7, width: 14, height: 14)
            }
            if let h = sub as? ScorePDFTextResizeHandleView, h.textID == textID {
                switch h.side {
                case .left:
                    h.frame = CGRect(x: boxFrame.minX - 6, y: boxFrame.midY - 6, width: 12, height: 12)
                case .right:
                    h.frame = CGRect(x: boxFrame.maxX - 6, y: boxFrame.midY - 6, width: 12, height: 12)
                }
            }
        }
    }

    // MARK: - Commit

    func commitTextEditing() {
        guard let placement = activeTextEditorPlacement,
              let textView = activeTextEditor,
              let pageIndex = activeTextEditorPageIndex else {
            activeTextEditorPlacement = nil
            activeTextEditor = nil
            activeTextEditorPageIndex = nil
            return
        }

        let editingBoxView = textView.superview

        activeTextEditorPlacement = nil
        activeTextEditor = nil
        activeTextEditorPageIndex = nil

        textView.resignFirstResponder()

        if let overlay = overlayViews[pageIndex] {
            overlay.stickerContainerView.subviews
                .compactMap({ $0 as? ScorePDFTextDeleteButton })
                .filter({ $0.textID == placement.id })
                .forEach({ $0.removeFromSuperview() })
        }
        editingBoxView?.removeFromSuperview()

        let attributed = textView.attributedText
        let plainText = attributed?.string.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if plainText.isEmpty {
            textPlacements.removeAll { $0.id == placement.id }
        } else {
            let rtfData = (try? attributed?.data(
                from: NSRange(location: 0, length: attributed?.length ?? 0),
                documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
            )) ?? Data()

            var updated = placement
            updated.rtfData = rtfData

            if let idx = textPlacements.firstIndex(where: { $0.id == placement.id }) {
                textPlacements[idx] = updated
            } else {
                textPlacements.append(updated)
            }
        }

        persistTextPlacements()
        if let overlay = overlayViews[pageIndex] {
            rebuildTextViews(for: pageIndex, overlay: overlay)
        }
    }

    // MARK: - UITextViewDelegate

    func textViewDidChange(_ textView: UITextView) {
        guard textView === activeTextEditor,
              let superview = textView.superview,
              let placement = activeTextEditorPlacement else { return }

        let maxWidth = superview.frame.width
        let needed = textView.sizeThatFits(CGSize(width: maxWidth, height: .greatestFiniteMagnitude))
        superview.frame.size = CGSize(width: maxWidth, height: max(44, needed.height))

        if let container = superview.superview {
            let h = container.bounds.height
            guard h > 0 else { return }
            if let idx = textPlacements.firstIndex(where: { $0.id == placement.id }) {
                textPlacements[idx].normalizedY = Double(superview.frame.midY / h)
            }
            container.subviews.compactMap({ $0 as? ScorePDFTextDeleteButton })
                .filter({ $0.textID == placement.id })
                .forEach({
                    $0.frame = CGRect(x: superview.frame.maxX - 7, y: superview.frame.minY - 7,
                                      width: 14, height: 14)
                })
        }
    }

    func textViewDidEndEditing(_ textView: UITextView) {
        guard textView === activeTextEditor else { return }
        commitTextEditing()
    }

    // MARK: - Persist

    func persistTextPlacements() {
        guard let currentPieceID else { return }
        ScoreFileStore.saveTextPlacements(textPlacements, pieceID: currentPieceID)
    }

    // MARK: - Helpers

    private func resolvedTextLayerID() -> UUID? {
        if let id = activeLayerID, annotationLayers.contains(where: { $0.id == id && $0.isVisible }) {
            return id
        }
        return annotationLayers.first(where: { $0.isVisible })?.id ?? annotationLayers.first?.id
    }
}
#endif
