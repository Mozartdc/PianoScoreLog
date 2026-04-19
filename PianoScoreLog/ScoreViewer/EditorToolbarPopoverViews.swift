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
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHGrid(rows: rows, spacing: 8) {
                    ForEach(ScoreEditorState.stickerSymbols) { symbol in
                        Button {
                            state.selectedStickerSymbolID = symbol.id
                        } label: {
                            stickerPaletteGlyph(
                                for: symbol,
                                color: state.selectedStickerSymbolID == symbol.id ? Color.accentColor : Color.primary
                            )
                            .frame(width: 44, height: 34)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(state.selectedStickerSymbolID == symbol.id
                                          ? Color.accentColor.opacity(0.14) : Color.clear)
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
            }
            .frame(height: 84)

            Divider()

            HStack(spacing: 0) {
                if let symbol = selectedSymbol {
                    stickerPaletteGlyph(for: symbol, color: Color(state.stickerColor))
                        .frame(width: 44, height: 48)
                        .frame(width: 52)
                    Divider()
                }

                HStack(spacing: 6) {
                    let recent = Array(state.recentColors.prefix(3))
                    ForEach(0..<3, id: \.self) { index in
                        if index < recent.count {
                            let color = recent[index]
                            Button {
                                state.stickerColor = color
                                state.selectDrawingColor(color)
                            } label: {
                                Circle()
                                    .fill(color)
                                    .frame(width: 22, height: 22)
                                    .overlay(Circle().stroke(Color.primary.opacity(0.15), lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        } else {
                            Color.clear.frame(width: 22, height: 22)
                        }
                    }
                    ColorPicker(
                        "",
                        selection: Binding(
                            get: { state.stickerColor },
                            set: { state.stickerColor = $0; state.selectDrawingColor($0) }
                        ),
                        supportsOpacity: false
                    )
                    .labelsHidden()
                }
                .padding(.horizontal, 10)

                Divider()

                HStack(spacing: 6) {
                    Text("크기")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Slider(value: $state.stickerScale, in: 0.2...3.0)
                        .frame(width: 100)
                    Button {
                        state.stickerScale = 0.5
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 10)

                Divider()

                HStack(spacing: 6) {
                    Text("투명")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Slider(value: $state.stickerOpacity, in: 0.1...1.0)
                        .frame(width: 90)
                }
                .padding(.horizontal, 10)
            }
            .frame(height: 48)
        }
    }

    private var selectedSymbol: StickerSymbol? {
        guard let id = state.selectedStickerSymbolID else { return nil }
        return ScoreEditorState.stickerSymbols.first(where: { $0.id == id })
    }

    @ViewBuilder
    private func stickerPaletteGlyph(for symbol: StickerSymbol, color: Color) -> some View {
        let paletteBox = CGSize(width: 34, height: 26)
        if let image = renderedStickerPaletteImage(
            symbolID: symbol.id,
            value: symbol.value,
            color: UIColor(color),
            canvasSize: paletteBox,
            fillRatio: max(0.10, min(0.95, 0.74 * stickerPaletteFineTuneMultiplier(symbolID: symbol.id)))
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
#endif
