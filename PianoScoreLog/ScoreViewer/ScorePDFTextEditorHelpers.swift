#if os(iOS)
import UIKit

func makeScorePDFTextEditor(
    frame: CGRect,
    delegate: UITextViewDelegate,
    longPressTarget: Any?,
    longPressAction: Selector
) -> UITextView {
    let textView = UITextView(frame: frame)
    textView.backgroundColor = UIColor.systemYellow.withAlphaComponent(0.12)
    textView.textColor = .label
    textView.font = .systemFont(ofSize: 16)
    textView.isScrollEnabled = false
    textView.delegate = delegate
    textView.layer.borderColor = UIColor.systemBlue.withAlphaComponent(0.5).cgColor
    textView.layer.borderWidth = 1
    textView.layer.cornerRadius = 4

    let longPress = UILongPressGestureRecognizer(target: longPressTarget, action: longPressAction)
    longPress.minimumPressDuration = 0.4
    textView.addGestureRecognizer(longPress)

    return textView
}

func requestScorePDFFirstResponder(_ textView: UITextView) {
    DispatchQueue.main.async { textView.becomeFirstResponder() }
}
#endif
