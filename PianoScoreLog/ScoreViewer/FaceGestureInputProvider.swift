import ARKit
import AVFoundation
import Combine

#if os(iOS)

/// ARKit ARFaceTrackingConfiguration 기반 얼굴 제스처 입력.
/// 카메라 세션·얼굴 추적·BlendShape 계산은 ARKit이 담당한다.
/// 이 클래스는 어떤 값이 임계치를 넘으면 어떤 이벤트를 방출할지만 정의한다.
final class FaceGestureInputProvider: NSObject, PageTurnInputProvider, ARSessionDelegate {

    let source: PageTurnInputSource = .faceGesture

    /// TrueDepth(Face ID) 카메라 탑재 기기에서만 지원
    static var isSupported: Bool { ARFaceTrackingConfiguration.isSupported }
    var isSupported: Bool { Self.isSupported }

    private(set) var isActive: Bool = false

    /// 감지할 얼굴 제스처 종류
    var gestureKind: FaceGestureKind = .wink

    /// 감도 (0.0~1.0). 높을수록 더 강한 움직임이 필요 (오감지 억제)
    var sensitivity: Double = 0.7

    var events: AnyPublisher<PageTurnEvent, Never> { subject.eraseToAnyPublisher() }
    private let subject = PassthroughSubject<PageTurnEvent, Never>()

    private let session = ARSession()
    private var lastFireDate: Date = .distantPast
    private let cooldown: TimeInterval = 1.2   // 연속 트리거 방지

    override init() {
        super.init()
        session.delegate = self
    }

    // MARK: - Activation

    func activate() {
        guard isSupported, !isActive else { return }
        requestCameraPermissionAndStart()
    }

    func deactivate() {
        session.pause()
        isActive = false
    }

    // MARK: - Camera permission

    private func requestCameraPermissionAndStart() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            startSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                guard granted else { return }
                DispatchQueue.main.async { self?.startSession() }
            }
        default:
            // 권한 거부 — UI 레이어에서 설정 앱 안내
            break
        }
    }

    private func startSession() {
        session.run(ARFaceTrackingConfiguration(), options: [])
        isActive = true
    }

    // MARK: - ARSessionDelegate

    func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        guard let face = anchors.first as? ARFaceAnchor else { return }
        let now = Date()
        guard now.timeIntervalSince(lastFireDate) > cooldown else { return }

        let s = face.blendShapes
        let threshold = Float(sensitivity)

        switch gestureKind {
        case .wink:
            // 윙크는 눈 크기에 따라 최대값이 다르므로 threshold를 낮게 스케일
            // sensitivity 0.5 기준 → 실제 임계값 0.4
            let winkThreshold = threshold * 0.8
            // 반대쪽 눈 조건: 완전히 뜬 상태(< threshold)만 요구 — 너무 엄격하면 인식 실패
            let l = s[.eyeBlinkLeft]?.floatValue  ?? 0
            let r = s[.eyeBlinkRight]?.floatValue ?? 0
            if l > winkThreshold, r < threshold {
                fire(now, event: .previousPage)
            } else if r > winkThreshold, l < threshold {
                fire(now, event: .nextPage)
            }

        case .lips:
            let left  = s[.mouthLeft]?.floatValue  ?? 0
            let right = s[.mouthRight]?.floatValue ?? 0
            if left > threshold, right < threshold * 0.6 {
                fire(now, event: .previousPage)
            } else if right > threshold, left < threshold * 0.6 {
                fire(now, event: .nextPage)
            }
        }
    }

    private func fire(_ date: Date, event: PageTurnEvent) {
        lastFireDate = date
        DispatchQueue.main.async { [weak self] in self?.subject.send(event) }
    }
}

#endif
