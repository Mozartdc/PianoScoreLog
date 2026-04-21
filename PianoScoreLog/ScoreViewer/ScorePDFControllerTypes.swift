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

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
#endif
