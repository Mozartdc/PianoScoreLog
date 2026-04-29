import Combine

// MARK: - Event

/// 페이지 넘김 방향
enum PageTurnEvent {
    case nextPage
    case previousPage
}

// MARK: - Source

/// 지원하는 입력 방식
enum PageTurnInputSource: String, CaseIterable, Identifiable {
    case faceGesture        = "얼굴 제스처"
    case airPodsHeadGesture = "AirPods 머리 제스처"
    case bluetoothPedal     = "Bluetooth 페달"
    var id: String { rawValue }
}

/// 얼굴 제스처 종류
enum FaceGestureKind: String, CaseIterable, Identifiable {
    case wink = "윙크"
    case lips = "입술"
    var id: String { rawValue }

    var hint: String {
        switch self {
        case .wink: return "왼쪽 윙크 → 이전  /  오른쪽 윙크 → 다음"
        case .lips: return "입 왼쪽 → 이전  /  입 오른쪽 → 다음"
        }
    }
}

// MARK: - Protocol

/// 모든 핸즈프리 입력 방식이 따르는 공통 프로토콜.
/// PDF 뷰어는 이 프로토콜의 `events` 스트림만 구독한다.
protocol PageTurnInputProvider: AnyObject {
    var source: PageTurnInputSource { get }

    /// 현재 기기·환경에서 이 입력 방식을 사용할 수 있는지
    var isSupported: Bool { get }

    /// 현재 활성화되어 이벤트를 방출 중인지
    var isActive: Bool { get }

    /// .nextPage / .previousPage 이벤트 스트림 (메인 스레드에서 방출)
    var events: AnyPublisher<PageTurnEvent, Never> { get }

    func activate()
    func deactivate()
}
