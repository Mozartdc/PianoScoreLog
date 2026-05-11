#if os(iOS)
import UIKit
import PencilKit

func requestScorePDFFirstResponder(_ textView: UITextView) {
    DispatchQueue.main.async { textView.becomeFirstResponder() }
}

/// PDFPageOverlayView는 PDF 페이지의 네이티브 포인트 크기를 bounds로 사용한다.
/// 스캔 해상도에 따라 페이지 크기가 달라지면(예: 595pt vs 2480pt) 고정 폰트 크기가
/// 화면에서 다른 비율로 보이는 문제가 생긴다.
/// 이 기준값을 기준으로 폰트·캔버스 좌표계를 정규화한다.
let kTextToolReferencePageWidth: CGFloat = 595   // A4 @ 72dpi

/// `PKDrawing.applying(_:)` 대신 각 스트로크의 transform에 scale을 곱해 drawing을 변환한다.
/// `scale < 1` 이면 축소 (page space → normalized space),
/// `scale > 1` 이면 확대 (normalized space → page space).
func scaleDrawing(_ drawing: PKDrawing, by scale: CGFloat) -> PKDrawing {
    guard abs(scale - 1.0) > 0.001, !drawing.strokes.isEmpty else { return drawing }
    let scaleTransform = CGAffineTransform(scaleX: scale, y: scale)
    let scaledStrokes = drawing.strokes.map { stroke in
        // stroke.transform: path 좌표계 → canvas 좌표계 변환.
        // 뒤에 scaleTransform을 concatenate하면 canvas 좌표계에 scale이 적용된다.
        let scaledTransform = stroke.transform.concatenating(scaleTransform)
        return PKStroke(
            ink: stroke.ink,
            path: stroke.path,
            transform: scaledTransform,
            mask: stroke.mask
        )
    }
    return PKDrawing(strokes: scaledStrokes)
}

/// `creationPageWidth`와 현재 캔버스 폭을 이용해 NSAttributedString의 폰트 크기를 스케일링한다.
/// 기준값이 없으면 (구버전 데이터) 원본을 그대로 돌려준다.
func scaledAttributedString(
    _ attrStr: NSAttributedString,
    creationPageWidth: Double?,
    currentPageWidth: CGFloat
) -> NSAttributedString {
    guard let cpw = creationPageWidth, cpw > 0 else { return attrStr }
    let scale = currentPageWidth / CGFloat(cpw)
    guard abs(scale - 1.0) > 0.01 else { return attrStr }
    let mutable = NSMutableAttributedString(attributedString: attrStr)
    let fullRange = NSRange(location: 0, length: mutable.length)
    mutable.enumerateAttribute(.font, in: fullRange, options: []) { value, range, _ in
        if let font = value as? UIFont {
            mutable.addAttribute(.font,
                                 value: font.withSize(max(1, font.pointSize * scale)),
                                 range: range)
        }
    }
    return mutable
}

#endif
