import Combine
import Observation

#if os(iOS)

/// 모든 PageTurnInputProvider를 관리하고 이벤트를 단일 스트림으로 병합한다.
/// PDF 뷰어는 `pageEvents` 하나만 구독하면 된다.
@Observable
final class PageTurnManager {

    // MARK: - Settings

    var isEnabled: Bool = false {
        didSet { isEnabled ? activateCurrent() : deactivateAll() }
    }

    var activeSource: PageTurnInputSource = .faceGesture {
        didSet { guard isEnabled else { return }; switchSource() }
    }

    var faceGestureKind: FaceGestureKind = .wink {
        didSet { faceProvider.gestureKind = faceGestureKind }
    }

    /// 감도 0.0(민감)~1.0(둔감). 각 provider가 자체 스케일로 변환한다.
    var sensitivity: Double = 0.5 {
        didSet {
            faceProvider.sensitivity     = sensitivity
            airPodsProvider.sensitivity  = 0.2 + sensitivity * 0.4   // 0.2~0.6 rad
        }
    }

    // MARK: - Providers

    let faceProvider    = FaceGestureInputProvider()
    let airPodsProvider = AirPodsHeadGestureInputProvider()
    let keyboardProvider = KeyboardPageTurnInputProvider()

    // MARK: - Merged event stream

    private let eventSubject = PassthroughSubject<PageTurnEvent, Never>()

    /// 모든 입력 방식의 이벤트가 합쳐진 단일 스트림 (메인 스레드)
    var pageEvents: AnyPublisher<PageTurnEvent, Never> {
        eventSubject.eraseToAnyPublisher()
    }

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Init

    init() {
        // 각 provider 이벤트를 eventSubject로 병합
        for provider in allProviders {
            provider.events
                .sink { [weak self] event in self?.eventSubject.send(event) }
                .store(in: &cancellables)
        }
    }

    // MARK: - Activation

    private var allProviders: [any PageTurnInputProvider] {
        [faceProvider, airPodsProvider, keyboardProvider]
    }

    private func activateCurrent() {
        deactivateAll()
        switch activeSource {
        case .faceGesture:        faceProvider.activate()
        case .airPodsHeadGesture: airPodsProvider.activate()
        case .bluetoothPedal:     keyboardProvider.activate()
        }
    }

    private func deactivateAll() {
        allProviders.forEach { $0.deactivate() }
    }

    private func switchSource() {
        deactivateAll()
        activateCurrent()
    }

    // MARK: - Calibration

    func recalibrate() {
        switch activeSource {
        case .airPodsHeadGesture: airPodsProvider.recalibrate()
        default: break
        }
    }
}

#endif
