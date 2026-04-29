import CoreMotion
import Combine

#if os(iOS)

/// CMHeadphoneMotionManager 기반 AirPods 머리 제스처 입력.
/// 머리 좌우 회전으로 이전/다음 페이지를 전환한다.
final class AirPodsHeadGestureInputProvider: PageTurnInputProvider {

    let source: PageTurnInputSource = .airPodsHeadGesture

    /// 호환 AirPods(Pro, Max, 3세대 이상)가 현재 연결된 경우에만 true
    /// isDeviceMotionAvailable은 인스턴스 프로퍼티 — manager로 확인
    var isSupported: Bool { manager.isDeviceMotionAvailable }

    private(set) var isActive: Bool = false

    /// 감도 — 페이지 전환을 트리거할 yaw 변화량 (라디안)
    var sensitivity: Double = 0.35

    var events: AnyPublisher<PageTurnEvent, Never> { subject.eraseToAnyPublisher() }
    private let subject = PassthroughSubject<PageTurnEvent, Never>()

    private let manager = CMHeadphoneMotionManager()
    private var lastFireDate: Date = .distantPast
    private let cooldown: TimeInterval = 1.5

    /// 활성화 시점의 yaw 기준값 (캘리브레이션)
    private var referenceYaw: Double?

    // MARK: - Activation

    func activate() {
        guard isSupported, !isActive else { return }
        // CMHeadphoneMotionManager는 Motion & Fitness 권한을 자동 요청한다.
        // Info.plist의 NSMotionUsageDescription 필수.
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, error in
            guard let self, let motion, error == nil else { return }
            self.handleMotion(motion)
        }
        isActive = true
    }

    func deactivate() {
        manager.stopDeviceMotionUpdates()
        referenceYaw = nil
        isActive = false
    }

    // MARK: - Motion handling

    private func handleMotion(_ motion: CMDeviceMotion) {
        // 첫 데이터로 기준 yaw 설정 (캘리브레이션)
        if referenceYaw == nil { referenceYaw = motion.attitude.yaw }
        guard let ref = referenceYaw else { return }

        let now = Date()
        guard now.timeIntervalSince(lastFireDate) > cooldown else { return }

        let delta = motion.attitude.yaw - ref
        if delta > sensitivity {
            fire(now, event: .nextPage)
            referenceYaw = motion.attitude.yaw   // 기준 재설정
        } else if delta < -sensitivity {
            fire(now, event: .previousPage)
            referenceYaw = motion.attitude.yaw
        }
    }

    private func fire(_ date: Date, event: PageTurnEvent) {
        lastFireDate = date
        subject.send(event)
    }

    // MARK: - Calibration

    /// 현재 머리 위치를 기준으로 재캘리브레이션
    func recalibrate() {
        referenceYaw = nil
    }
}

#endif
