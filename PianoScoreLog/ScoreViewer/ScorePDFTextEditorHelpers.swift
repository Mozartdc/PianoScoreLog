#if os(iOS)
import UIKit

func requestScorePDFFirstResponder(_ textView: UITextView) {
    DispatchQueue.main.async { textView.becomeFirstResponder() }
}
#endif
