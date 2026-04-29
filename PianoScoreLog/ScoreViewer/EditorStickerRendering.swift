import SwiftUI
#if os(iOS)
import UIKit
import CoreText

func stickerPaletteFineTuneMultiplier(symbolID: String) -> CGFloat {
    switch symbolID {
    case "trebleClef", "aTempo":
        return 1.35
    case "fingering1", "fingering2", "fingering3", "fingering4", "fingering5", "rit", "rall", "eighthRest":
        return 0.80
    case "wholeRest", "halfRest":
        return 0.31
    case "pedalUpMark", "doubleSharp":
        return 0.72
    case "dynamicP":
        return 0.60
    case "accent", "marcato":
        return 0.36
    case "staccato":
        return 0.18
    case "fermata":
        return 0.50
    case "trill":
        return 0.70
    case "wholeNote":
        return 0.36
    case "halfNote":
        return 1.0
    default:
        return 1.0
    }
}

/// 현재 크기를 유지할 스탬프는 1.0, 나머지는 0.8을 반환한다.
/// 팔레트 fillRatio와 캔버스 pointSize 양쪽에서 공통으로 사용한다.
func stickerSizeScale(symbolID: String) -> CGFloat {
    let exemptIDs: Set<String> = [
        "trebleClef", "bassClef",
        "cresc", "dim",
        "accent", "staccato", "marcato", "fermata",
        "aTempo", "rall",
        "wholeNote", "halfNote", "quarterNote", "eighthNote", "sixteenthNote",
        "wholeRest", "halfRest", "quarterRest", "eighthRest", "sixteenthRest"
    ]
    return exemptIDs.contains(symbolID) ? 1.0 : 0.8
}

func stickerSymbolPointSize(symbolID: String, baseSize: CGFloat) -> CGFloat {
    let scale = stickerSizeScale(symbolID: symbolID)

    if ["dynamicP", "dynamicPP", "dynamicPPP", "dynamicMP", "dynamicMF", "dynamicF", "dynamicFF", "dynamicFFF", "sfz"].contains(symbolID) {
        return baseSize * 1.25 * scale
    }
    if ["accent", "marcato", "strongAccent", "staccato", "tenuto", "fermata", "trill", "mordent", "turn"].contains(symbolID) {
        return baseSize * 1.48 * scale
    }
    if ["sharp", "flat", "doubleSharp", "doubleFlat", "natural"].contains(symbolID) {
        return baseSize * 1.52 * scale
    }
    if ["cresc", "dim"].contains(symbolID) {
        return baseSize * 1.35 * scale
    }
    if ["rit", "aTempo", "rall", "DC", "DS", "fine"].contains(symbolID) {
        return baseSize * 0.88 * scale
    }
    return baseSize * scale
}

func stickerDisplayText(from value: String) -> String {
    if stickerSFSymbolName(from: value) != nil { return "" }
    guard value.hasPrefix("U+") else { return value }
    let hex = value.dropFirst(2)
    guard let scalarValue = UInt32(hex, radix: 16), let scalar = UnicodeScalar(scalarValue) else {
        return "?"
    }
    return String(scalar)
}

func stickerSFSymbolName(from value: String) -> String? {
    guard value.hasPrefix("SF:") else { return nil }
    return String(value.dropFirst(3))
}

func renderedBravuraGlyphImage(value: String, font: UIFont, color: UIColor) -> UIImage? {
    guard value.hasPrefix("U+") else { return nil }
    let hex = String(value.dropFirst(2))
    guard let code = UInt32(hex, radix: 16), let scalar = UnicodeScalar(code) else { return nil }
    let text = String(scalar)
    let attributed = NSAttributedString(
        string: text,
        attributes: [
            .font: font,
            .foregroundColor: color
        ]
    )
    let line = CTLineCreateWithAttributedString(attributed)
    var bounds = CTLineGetBoundsWithOptions(
        line,
        [.useGlyphPathBounds, .excludeTypographicLeading]
    ).integral
    if bounds.isNull || bounds.isEmpty {
        let fallback = attributed.size()
        guard fallback.width > 0, fallback.height > 0 else { return nil }
        bounds = CGRect(origin: .zero, size: CGSize(width: ceil(fallback.width), height: ceil(fallback.height)))
    }

    let size = CGSize(width: max(1, ceil(bounds.width)), height: max(1, ceil(bounds.height)))
    let renderer = UIGraphicsImageRenderer(size: size)
    return renderer.image { context in
        let cg = context.cgContext
        cg.translateBy(x: 0, y: size.height)
        cg.scaleBy(x: 1, y: -1)
        cg.translateBy(x: -bounds.origin.x, y: -bounds.origin.y)
        CTLineDraw(line, cg)
    }
}

private func renderedTightTextImage(text: String, font: UIFont, color: UIColor) -> UIImage? {
    guard !text.isEmpty else { return nil }
    let attributed = NSAttributedString(
        string: text,
        attributes: [
            .font: font,
            .foregroundColor: color
        ]
    )
    let line = CTLineCreateWithAttributedString(attributed)
    var bounds = CTLineGetBoundsWithOptions(
        line,
        [.useGlyphPathBounds, .excludeTypographicLeading]
    ).integral
    if bounds.isNull || bounds.isEmpty {
        let fallback = attributed.size()
        guard fallback.width > 0, fallback.height > 0 else { return nil }
        bounds = CGRect(origin: .zero, size: CGSize(width: ceil(fallback.width), height: ceil(fallback.height)))
    }

    let size = CGSize(width: max(1, ceil(bounds.width)), height: max(1, ceil(bounds.height)))
    let renderer = UIGraphicsImageRenderer(size: size)
    return renderer.image { context in
        let cg = context.cgContext
        cg.translateBy(x: 0, y: size.height)
        cg.scaleBy(x: 1, y: -1)
        cg.translateBy(x: -bounds.origin.x, y: -bounds.origin.y)
        CTLineDraw(line, cg)
    }
}

func renderedStickerPaletteImage(
    symbolID: String,
    value: String,
    color: UIColor,
    canvasSize: CGSize,
    fillRatio: CGFloat
) -> UIImage? {
    let raw: UIImage?
    if let sfName = stickerSFSymbolName(from: value) {
        let config = UIImage.SymbolConfiguration(pointSize: 120, weight: .semibold)
        raw = UIImage(systemName: sfName, withConfiguration: config)?
            .withTintColor(color, renderingMode: .alwaysOriginal)
    } else if value.hasPrefix("U+"), let bravura = UIFont(name: "Bravura", size: 120) {
        raw = renderedBravuraGlyphImage(value: value, font: bravura, color: color)
    } else {
        let text = stickerDisplayText(from: value)
        if ["rit", "aTempo", "rall", "DC", "DS", "fine"].contains(symbolID) {
            raw = renderedTightTextImage(text: text, font: UIFont.italicSystemFont(ofSize: 96), color: color)
        } else {
            raw = renderedTightTextImage(text: text, font: UIFont.systemFont(ofSize: 96, weight: .semibold), color: color)
        }
    }
    guard let raw, raw.size.width > 0, raw.size.height > 0 else { return nil }

    let target = CGSize(
        width: max(1, canvasSize.width * fillRatio),
        height: max(1, canvasSize.height * fillRatio)
    )
    let ratio = min(target.width / raw.size.width, target.height / raw.size.height)
    let drawSize = CGSize(width: raw.size.width * ratio, height: raw.size.height * ratio)
    let origin = CGPoint(x: (canvasSize.width - drawSize.width) * 0.5, y: (canvasSize.height - drawSize.height) * 0.5)

    let renderer = UIGraphicsImageRenderer(size: canvasSize)
    return renderer.image { _ in
        raw.draw(in: CGRect(origin: origin, size: drawSize))
    }
}
#endif
