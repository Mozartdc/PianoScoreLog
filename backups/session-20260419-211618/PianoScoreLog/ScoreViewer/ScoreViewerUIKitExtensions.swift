#if os(iOS)
import UIKit

extension UIImage {
    var dominantColor: UIColor? {
        guard let cgImage = cgImage else { return nil }
        var data = [UInt8](repeating: 0, count: 4)
        guard let context = CGContext(
            data: &data,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return UIColor(
            red: CGFloat(data[0]) / 255,
            green: CGFloat(data[1]) / 255,
            blue: CGFloat(data[2]) / 255,
            alpha: 1
        )
    }
}

extension UIColor {
    convenience init?(hex: String) {
        let cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "")
        guard cleaned.count == 8, let value = UInt64(cleaned, radix: 16) else { return nil }
        let r = CGFloat((value & 0xFF000000) >> 24) / 255
        let g = CGFloat((value & 0x00FF0000) >> 16) / 255
        let b = CGFloat((value & 0x0000FF00) >> 8) / 255
        let a = CGFloat(value & 0x000000FF) / 255
        self.init(red: r, green: g, blue: b, alpha: a)
    }

    var hexString: String {
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        guard getRed(&r, green: &g, blue: &b, alpha: &a) else { return "000000FF" }
        return String(format: "%02X%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255), Int(a * 255))
    }
}
#endif
