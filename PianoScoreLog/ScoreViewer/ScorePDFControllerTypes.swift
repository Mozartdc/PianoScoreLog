import PDFKit

#if os(iOS)
import PencilKit
import UIKit

struct ScorePDFPendingConfiguration {
    let url: URL
    let pieceID: UUID
    let startPageIndex: Int
}

struct ScorePDFDrawingKey: Hashable {
    let pageIndex: Int
    let layerID: UUID
}

final class ScorePDFLayeredPageOverlayView: UIView {
    let passiveImageView = UIImageView()
    let stickerContainerView = UIView()
    let canvasView = PKCanvasView()

    /// 서브뷰(PKCanvasView, stickerContainerView)가 터치를 처리하지 않으면
    /// nil을 반환해 PDFKit 스크롤뷰까지 터치를 통과시킨다.
    /// PKCanvasView는 pencilOnly 정책이므로 손가락 패닝은 PDFKit에 전달된다.
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let result = super.hitTest(point, with: event)
        return result === self ? nil : result
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        passiveImageView.translatesAutoresizingMaskIntoConstraints = false
        passiveImageView.contentMode = .scaleToFill
        passiveImageView.isUserInteractionEnabled = false
        addSubview(passiveImageView)

        stickerContainerView.translatesAutoresizingMaskIntoConstraints = false
        stickerContainerView.isUserInteractionEnabled = true
        stickerContainerView.backgroundColor = .clear
        addSubview(stickerContainerView)

        canvasView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(canvasView)

        NSLayoutConstraint.activate([
            passiveImageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            passiveImageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            passiveImageView.topAnchor.constraint(equalTo: topAnchor),
            passiveImageView.bottomAnchor.constraint(equalTo: bottomAnchor),
            stickerContainerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            stickerContainerView.trailingAnchor.constraint(equalTo: trailingAnchor),
            stickerContainerView.topAnchor.constraint(equalTo: topAnchor),
            stickerContainerView.bottomAnchor.constraint(equalTo: bottomAnchor),
            canvasView.leadingAnchor.constraint(equalTo: leadingAnchor),
            canvasView.trailingAnchor.constraint(equalTo: trailingAnchor),
            canvasView.topAnchor.constraint(equalTo: topAnchor),
            canvasView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

final class ScorePDFStickerGlyphView: UILabel {
    let stickerID: UUID

    init(stickerID: UUID) {
        self.stickerID = stickerID
        super.init(frame: .zero)
        isUserInteractionEnabled = true
        backgroundColor = .clear
        textAlignment = .center
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

final class ScorePDFStickerDeleteButton: UIButton {
    let stickerID: UUID

    init(stickerID: UUID) {
        self.stickerID = stickerID
        super.init(frame: .zero)
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        bounds.insetBy(dx: -10, dy: -10).contains(point)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

final class ScorePDFStickerResizeHandleView: UIView {
    let stickerID: UUID

    init(stickerID: UUID) {
        self.stickerID = stickerID
        super.init(frame: .zero)
        isUserInteractionEnabled = true
        backgroundColor = .systemBlue
        layer.cornerRadius = 3
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        bounds.insetBy(dx: -6, dy: -6).contains(point)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

final class ScorePDFTextDeleteButton: UIButton {
    let textID: UUID

    init(textID: UUID) {
        self.textID = textID
        super.init(frame: .zero)
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        bounds.insetBy(dx: -10, dy: -10).contains(point)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }
}

/// Left / right resize handles shown when a text box is selected (not editing).
final class ScorePDFTextResizeHandleView: UIView {
    enum Side { case left, right }
    let textID: UUID
    let side: Side

    init(textID: UUID, side: Side) {
        self.textID = textID
        self.side = side
        super.init(frame: .zero)
        isUserInteractionEnabled = true
        backgroundColor = .white
        layer.borderColor = UIColor.systemBlue.cgColor
        layer.borderWidth = 1.0
        layer.cornerRadius = 6   // perfect circle at 12×12
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.2
        layer.shadowRadius = 1.5
        layer.shadowOffset = .zero
    }

    /// Expand hit area so thin handles are easy to grab.
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        bounds.insetBy(dx: -10, dy: -10).contains(point)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }
}

final class ScorePDFTextBoxView: UIView {
    let textID: UUID
    let textView: UITextView

    init(textID: UUID) {
        self.textID = textID
        self.textView = UITextView()
        super.init(frame: .zero)
        isUserInteractionEnabled = true
        backgroundColor = .clear

        textView.backgroundColor = .clear
        textView.isScrollEnabled = false
        textView.isEditable = false
        textView.isSelectable = false
        textView.textContainerInset = UIEdgeInsets(top: 4, left: 4, bottom: 4, right: 4)
        textView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(textView)
        NSLayoutConstraint.activate([
            textView.leadingAnchor.constraint(equalTo: leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: trailingAnchor),
            textView.topAnchor.constraint(equalTo: topAnchor),
            textView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }
}
#endif
