import SwiftUI
import PDFKit
import Observation

#if os(iOS)
struct ScoreViewerScreen: View {
    let piece: Piece
    let pdfURL: URL
    let editorState: ScoreEditorState
    var totalBarBottom: CGFloat = 0
    var onRequestOpenPanel: () -> Void = {}
    @State private var viewerPageIndex: Int
    @State private var viewerPageCount: Int = 0

    init(piece: Piece, pdfURL: URL,
         editorState: ScoreEditorState,
         totalBarBottom: CGFloat = 0,
         onRequestOpenPanel: @escaping () -> Void = {}) {
        self.piece = piece
        self.pdfURL = pdfURL
        self.editorState = editorState
        self.totalBarBottom = totalBarBottom
        self.onRequestOpenPanel = onRequestOpenPanel
        _viewerPageIndex = State(initialValue: max(0, piece.lastViewedPage))
    }

    var body: some View {
#if os(iOS)
        ZStack(alignment: .top) {
            let pdfView = ScorePDFView(
                pieceID: piece.id,
                pdfURL: pdfURL,
                pageIndex: Binding(
                    get: { viewerPageIndex },
                    set: { viewerPageIndex = $0 }
                ),
                pageCount: Binding(
                    get: { viewerPageCount },
                    set: { viewerPageCount = $0 }
                ),
                isEditorMode: editorState.isEditorMode,
                isDrawingEnabled: editorState.activeDrawingTool != nil
                    && editorState.isLayerPanelPresented == false
                    && (editorState.activeLayer?.isVisible ?? false),
                annotationLayers: editorState.annotationLayers,
                activeLayerID: editorState.activeLayerID,
                selectedTool: resolvedDrawingTool(editorState.activeDrawingTool),
                selectedColor: editorState.selectedDrawingColor,
                strokeWidth: editorState.strokeWidth,
                strokeOpacity: editorState.strokeOpacity,
                eraserMode: editorState.eraserMode,
                eraserSize: editorState.eraserSize,
                selectedStickerSymbolID: editorState.selectedStickerSymbolID,
                stickerColor: editorState.stickerColor,
                stickerScale: editorState.stickerScale,
                stickerOpacity: editorState.stickerOpacity,
                deleteStickerTrigger: editorState.deleteStickerTrigger,
                toolbarHeight: editorState.isEditorMode ? totalBarBottom : 0,
                undoTrigger: editorState.undoTrigger,
                redoTrigger: editorState.redoTrigger,
                prevPageTrigger: editorState.prevPageTrigger,
                nextPageTrigger: editorState.nextPageTrigger,
                onCanvasTap: handleCanvasTap,
                onStickerSelectionChanged: { isSelected in
                    editorState.hasSelectedSticker = isSelected
                },
                onLayerConfigurationChanged: { layers, active in
                    editorState.setLayers(layers, activeLayerID: active)
                }
            )
            pdfView

            if editorState.isEditorMode {
                EditorTopBarOverlay(
                    state: editorState,
                    onRequestOpenPanel: onRequestOpenPanel,
                    onDone: {
                        withAnimation(.spring()) {
                            editorState.isEditorMode = false
                            editorState.isFullScreenMode = true
                        }
                    }
                )
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(10)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: viewerPageIndex) { _, newValue in
            editorState.currentPageIndex = newValue
        }
        .onChange(of: viewerPageCount) { _, newValue in
            editorState.pageCount = newValue
        }
        .onAppear {
            editorState.currentPageIndex = viewerPageIndex
            editorState.pageCount = viewerPageCount
        }
        .animation(.spring(), value: editorState.isEditorMode)
        .onDisappear {
            let safeIndex = max(0, min(viewerPageIndex, max(0, viewerPageCount - 1)))
            piece.lastViewedPage = safeIndex
        }
#else
        VStack(spacing: 12) {
            Text("이 플랫폼에서는 iOS PDF 뷰어를 사용할 수 없습니다.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text(pdfURL.lastPathComponent)
                .font(.footnote)
        }
        .padding()
#endif
    }

    private func resolvedDrawingTool(_ tool: DrawingTool?) -> DrawingToolMode {
        switch tool {
        case .pencil: return .pencil
        case .highlighter: return .marker
        case .eraser: return .eraser
        case .sticker: return .sticker
        case .text: return .text
        default: return .pen
        }
    }

    private func handleCanvasTap() {
        withAnimation(.spring()) {
            if !editorState.isEditorMode {
                editorState.isFullScreenMode = false
                editorState.isEditorMode = true
                editorState.activeDrawingTool = nil
                return
            }
        }
    }
}
#endif
