import PDFKit

#if os(iOS)
import UIKit

func scorePDFFreeTextAnnotation(
    in pdfView: PDFView,
    at location: CGPoint,
    container: UIView,
    pageIndex: Int
) -> PDFAnnotation? {
    guard let page = pdfView.document?.page(at: pageIndex),
          container.bounds.width > 0,
          container.bounds.height > 0 else { return nil }
    let pageBounds = page.bounds(for: .mediaBox)
    let scaleX = pageBounds.width / container.bounds.width
    let scaleY = pageBounds.height / container.bounds.height
    // container origin = top-left; PDF origin = bottom-left
    let pdfPoint = CGPoint(
        x: pageBounds.origin.x + location.x * scaleX,
        y: pageBounds.origin.y + pageBounds.height - location.y * scaleY
    )
    return page.annotations.first { annotation in
        annotation.type == "FreeText" && annotation.bounds.insetBy(dx: -6, dy: -6).contains(pdfPoint)
    }
}

func scorePDFContainerRect(
    for annotationBounds: CGRect,
    in container: UIView,
    page: PDFPage
) -> CGRect {
    let pageBounds = page.bounds(for: .mediaBox)
    guard pageBounds.width > 0, pageBounds.height > 0 else { return .zero }
    let scaleX = container.bounds.width / pageBounds.width
    let scaleY = container.bounds.height / pageBounds.height
    let x = (annotationBounds.minX - pageBounds.origin.x) * scaleX
    // annotBounds.maxY is the top edge in PDF coords (bottom-left origin)
    let y = container.bounds.height - (annotationBounds.maxY - pageBounds.origin.y) * scaleY
    return CGRect(
        x: x,
        y: y,
        width: annotationBounds.width * scaleX,
        height: annotationBounds.height * scaleY
    )
}
#endif
