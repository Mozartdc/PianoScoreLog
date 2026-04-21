import SwiftUI
#if os(iOS)
import UIKit
#endif
import Observation

struct AnnotationLayer: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var isVisible: Bool

    init(id: UUID = UUID(), name: String, isVisible: Bool = true) {
        self.id = id
        self.name = name
        self.isVisible = isVisible
    }
}

struct StickerPlacement: Identifiable, Codable, Equatable {
    let id: UUID
    var symbolID: String
    var text: String
    var pageIndex: Int
    var layerID: UUID
    var normalizedX: Double
    var normalizedY: Double
    var scale: Double
    var colorHex: String
    var opacity: Double

    private enum CodingKeys: String, CodingKey {
        case id
        case symbolID
        case text
        case pageIndex
        case layerID
        case normalizedX
        case normalizedY
        case scale
        case colorHex
        case opacity
    }

    init(
        id: UUID = UUID(),
        symbolID: String,
        text: String,
        pageIndex: Int,
        layerID: UUID,
        normalizedX: Double,
        normalizedY: Double,
        scale: Double,
        colorHex: String,
        opacity: Double = 1.0
    ) {
        self.id = id
        self.symbolID = symbolID
        self.text = text
        self.pageIndex = pageIndex
        self.layerID = layerID
        self.normalizedX = normalizedX
        self.normalizedY = normalizedY
        self.scale = scale
        self.colorHex = colorHex
        self.opacity = opacity
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        symbolID = try c.decode(String.self, forKey: .symbolID)
        text = try c.decode(String.self, forKey: .text)
        pageIndex = try c.decode(Int.self, forKey: .pageIndex)
        layerID = try c.decode(UUID.self, forKey: .layerID)
        normalizedX = try c.decode(Double.self, forKey: .normalizedX)
        normalizedY = try c.decode(Double.self, forKey: .normalizedY)
        scale = try c.decode(Double.self, forKey: .scale)
        colorHex = try c.decode(String.self, forKey: .colorHex)
        opacity = try c.decodeIfPresent(Double.self, forKey: .opacity) ?? 1.0
    }
}

struct StickerSymbol: Identifiable, Equatable {
    let id: String
    let value: String
}

@Observable
final class ScoreEditorState {
    private struct RGBAColor: Codable, Equatable {
        let r: Double
        let g: Double
        let b: Double
        let a: Double

        init?(color: Color) {
#if os(iOS)
            let uiColor = UIColor(color)
            var red: CGFloat = 0
            var green: CGFloat = 0
            var blue: CGFloat = 0
            var alpha: CGFloat = 0
            guard uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return nil }
            self.r = Double(red)
            self.g = Double(green)
            self.b = Double(blue)
            self.a = Double(alpha)
#else
            return nil
#endif
        }

        var color: Color {
            Color(.sRGB, red: r, green: g, blue: b, opacity: a)
        }
    }

    private enum StorageKey {
        static let recentColors = "score_editor_recent_colors_v1"
    }

    private static let maxRecentColorCount = 8

    var isEditorMode: Bool = false
    var isFullScreenMode: Bool = false
    var activeDrawingTool: DrawingTool? = nil
    var selectedDrawingColor: Color = .black
    var recentColors: [Color] = []
    var stickerColor: Color = .black
    var stickerScale: CGFloat = 0.5
    var selectedStickerSymbolID: String? = nil
    var hasSelectedSticker: Bool = false
    var deleteStickerTrigger: Int = 0
    var strokeWidth: CGFloat = 4
    var strokeOpacity: CGFloat = 1
    var stickerOpacity: CGFloat = 1.0
#if os(iOS)
    var eraserMode: EraserMode = .bitmap
#endif
    var eraserSize: CGFloat = 0.5
    var undoTrigger: Int = 0
    var redoTrigger: Int = 0
    var prevPageTrigger: Int = 0
    var nextPageTrigger: Int = 0
    var jumpToPageTrigger: Int = 0
    var jumpToPageTarget: Int = 0
    var currentPageIndex: Int = 0
    var pageCount: Int = 0
    var isLayerPanelPresented: Bool = false
    var annotationLayers: [AnnotationLayer] = [AnnotationLayer(name: "레이어 1", isVisible: true)]
    var activeLayerID: UUID? = nil
    private var recentColorEntries: [RGBAColor] = []

    static let stickerSymbols: [StickerSymbol] = [
        StickerSymbol(id: "trebleClef", value: "U+E050"),
        StickerSymbol(id: "bassClef", value: "U+E062"),
        StickerSymbol(id: "fingering1", value: "U+EA71"),
        StickerSymbol(id: "fingering2", value: "U+EA72"),
        StickerSymbol(id: "fingering3", value: "U+EA73"),
        StickerSymbol(id: "fingering4", value: "U+EA74"),
        StickerSymbol(id: "fingering5", value: "U+EA75"),
        StickerSymbol(id: "check", value: "U+E4CF"),
        StickerSymbol(id: "pedalMark", value: "U+1D1AE"),
        StickerSymbol(id: "pedalUpMark", value: "U+1D1AF"),
        // Dynamics
        StickerSymbol(id: "dynamicP", value: "U+E520"),
        StickerSymbol(id: "dynamicPP", value: "U+E52B"),
        StickerSymbol(id: "dynamicPPP", value: "U+E52A"),
        StickerSymbol(id: "dynamicMP", value: "U+E52C"),
        StickerSymbol(id: "dynamicMF", value: "U+E52D"),
        StickerSymbol(id: "dynamicF", value: "U+E522"),
        StickerSymbol(id: "dynamicFF", value: "U+E52F"),
        StickerSymbol(id: "dynamicFFF", value: "U+E530"),
        StickerSymbol(id: "sfz", value: "U+E539"),
        StickerSymbol(id: "eyeWarning", value: "SF:exclamationmark.triangle"),
        StickerSymbol(id: "cresc", value: "U+E53E"),
        StickerSymbol(id: "dim", value: "U+E53F"),
        // Articulation / ornaments
        StickerSymbol(id: "accent", value: "U+E4A0"),
        StickerSymbol(id: "staccato", value: "U+E4A2"),
        StickerSymbol(id: "marcato", value: "U+E4AC"),
        StickerSymbol(id: "fermata", value: "U+E4C0"),
        StickerSymbol(id: "trill", value: "U+E566"),
        StickerSymbol(id: "ornament56C", value: "U+E56C"),
        StickerSymbol(id: "ornament56D", value: "U+E56D"),
        StickerSymbol(id: "mordent", value: "U+E56E"),
        // Repeats / directions
        StickerSymbol(id: "segno", value: "U+E047"),
        StickerSymbol(id: "coda", value: "U+E048"),
        StickerSymbol(id: "repeatStart", value: "U+E040"),
        StickerSymbol(id: "repeatEnd", value: "U+E041"),
        StickerSymbol(id: "DC", value: "D.C."),
        StickerSymbol(id: "DS", value: "D.S."),
        StickerSymbol(id: "fine", value: "fine"),
        StickerSymbol(id: "rit", value: "rit."),
        StickerSymbol(id: "aTempo", value: "a tempo"),
        StickerSymbol(id: "rall", value: "rall."),
        // Accidentals
        StickerSymbol(id: "sharp", value: "U+E262"),
        StickerSymbol(id: "flat", value: "U+E260"),
        StickerSymbol(id: "doubleSharp", value: "U+E263"),
        StickerSymbol(id: "doubleFlat", value: "U+E264"),
        StickerSymbol(id: "natural", value: "U+E261"),
        // Octave / notes / rests
        StickerSymbol(id: "octave8va", value: "U+E511"),
        StickerSymbol(id: "wholeNote", value: "U+E1D2"),
        StickerSymbol(id: "halfNote", value: "U+E1D3"),
        StickerSymbol(id: "quarterNote", value: "U+E1D5"),
        StickerSymbol(id: "eighthNote", value: "U+E1D7"),
        StickerSymbol(id: "sixteenthNote", value: "U+E1D9"),
        StickerSymbol(id: "wholeRest", value: "U+E4E3"),
        StickerSymbol(id: "halfRest", value: "U+E4E4"),
        StickerSymbol(id: "quarterRest", value: "U+E4E5"),
        StickerSymbol(id: "eighthRest", value: "U+E4E6"),
        StickerSymbol(id: "sixteenthRest", value: "U+E4E7")
    ]

    init() {
        loadRecentColors()
        if let first = recentColors.first {
            selectedDrawingColor = first
            stickerColor = first
        } else {
            selectDrawingColor(.black)
        }
        activeLayerID = annotationLayers.first?.id
    }

    var activeLayer: AnnotationLayer? {
        guard let id = activeLayerID else { return nil }
        return annotationLayers.first(where: { $0.id == id })
    }

    func addLayer() {
        let nextIndex = annotationLayers.count + 1
        let layer = AnnotationLayer(name: "레이어 \(nextIndex)", isVisible: true)
        annotationLayers.append(layer)
        activeLayerID = layer.id
    }

    func removeActiveLayer() {
        guard let activeLayerID else { return }
        guard annotationLayers.count > 1 else { return }
        annotationLayers.removeAll { $0.id == activeLayerID }
        self.activeLayerID = annotationLayers.first?.id
        ensureValidLayerSelection()
    }

    func setActiveLayer(_ id: UUID) {
        guard annotationLayers.contains(where: { $0.id == id }) else { return }
        activeLayerID = id
    }

    func renameLayer(_ id: UUID, name: String) {
        guard let idx = annotationLayers.firstIndex(where: { $0.id == id }) else { return }
        annotationLayers[idx].name = name.isEmpty ? "레이어" : name
    }

    func toggleLayerVisibility(_ id: UUID) {
        guard let idx = annotationLayers.firstIndex(where: { $0.id == id }) else { return }
        annotationLayers[idx].isVisible.toggle()
        ensureValidLayerSelection()
    }

    func setLayers(_ layers: [AnnotationLayer], activeLayerID: UUID?) {
        if layers.isEmpty {
            annotationLayers = [AnnotationLayer(name: "레이어 1", isVisible: true)]
            self.activeLayerID = annotationLayers.first?.id
            return
        }
        annotationLayers = layers
        self.activeLayerID = activeLayerID
        ensureValidLayerSelection()
    }

    func ensureActiveLayerVisibleForDrawing() {
        guard let activeLayerID,
              let idx = annotationLayers.firstIndex(where: { $0.id == activeLayerID }) else { return }
        if annotationLayers[idx].isVisible == false {
            annotationLayers[idx].isVisible = true
        }
    }

    func selectDrawingColor(_ color: Color) {
        selectedDrawingColor = color
        stickerColor = color
        pushRecentColor(color)
    }

    private func ensureValidLayerSelection() {
        if annotationLayers.isEmpty {
            annotationLayers = [AnnotationLayer(name: "레이어 1", isVisible: true)]
        }
        if let activeLayerID,
           annotationLayers.contains(where: { $0.id == activeLayerID }) {
            return
        }
        activeLayerID = annotationLayers.first?.id
    }

    /// 탭 전환 시 호출 — 레이아웃 상태만 초기화, 사용자 설정(색상·굵기)은 유지
    func reset() {
        isEditorMode = false
        isFullScreenMode = false
        activeDrawingTool = nil
        hasSelectedSticker = false
        undoTrigger = 0
        redoTrigger = 0
        prevPageTrigger = 0
        nextPageTrigger = 0
        jumpToPageTrigger = 0
        jumpToPageTarget = 0
        currentPageIndex = 0
        pageCount = 0
        isLayerPanelPresented = false
        annotationLayers = [AnnotationLayer(name: "레이어 1", isVisible: true)]
        activeLayerID = annotationLayers.first?.id
    }

    private func loadRecentColors() {
        let decoder = JSONDecoder()
        if let data = UserDefaults.standard.data(forKey: StorageKey.recentColors),
           let decoded = try? decoder.decode([RGBAColor].self, from: data),
           decoded.isEmpty == false {
            recentColorEntries = Array(decoded.prefix(Self.maxRecentColorCount))
            recentColors = recentColorEntries.map(\.color)
            return
        }
        recentColorEntries = []
        recentColors = []
    }

    private func pushRecentColor(_ color: Color) {
        guard let rgba = RGBAColor(color: color) else { return }
        // 이미 있는 색상이면 제거 후 맨 앞으로 이동 — 최근 선택순 유지.
        recentColorEntries.removeAll { $0 == rgba }
        recentColorEntries.insert(rgba, at: 0)
        if recentColorEntries.count > Self.maxRecentColorCount {
            recentColorEntries = Array(recentColorEntries.prefix(Self.maxRecentColorCount))
        }
        recentColors = recentColorEntries.map(\.color)
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(recentColorEntries) {
            UserDefaults.standard.set(data, forKey: StorageKey.recentColors)
        }
    }
}
