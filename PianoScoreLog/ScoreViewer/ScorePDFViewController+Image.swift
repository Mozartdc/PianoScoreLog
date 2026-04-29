import PDFKit
import PhotosUI
import UniformTypeIdentifiers

#if os(iOS)
import UIKit

extension ScorePDFViewController: PHPickerViewControllerDelegate, UIDocumentPickerDelegate {

    // MARK: - Picker presentation

    func presentGalleryPicker() {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.selectionLimit = 1
        config.filter = .images
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = self
        if let presented = presentedViewController {
            presented.dismiss(animated: false) { [weak self] in
                self?.present(picker, animated: true)
            }
        } else {
            present(picker, animated: true)
        }
    }

    func presentFilePicker() {
        let types: [UTType] = [.png, .jpeg, .heic, .image]
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
        picker.delegate = self
        picker.allowsMultipleSelection = false
        if let presented = presentedViewController {
            presented.dismiss(animated: false) { [weak self] in
                self?.present(picker, animated: true)
            }
        } else {
            present(picker, animated: true)
        }
    }

    // MARK: - PHPickerViewControllerDelegate

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard let result = results.first else { return }
        result.itemProvider.loadObject(ofClass: UIImage.self) { [weak self] object, error in
            guard let self, let image = object as? UIImage, error == nil else { return }
            DispatchQueue.main.async { self.placeImage(image) }
        }
    }

    // MARK: - UIDocumentPickerDelegate

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let image = UIImage(contentsOfFile: url.path) else { return }
            DispatchQueue.main.async { self?.placeImage(image) }
        }
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {}

    // MARK: - Image placement

    private func placeImage(_ image: UIImage) {
        guard let pieceID = currentPieceID,
              let overlay = overlayViews[activePageIndex] else { return }

        let layerID = activeLayerID
            ?? annotationLayers.first(where: { $0.isVisible })?.id
            ?? annotationLayers.first?.id
        guard let layerID else { return }

        if activeLayerID == nil {
            activeLayerID = layerID
            onLayerConfigurationChanged?(annotationLayers, activeLayerID)
            persistLayerMetadata()
        }

        guard let filename = try? ScoreFileStore.saveImageFile(image, pieceID: pieceID) else { return }

        let bounds = overlay.imageContainerView.bounds
        guard bounds.width > 0, bounds.height > 0 else { return }

        // Default: 40% page width, proportional height, centered
        let normalizedWidth = 0.4
        let aspectRatio = image.size.height / max(image.size.width, 1)
        let pixelWidth = normalizedWidth * Double(bounds.width)
        let pixelHeight = pixelWidth * aspectRatio
        let normalizedHeight = pixelHeight / Double(bounds.height)

        let placement = ImagePlacement(
            pageIndex: activePageIndex,
            layerID: layerID,
            normalizedX: 0.5,
            normalizedY: 0.5,
            normalizedWidth: normalizedWidth,
            normalizedHeight: min(normalizedHeight, 0.9),
            imageFilename: filename
        )
        let oldPlacements = imagePlacements
        let oldSelected = selectedImageID
        isImageManagementMode = false  // 이미지 배치 후 관리 모드 해제
        imagePlacements.append(placement)
        selectedImageID = placement.id
        commitImageStateChange(
            from: oldPlacements,
            oldSelectedImageID: oldSelected,
            actionName: "Add Image"
        )
    }

    // MARK: - Tap (select / deselect)

    @objc func handleImageTap(_ recognizer: UITapGestureRecognizer) {
        guard isEditorMode else { return }
        guard let imgView = recognizer.view as? ScorePDFImageView else { return }
        isImageManagementMode = false  // 이미지 탭 시 관리 모드 해제
        if selectedImageID == imgView.imageID {
            selectedImageID = nil
        } else {
            selectedImageID = imgView.imageID
        }
        refreshAllOverlayViews()
    }

    // MARK: - Pan (move)

    @objc func handleImagePan(_ recognizer: UIPanGestureRecognizer) {
        guard isEditorMode else { return }
        guard let imgView = recognizer.view as? ScorePDFImageView,
              let container = imgView.superview else { return }
        let imageID = imgView.imageID
        guard let idx = imagePlacements.firstIndex(where: { $0.id == imageID }) else { return }
        guard container.bounds.width > 0, container.bounds.height > 0 else { return }

        switch recognizer.state {
        case .began:
            isImageManagementMode = false  // 드래그 시작 시 관리 모드 해제
            selectedImageID = imageID
            pendingImageGestureSnapshot = (imagePlacements, selectedImageID)
        case .ended, .cancelled:
            if let snapshot = pendingImageGestureSnapshot {
                let pageIndex = imagePlacements[idx].pageIndex
                commitImageStateChange(
                    from: snapshot.0,
                    oldSelectedImageID: snapshot.1,
                    actionName: "Move Image"
                )
                if let overlay = overlayViews[pageIndex] {
                    rebuildImageViews(for: pageIndex, overlay: overlay)
                }
                pendingImageGestureSnapshot = nil
            }
            return
        case .changed:
            break
        default:
            return
        }

        let translation = recognizer.translation(in: container)
        recognizer.setTranslation(.zero, in: container)
        let dx = Double(translation.x / container.bounds.width)
        let dy = Double(translation.y / container.bounds.height)
        imagePlacements[idx].normalizedX = min(max(imagePlacements[idx].normalizedX + dx, 0), 1)
        imagePlacements[idx].normalizedY = min(max(imagePlacements[idx].normalizedY + dy, 0), 1)

        let cx = CGFloat(imagePlacements[idx].normalizedX) * container.bounds.width
        let cy = CGFloat(imagePlacements[idx].normalizedY) * container.bounds.height
        let w = imgView.bounds.width
        let h = imgView.bounds.height
        imgView.frame = CGRect(x: cx - w / 2, y: cy - h / 2, width: w, height: h)
        repositionImageAccessories(for: imageID, imageFrame: imgView.frame, in: container)
    }

    // MARK: - Resize handle pan

    @objc func handleImageResizeHandlePan(_ recognizer: UIPanGestureRecognizer) {
        guard isEditorMode else { return }
        guard let handle = recognizer.view as? ScorePDFImageResizeHandleView,
              let container = handle.superview else { return }
        let imageID = handle.imageID
        guard let idx = imagePlacements.firstIndex(where: { $0.id == imageID }) else { return }
        guard container.bounds.width > 0, container.bounds.height > 0 else { return }

        switch recognizer.state {
        case .began:
            pendingImageGestureSnapshot = (imagePlacements, selectedImageID)
            imageResizeInitialSize = CGSize(
                width: CGFloat(imagePlacements[idx].normalizedWidth) * container.bounds.width,
                height: CGFloat(imagePlacements[idx].normalizedHeight) * container.bounds.height
            )
            let center = CGPoint(
                x: CGFloat(imagePlacements[idx].normalizedX) * container.bounds.width,
                y: CGFloat(imagePlacements[idx].normalizedY) * container.bounds.height
            )
            imageResizeInitialDistance = hypot(handle.center.x - center.x, handle.center.y - center.y)

        case .changed:
            guard imageResizeInitialDistance > 1 else { return }
            let location = recognizer.location(in: container)
            let center = CGPoint(
                x: CGFloat(imagePlacements[idx].normalizedX) * container.bounds.width,
                y: CGFloat(imagePlacements[idx].normalizedY) * container.bounds.height
            )
            let currentDistance = hypot(location.x - center.x, location.y - center.y)
            let ratio = currentDistance / imageResizeInitialDistance
            let newWidth = max(20, imageResizeInitialSize.width * ratio)
            let newHeight = max(20, imageResizeInitialSize.height * ratio)
            imagePlacements[idx].normalizedWidth = Double(newWidth / container.bounds.width)
            imagePlacements[idx].normalizedHeight = Double(newHeight / container.bounds.height)

            if let imgView = container.subviews
                .compactMap({ $0 as? ScorePDFImageView })
                .first(where: { $0.imageID == imageID }) {
                let cx = CGFloat(imagePlacements[idx].normalizedX) * container.bounds.width
                let cy = CGFloat(imagePlacements[idx].normalizedY) * container.bounds.height
                imgView.frame = CGRect(x: cx - newWidth / 2, y: cy - newHeight / 2,
                                       width: newWidth, height: newHeight)
                repositionImageAccessories(for: imageID, imageFrame: imgView.frame, in: container)
            }

        case .ended, .cancelled:
            if let snapshot = pendingImageGestureSnapshot {
                let pageIndex = imagePlacements[idx].pageIndex
                commitImageStateChange(
                    from: snapshot.0,
                    oldSelectedImageID: snapshot.1,
                    actionName: "Resize Image"
                )
                if let overlay = overlayViews[pageIndex] {
                    rebuildImageViews(for: pageIndex, overlay: overlay)
                }
                pendingImageGestureSnapshot = nil
            }

        default:
            return
        }
    }

    // MARK: - Delete button

    @objc func handleImageDeleteButtonTap(_ sender: ScorePDFImageDeleteButton) {
        selectedImageID = sender.imageID
        deleteSelectedImage()
    }

    private func deleteSelectedImage() {
        guard let selectedImageID,
              imagePlacements.contains(where: { $0.id == selectedImageID }) else { return }
        let oldPlacements = imagePlacements
        let oldSelected = self.selectedImageID
        imagePlacements.removeAll { $0.id == selectedImageID }
        self.selectedImageID = nil
        commitImageStateChange(
            from: oldPlacements,
            oldSelectedImageID: oldSelected,
            actionName: "Delete Image"
        )
    }

    // MARK: - Accessory repositioning

    private func repositionImageAccessories(for imageID: UUID, imageFrame: CGRect, in container: UIView) {
        if let btn = container.subviews
            .compactMap({ $0 as? ScorePDFImageDeleteButton })
            .first(where: { $0.imageID == imageID }) {
            btn.frame = CGRect(x: imageFrame.maxX - 7, y: imageFrame.minY - 7, width: 14, height: 14)
        }
        if let handle = container.subviews
            .compactMap({ $0 as? ScorePDFImageResizeHandleView })
            .first(where: { $0.imageID == imageID }) {
            handle.frame = CGRect(x: imageFrame.maxX - 6, y: imageFrame.maxY - 6, width: 12, height: 12)
        }
    }

    // MARK: - Undo / redo support

    func applyImageState(
        _ newPlacements: [ImagePlacement],
        selectedImageID newSelectedID: UUID?,
        actionName: String,
        undoManager manager: UndoManager?,
        registeringOppositeWith oppositePlacements: [ImagePlacement],
        oppositeSelectedImageID: UUID?
    ) {
        manager?.registerUndo(withTarget: self) { target in
            target.applyImageState(
                oppositePlacements,
                selectedImageID: oppositeSelectedImageID,
                actionName: actionName,
                undoManager: manager,
                registeringOppositeWith: newPlacements,
                oppositeSelectedImageID: newSelectedID
            )
        }
        manager?.setActionName(actionName)
        imagePlacements = newPlacements
        selectedImageID = newSelectedID
        persistImagePlacements()
        refreshAllOverlayViews()
    }

    func commitImageStateChange(
        from oldPlacements: [ImagePlacement],
        oldSelectedImageID: UUID?,
        actionName: String
    ) {
        let newPlacements = imagePlacements
        let newSelectedID = selectedImageID
        guard oldPlacements != newPlacements || oldSelectedImageID != newSelectedID else { return }
        let manager = currentCanvasView?.undoManager ?? undoManager
        manager?.registerUndo(withTarget: self) { target in
            target.applyImageState(
                oldPlacements,
                selectedImageID: oldSelectedImageID,
                actionName: actionName,
                undoManager: manager,
                registeringOppositeWith: newPlacements,
                oppositeSelectedImageID: newSelectedID
            )
        }
        manager?.setActionName(actionName)
        persistImagePlacements()
        refreshAllOverlayViews()
    }
}
#endif
