import SwiftUI
import Observation
#if os(iOS)
import UIKit

struct DrawingToolOptionsPopoverView: View {
    @Bindable var state: ScoreEditorState
    let tool: DrawingTool

    var body: some View {
        switch tool {
        case .pen, .pencil, .highlighter:
            VStack(alignment: .leading, spacing: 14) {
                let recent = Array(state.recentColors.prefix(5))
                HStack(spacing: 8) {
                    ForEach(0..<5, id: \.self) { index in
                        if index < recent.count {
                            let color = recent[index]
                            Button {
                                state.selectDrawingColor(color)
                            } label: {
                                Circle()
                                    .fill(color)
                                    .frame(width: 26, height: 26)
                                    .overlay(Circle().stroke(Color.primary.opacity(0.15), lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                            .frame(maxWidth: .infinity)
                        } else {
                            Color.clear
                                .frame(width: 26, height: 26)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    ColorPicker(
                        "",
                        selection: Binding(
                            get: { state.selectedDrawingColor },
                            set: { state.selectDrawingColor($0) }
                        ),
                        supportsOpacity: false
                    )
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity)

                Divider()
                LabeledContent("굵기") {
                    Slider(value: $state.strokeWidth, in: 1...16)
                        .frame(width: 160)
                }
                LabeledContent("불투명도") {
                    Slider(value: $state.strokeOpacity, in: 0.1...1)
                        .frame(width: 160)
                }
            }
            .frame(width: 280)
        case .eraser:
            VStack(alignment: .leading, spacing: 14) {
                Picker("지우기 방식", selection: $state.eraserMode) {
                    Text("영역").tag(EraserMode.bitmap)
                    Text("획").tag(EraserMode.vector)
                }
                .pickerStyle(.segmented)
                LabeledContent("크기") {
                    Slider(value: $state.eraserSize, in: 0...1)
                        .frame(width: 160)
                }
            }
            .padding(.horizontal, 12)
            .frame(width: 220)
        default:
            EmptyView()
        }
    }
}

struct LayerManagerPopover: View {
    @Bindable var state: ScoreEditorState
    @State private var renamingLayerID: UUID?
    @State private var layerNameDraft: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("레이어")
                .font(.headline)

            List {
                ForEach(state.annotationLayers) { layer in
                    LayerManagerRow(
                        isActive: state.activeLayerID == layer.id,
                        isVisible: layer.isVisible,
                        name: state.annotationLayers.first(where: { $0.id == layer.id })?.name ?? "",
                        onSelect: { state.setActiveLayer(layer.id) },
                        onToggleVisible: { state.toggleLayerVisibility(layer.id) },
                        onRename: {
                            renamingLayerID = layer.id
                            layerNameDraft = layer.name
                            state.isLayerPanelPresented = true
                        }
                    )
                }
            }
            .listStyle(.inset)

            HStack(spacing: 12) {
                Button {
                    state.addLayer()
                } label: {
                    Label("레이어 추가", systemImage: "plus")
                }

                Button(role: .destructive) {
                    state.removeActiveLayer()
                } label: {
                    Label("활성 레이어 삭제", systemImage: "trash")
                }
                .disabled(state.annotationLayers.count <= 1)
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .alert("레이어 이름 변경", isPresented: Binding(
            get: { renamingLayerID != nil },
            set: { shown in
                if !shown { renamingLayerID = nil }
            }
        )) {
            TextField("이름", text: $layerNameDraft)
            Button("취소", role: .cancel) { renamingLayerID = nil }
            Button("저장") {
                if let id = renamingLayerID {
                    state.renameLayer(id, name: layerNameDraft.trimmingCharacters(in: .whitespacesAndNewlines))
                }
                renamingLayerID = nil
            }
        }
    }
}

private struct LayerManagerRow: View {
    let isActive: Bool
    let isVisible: Bool
    let name: String
    let onSelect: () -> Void
    let onToggleVisible: () -> Void
    let onRename: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onSelect) {
                Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)

            Text(name)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: onRename) {
                Image(systemName: "pencil")
                    .foregroundStyle(Color.secondary)
            }
            .buttonStyle(.plain)

            Button(action: onToggleVisible) {
                Image(systemName: isVisible ? "eye" : "eye.slash")
                    .foregroundStyle(Color.secondary)
            }
            .buttonStyle(.plain)
        }
    }
}

struct StickerTrayView: View {
    @Bindable var state: ScoreEditorState
    private let rows = [GridItem(.fixed(34), spacing: 8), GridItem(.fixed(34), spacing: 8)]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ColorPicker(
                    "",
                    selection: Binding(
                        get: { state.stickerColor },
                        set: { state.stickerColor = $0; state.selectDrawingColor($0) }
                    ),
                    supportsOpacity: false
                )
                .labelsHidden()
                .frame(width: 52)
                .frame(maxHeight: .infinity)

                Divider()
                    .padding(.vertical, 12)

                LazyHGrid(rows: rows, spacing: 8) {
                    ForEach(ScoreEditorState.stickerSymbols) { symbol in
                        Button {
                            state.selectedStickerSymbolID = symbol.id
                        } label: {
                            stickerPaletteGlyph(
                                for: symbol,
                                color: Color.primary
                            )
                            .frame(width: 44, height: 34)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(state.selectedStickerSymbolID == symbol.id
                                          ? Color(uiColor: .tertiarySystemFill) : Color.clear)
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
            }
        }
        .frame(height: 84)
    }

    @ViewBuilder
    private func stickerPaletteGlyph(for symbol: StickerSymbol, color: Color) -> some View {
        let paletteBox = CGSize(width: 34, height: 26)
        if let image = renderedStickerPaletteImage(
            symbolID: symbol.id,
            value: symbol.value,
            color: UIColor(color),
            canvasSize: paletteBox,
            fillRatio: max(0.10, min(0.95, 0.74 * stickerPaletteFineTuneMultiplier(symbolID: symbol.id) * stickerSizeScale(symbolID: symbol.id)))
        ) {
            Image(uiImage: image)
                .interpolation(.high)
                .resizable()
                .frame(width: paletteBox.width, height: paletteBox.height, alignment: .center)
        } else {
            Color.clear.frame(width: paletteBox.width, height: paletteBox.height)
        }
    }
}
/// 핸즈프리 페이지 넘김 설정 팝오버.
/// preferredContentSize 고정 (sizingOptions 미사용) — @Observable 피드백 루프 방지.
struct HandsFreeSettingsView: View {
    @Bindable var manager: PageTurnManager

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // ── 활성화 토글 ──────────────────────────────
            Toggle(isOn: $manager.isEnabled) {
                Label("핸즈프리 페이지 넘김", systemImage: "hand.wave")
                    .font(.subheadline.weight(.medium))
            }
            .tint(.accentColor)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            // ── 입력 방식 ────────────────────────────────
            VStack(alignment: .leading, spacing: 10) {
                Text("입력 방식")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                HStack(spacing: 6) {
                    ForEach(PageTurnInputSource.allCases) { src in
                        SourceSegmentButton(
                            source: src,
                            isSelected: manager.activeSource == src
                        ) { manager.activeSource = src }
                    }
                }
                .disabled(!manager.isEnabled)

                if manager.isEnabled {
                    supportBadge(for: manager.activeSource)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

            // ── 방식별 세부 설정 ─────────────────────────
            Group {
                switch manager.activeSource {
                case .faceGesture:
                    faceGestureSection
                case .airPodsHeadGesture:
                    airPodsSection
                case .bluetoothPedal:
                    bluetoothSection
                }
            }
            .disabled(!manager.isEnabled)
        }
    }

    // MARK: - Face Gesture

    private var faceGestureSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("제스처 종류")
                .font(.footnote)
                .foregroundStyle(.secondary)

            HStack(spacing: 6) {
                ForEach(FaceGestureKind.allCases) { kind in
                    GestureKindSegmentButton(
                        kind: kind,
                        isSelected: manager.faceGestureKind == kind
                    ) { manager.faceGestureKind = kind }
                }
            }

            Text(manager.faceGestureKind.hint)
                .font(.footnote)
                .foregroundStyle(.secondary)

            sensitivityRow
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - AirPods

    private var airPodsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("고개를 왼쪽/오른쪽으로 돌려 페이지를 넘깁니다.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            sensitivityRow

            Button {
                manager.recalibrate()
            } label: {
                Label("현재 위치로 캘리브레이션", systemImage: "arrow.triangle.2.circlepath")
                    .font(.footnote)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Bluetooth

    private var bluetoothSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Bluetooth 페달 연결", systemImage: "cable.connector.horizontal")
                .font(.footnote.weight(.medium))
            Text("PageFlip · AirTurn 등 HID 방식 페달은\niOS 설정 앱에서 블루투스 페어링만 하면\n별도 설정 없이 자동 인식됩니다.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Shared

    private var sensitivityRow: some View {
        LabeledContent("감도") {
            Slider(value: $manager.sensitivity, in: 0.3...1.0)
                .frame(width: 130)
        }
        .font(.footnote)
    }

    @ViewBuilder
    private func supportBadge(for source: PageTurnInputSource) -> some View {
        let supported: Bool = {
            switch source {
            case .faceGesture:        return manager.faceProvider.isSupported
            case .airPodsHeadGesture: return manager.airPodsProvider.isSupported
            case .bluetoothPedal:     return true
            }
        }()
        Label(
            supported ? "이 기기에서 지원됩니다" : "이 기기에서 지원되지 않습니다",
            systemImage: supported ? "checkmark.circle" : "exclamationmark.triangle"
        )
        .font(.caption)
        .foregroundStyle(supported ? Color.green : Color.orange)
    }
}

// MARK: - Source Segment Button

private struct SourceSegmentButton: View {
    let source: PageTurnInputSource
    let isSelected: Bool
    let action: () -> Void

    private var symbol: String {
        switch source {
        case .faceGesture:        return "faceid"
        case .airPodsHeadGesture: return "airpods"
        case .bluetoothPedal:     return "cable.connector.horizontal"
        }
    }

    private var shortLabel: String {
        switch source {
        case .faceGesture:        return "얼굴"
        case .airPodsHeadGesture: return "AirPods"
        case .bluetoothPedal:     return "페달"
        }
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.title3)
                Text(shortLabel)
                    .font(.caption)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected
                          ? Color.accentColor.opacity(0.12)
                          : Color(uiColor: .tertiarySystemFill))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1.5)
            )
            .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Gesture Kind Segment Button

private struct GestureKindSegmentButton: View {
    let kind: FaceGestureKind
    let isSelected: Bool
    let action: () -> Void

    private var symbol: String {
        switch kind {
        case .wink: return "eye"
        case .lips: return "mouth"
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.body)
                Text(kind.rawValue)
                    .font(.subheadline)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected
                          ? Color.accentColor.opacity(0.12)
                          : Color(uiColor: .tertiarySystemFill))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1.5)
            )
            .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
        }
        .buttonStyle(.plain)
    }
}

struct PageJumpPopoverView: View {
    let currentPage: Int
    let totalPages: Int
    let onJump: (Int) -> Void

    @State private var text = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        HStack(spacing: 8) {
            TextField("\(currentPage)", text: $text)
                .keyboardType(.numberPad)
                .textFieldStyle(.roundedBorder)
                .frame(width: 72)
            Text("/ \(totalPages)")
                .foregroundStyle(.secondary)
            Button("이동") {
                if let n = Int(text) { onJump(n) }
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding()
    }
}

#endif
