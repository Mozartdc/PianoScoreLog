import SwiftUI
import SwiftData

struct RootShellView: View {
    @Query private var pieces: [Piece]

    @State private var openPieceIDs: [UUID] = []
    @State private var selectedPieceID: UUID?
    @State private var isPanelOpen: Bool = true
    @State private var editorState = ScoreEditorState()

    private var openPieces: [Piece] {
        openPieceIDs.compactMap { id in pieces.first { $0.id == id } }
    }

    private var selectedPiece: Piece? {
        guard let id = selectedPieceID else { return nil }
        return pieces.first { $0.id == id }
    }

    private func openPiece(_ piece: Piece) {
        if !openPieceIDs.contains(piece.id) {
            openPieceIDs.append(piece.id)
        }
        selectedPieceID = piece.id
    }

    private func closeTab(id: UUID) {
        guard let idx = openPieceIDs.firstIndex(of: id) else { return }
        openPieceIDs.remove(at: idx)
        if selectedPieceID == id {
            selectedPieceID = openPieceIDs.isEmpty ? nil : openPieceIDs[max(0, idx - 1)]
        }
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                backgroundViewer

                if isPanelOpen, isIPad {
                    Color.black.opacity(0.2)
                        .ignoresSafeArea()
                        .onTapGesture {
                            withAnimation(.spring()) { isPanelOpen = false }
                        }

                    HomePanelView(
                        onSelectPiece: { piece in
                            openPiece(piece)
                            piece.lastOpenedAt = .now
                            withAnimation(.spring()) { isPanelOpen = false }
                        },
                        isPanelOpen: $isPanelOpen
                    )
                    .frame(width: min(proxy.size.width * 0.5, 500))
                    .frame(maxHeight: .infinity)
                    .background(.regularMaterial)
                    .transition(.move(edge: .leading).combined(with: .opacity))
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                if !openPieces.isEmpty && !editorState.isFullScreenMode {
                    ScoreTabBar(
                        openPieces: openPieces,
                        selectedPieceID: $selectedPieceID,
                        onClose: closeTab
                    )
                    .background(
                        BlurView(style: .systemChromeMaterial, bottomCornerRadius: 16)
                    )
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .sheet(isPresented: Binding(
                get: { !isIPad && isPanelOpen },
                set: { value in
                    if !isIPad {
                        isPanelOpen = value
                    }
                }
            )) {
                HomePanelView(
                    onSelectPiece: { piece in
                        openPiece(piece)
                        piece.lastOpenedAt = .now
                        withAnimation(.spring()) { isPanelOpen = false }
                    },
                    isPanelOpen: $isPanelOpen
                )
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
            .onAppear {
                syncSelectedPieceWithCurrentData()
            }
            .onChange(of: pieces) { _, _ in
                syncSelectedPieceWithCurrentData()
            }
            .onChange(of: openPieces.isEmpty) { _, isEmpty in
                if isEmpty {
                    withAnimation(.spring()) { isPanelOpen = true }
                }
            }
            .onChange(of: selectedPieceID) { _, _ in
                editorState.reset()
            }
            .animation(.spring(), value: isPanelOpen)
            .animation(.spring(), value: editorState.isEditorMode)
        }
    }

    @ViewBuilder
    private var backgroundViewer: some View {
        if let piece = selectedPiece,
           (piece.scoreFormat ?? "pdf") == "pdf",
           let scoreURL = resolvedScoreURL(for: piece),
           FileManager.default.fileExists(atPath: scoreURL.path) {
            ScoreViewerScreen(
                piece: piece,
                pdfURL: scoreURL,
                editorState: editorState
            ) {
                withAnimation(.spring()) {
                    isPanelOpen = true
                }
            }
            .id(piece.id)
        } else {
            EmptyScoreBackground()
        }
    }

    private func resolvedScoreURL(for piece: Piece) -> URL? {
        let path = piece.scoreRelativePath ?? piece.pdfRelativePath
        return try? ScoreFileStore.fileURL(for: path)
    }

    private var isIPad: Bool {
        #if os(iOS)
        UIDevice.current.userInterfaceIdiom == .pad
        #else
        false
        #endif
    }

    private func syncSelectedPieceWithCurrentData() {
        let validIDs = Set(pieces.map(\.id))
        let removedIDs = openPieceIDs.filter { !validIDs.contains($0) }
        for id in removedIDs {
            closeTab(id: id)
        }
    }
}

private struct EmptyScoreBackground: View {
    var body: some View {
        ZStack {
            Color(.systemGroupedBackground)
            VStack(spacing: 10) {
                Image(systemName: "music.note")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                Text("악보를 선택하세요")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    RootShellView()
        .modelContainer(
            for: [Piece.self, PracticeSession.self, PieceDailyStatus.self, Recording.self, MetronomePreset.self],
            inMemory: true
        )
}
