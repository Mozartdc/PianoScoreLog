import SwiftUI
import PDFKit
import Combine
import Observation

#if os(iOS)
struct ScoreViewerScreen: View {
    let piece: Piece
    let pdfURL: URL
    let editorState: ScoreEditorState
    var totalBarBottom: CGFloat = 0
    let pageTurnManager: PageTurnManager
    @State private var viewerPageIndex: Int
    @State private var viewerPageCount: Int = 0

    init(piece: Piece, pdfURL: URL,
         editorState: ScoreEditorState,
         pageTurnManager: PageTurnManager,
         totalBarBottom: CGFloat = 0) {
        self.piece = piece
        self.pdfURL = pdfURL
        self.editorState = editorState
        self.pageTurnManager = pageTurnManager
        self.totalBarBottom = totalBarBottom
        _viewerPageIndex = State(initialValue: max(0, piece.lastViewedPage))
    }

    var body: some View {
#if os(iOS)
        ScorePDFView(
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
            isViewerInteractionEnabled: editorState.isFullScreenMode,
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
            imageManagementTrigger: editorState.imageManagementTrigger,
            photoImportMenuTrigger: editorState.photoImportMenuTrigger,
            galleryImportTrigger: editorState.galleryImportTrigger,
            fileImportTrigger: editorState.fileImportTrigger,
            isRulerActive: editorState.isRulerActive,
            undoTrigger: editorState.undoTrigger,
            redoTrigger: editorState.redoTrigger,
            prevPageTrigger: editorState.prevPageTrigger,
            nextPageTrigger: editorState.nextPageTrigger,
            jumpToPageTrigger: editorState.jumpToPageTrigger,
            jumpToPageTarget: editorState.jumpToPageTarget,
            pageTurnKeyboardProvider: pageTurnManager.keyboardProvider,
            onCanvasTap: handleCanvasTap,
            onStickerSelectionChanged: { isSelected in
                editorState.hasSelectedSticker = isSelected
            },
            onLayerConfigurationChanged: { layers, active in
                editorState.setLayers(layers, activeLayerID: active)
            }
        )
        .ignoresSafeArea(.all, edges: .bottom)
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
        // PageTurnManager 이벤트 → 페이지 트리거
        .onReceive(pageTurnManager.pageEvents) { event in
            switch event {
            case .nextPage:     editorState.nextPageTrigger += 1
            case .previousPage: editorState.prevPageTrigger += 1
            }
        }
        .onDisappear {
            pageTurnManager.isEnabled = false   // 모든 provider 비활성화
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
