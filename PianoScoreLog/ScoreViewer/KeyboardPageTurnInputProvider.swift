import Combine

#if os(iOS)

/// HID 키보드형 Bluetooth 페달(PageFlip, AirTurn 등) 입력.
///
/// # HID vs BLE 구분
///
/// ## HID 방식 (이 클래스가 처리)
/// PageFlip Cicada, AirTurn PED 등 대부분의 악보 페달은
/// iOS에 Bluetooth Keyboard(HID)로 인식된다.
/// → 앱 내 페어링 로직 불필요. iOS 시스템 설정에서 페어링 후 자동 인식.
/// → UIKeyCommand만 오버라이드하면 끝.
///
/// ## BLE 커스텀 프로토콜 방식 (별도 구현 필요 시)
/// 제조사 전용 프로토콜을 사용하는 BLE 액세서리라면:
/// - iOS 18+: AccessorySetupKit으로 페어링 UI 제공 (권장)
/// - 실제 통신: CoreBluetooth CBPeripheral로 분리 구현
/// 현재는 지원하지 않음. HID 페달로 충분한 실사용 커버리지를 갖는다.
final class KeyboardPageTurnInputProvider: PageTurnInputProvider {

    let source: PageTurnInputSource = .bluetoothPedal

    /// HID 키보드는 항상 지원 (시스템이 처리)
    var isSupported: Bool { true }

    private(set) var isActive: Bool = false

    var events: AnyPublisher<PageTurnEvent, Never> { subject.eraseToAnyPublisher() }
    private let subject = PassthroughSubject<PageTurnEvent, Never>()

    func activate()   { isActive = true }
    func deactivate() { isActive = false }

    /// ScorePDFViewController의 UIKeyCommand 핸들러에서 호출.
    /// provider가 비활성 상태면 이벤트를 방출하지 않는다.
    func send(_ event: PageTurnEvent) {
        guard isActive else { return }
        subject.send(event)
    }
}

#endif
