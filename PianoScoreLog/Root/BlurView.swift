import SwiftUI
import UIKit

/// UIVisualEffectView wrapper for reliable blur above UIKit-hosted content.
struct BlurView: UIViewRepresentable {
    var style: UIBlurEffect.Style = .systemChromeMaterial
    var bottomCornerRadius: CGFloat = 0

    func makeUIView(context: Context) -> UIVisualEffectView {
        let view = UIVisualEffectView(effect: UIBlurEffect(style: style))
        applyStyle(to: view)
        return view
    }

    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {
        uiView.effect = UIBlurEffect(style: style)
        applyStyle(to: uiView)
    }

    private func applyStyle(to view: UIVisualEffectView) {
        view.layer.cornerRadius = bottomCornerRadius
        view.layer.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        view.layer.cornerCurve = .continuous
        view.clipsToBounds = bottomCornerRadius > 0
    }
}
