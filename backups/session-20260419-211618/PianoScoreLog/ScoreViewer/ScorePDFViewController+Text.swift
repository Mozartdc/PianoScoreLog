import PDFKit

#if os(iOS)
import UIKit

extension ScorePDFViewController {
    func handleTextTap(_ recognizer: UITapGestureRecognizer) {
        guard isEditorMode && isDrawingEnabled else { return }
        guard let container = recognizer.view else { return }
        let location = recognizer.location(in: container)
        let pageIndex = overlayViews.first(where: { $0.value.stickerContainerView === container })?.key ?? activePageIndex

        // Tap on existing free-text annotation -> re-edit it
        if let existing = scorePDFFreeTextAnnotation(in: pdfView, at: location, container: container, pageIndex: pageIndex) {
            commitTextEditing()
            beginEditingExistingAnnotation(existing, in: container, pageIndex: pageIndex)
            return
        }

        // Tap on blank area while a text editor is active -> commit, don't open another
        if activeTextEditor != nil {
            commitTextEditing()
            return
        }

        // Open a new text editor at the tap location
        beginTextEditing(at: location, in: container, pageIndex: pageIndex)
    }

    func beginTextEditing(at location: CGPoint, in container: UIView, pageIndex: Int) {
        let initialWidth: CGFloat = 180
        let initialHeight: CGFloat = 44
        let frame = CGRect(
            x: min(location.x, container.bounds.width - initialWidth),
            y: location.y - initialHeight / 2,
            width: initialWidth,
            height: initialHeight
        )
        let textView = makeScorePDFTextEditor(
            frame: frame,
            delegate: self,
            longPressTarget: self,
            longPressAction: #selector(handleEditorLongPress(_:))
        )
        container.addSubview(textView)
        activeTextEditor = textView
        activeTextEditorPageIndex = pageIndex
        editingAnnotation = nil
        requestScorePDFFirstResponder(textView)
    }

    func beginEditingExistingAnnotation(_ annotation: PDFAnnotation, in container: UIView, pageIndex: Int) {
        guard let page = pdfView.document?.page(at: pageIndex) else { return }
        let frame = scorePDFContainerRect(for: annotation.bounds, in: container, page: page)
        let textView = makeScorePDFTextEditor(
            frame: frame,
            delegate: self,
            longPressTarget: self,
            longPressAction: #selector(handleEditorLongPress(_:))
        )
        textView.text = annotation.contents ?? ""
        page.removeAnnotation(annotation)
        container.addSubview(textView)
        activeTextEditor = textView
        activeTextEditorPageIndex = pageIndex
        editingAnnotation = annotation
        requestScorePDFFirstResponder(textView)
    }

    func commitTextEditing() {
        guard let textView = activeTextEditor,
              let pageIndex = activeTextEditorPageIndex else { return }
        // Clear state before any early return so we don't double-commit
        activeTextEditor = nil
        activeTextEditorPageIndex = nil
        let savedAnnotation = editingAnnotation
        editingAnnotation = nil

        textView.resignFirstResponder()
        let text = textView.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !text.isEmpty,
              let container = textView.superview,
              let page = pdfView.document?.page(at: pageIndex) else {
            textView.removeFromSuperview()
            return
        }

        // Convert UITextView frame to PDF page coordinate bounds
        let editorFrame = textView.frame
        let pageBounds = page.bounds(for: .mediaBox)
        let scaleX = pageBounds.width / container.bounds.width
        let scaleY = pageBounds.height / container.bounds.height

        // Convert top-left origin of frame -> PDF bottom-left origin
        let pdfMinY = pageBounds.origin.y
            + pageBounds.height
            - editorFrame.maxY * scaleY
        let annotBounds = CGRect(
            x: pageBounds.origin.x + editorFrame.minX * scaleX,
            y: pdfMinY,
            width: editorFrame.width * scaleX,
            height: editorFrame.height * scaleY
        )

        // Re-use existing annotation's bounds if it had one
        let finalBounds = savedAnnotation != nil ? annotBounds : annotBounds
        let annotation = PDFAnnotation(bounds: finalBounds, forType: .freeText, withProperties: nil)
        annotation.contents = text
        annotation.font = UIFont.systemFont(ofSize: 16 * scaleX)
        annotation.fontColor = .black
        annotation.color = .clear
        annotation.alignment = .left
        page.addAnnotation(annotation)

        textView.removeFromSuperview()
    }

    @objc func handleEditorLongPress(_ recognizer: UILongPressGestureRecognizer) {
        guard let textView = recognizer.view as? UITextView,
              let container = textView.superview else { return }
        switch recognizer.state {
        case .began:
            UIView.animate(withDuration: 0.12) {
                textView.transform = CGAffineTransform(scaleX: 1.04, y: 1.04)
                textView.layer.borderColor = UIColor.systemBlue.cgColor
            }
        case .changed:
            let location = recognizer.location(in: container)
            let halfW = textView.frame.width / 2
            let halfH = textView.frame.height / 2
            textView.frame.origin = CGPoint(
                x: min(max(location.x - halfW, 0), container.bounds.width - textView.frame.width),
                y: min(max(location.y - halfH, 0), container.bounds.height - textView.frame.height)
            )
        case .ended, .cancelled:
            UIView.animate(withDuration: 0.12) {
                textView.transform = .identity
                textView.layer.borderColor = UIColor.systemBlue.withAlphaComponent(0.5).cgColor
            }
        default:
            break
        }
    }

    @objc func handleGlobalTapForTextCommit(_ recognizer: UITapGestureRecognizer) {
        guard let textView = activeTextEditor else { return }
        let locationInTextView = recognizer.location(in: textView)
        guard !textView.bounds.contains(locationInTextView) else { return }
        commitTextEditing()
    }

    func textViewDidChange(_ textView: UITextView) {
        guard textView === activeTextEditor else { return }
        let maxWidth = textView.frame.width
        let needed = textView.sizeThatFits(CGSize(width: maxWidth, height: .greatestFiniteMagnitude))
        textView.frame.size = CGSize(width: maxWidth, height: max(needed.height, 44))
    }

    func textViewDidEndEditing(_ textView: UITextView) {
        guard textView === activeTextEditor else { return }
        commitTextEditing()
    }
}
#endif
