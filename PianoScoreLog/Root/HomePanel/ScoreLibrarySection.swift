import SwiftUI
import SwiftData
import UniformTypeIdentifiers

// MARK: - Sort Option

private enum PieceSortOption: String, CaseIterable, Identifiable {
    case importedRecent  = "가져온 순"
    case title           = "제목순"
    case recentlyOpened  = "최근 연 순"
    var id: String { rawValue }
}

// MARK: - Main View

struct ScoreLibrarySection: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var pieces: [Piece]

    let onSelectPiece: (Piece) -> Void
    @Binding var isPanelOpen: Bool

    // MARK: UI State

    @State private var sortOption : PieceSortOption = .importedRecent
    @State private var searchText = ""

    // Import source pickers
    @State private var showingFilePicker  = false
    @State private var showingScanner     = false
    @State private var showingURLImport   = false
    @State private var showingIMSLP       = false

    // Pending import (이름 입력 시트용)
    @State private var pendingTempURL         : URL?
    @State private var pendingSuggestedTitle  = ""
    @State private var pendingSuggestedComposer = ""
    @State private var showingImportNameSheet = false

    // Error
    @State private var importErrorMessage: String?

    // MARK: - Body

    var body: some View {
        VStack(spacing: 8) {
            headerBar
            searchField
            pieceList
        }
        // ── 소스 시트들 ──────────────────────────────────────
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: allowedScoreTypes(),
            allowsMultipleSelection: false,
            onCompletion: handleFilePickerResult
        )
        .fullScreenCover(isPresented: $showingScanner) {
            DocumentScannerView(
                onCompletion: { result in
                    showingScanner = false
                    handleScanResult(result)
                },
                onCancel: {
                    showingScanner = false
                }
            )
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showingURLImport) {
            URLImportSheet { tempURL, filename in
                queueImport(tempURL: tempURL,
                            suggestedTitle: filename.deletingPDFExtension,
                            suggestedComposer: "")
            }
        }
        .sheet(isPresented: $showingIMSLP) {
            IMSLPSearchSheet { tempURL, filename, imslpTitle in
                let parsed = IMSLPSearchResult(
                    id: 0, pageTitle: imslpTitle,
                    displayTitle: imslpTitle, snippet: ""
                ).parsedTitleAndComposer()
                queueImport(tempURL: tempURL,
                            suggestedTitle: parsed.title.isEmpty ? filename.deletingPDFExtension : parsed.title,
                            suggestedComposer: parsed.composer)
            }
        }
        // ── 이름 입력 시트 ─────────────────────────────────────
        .sheet(isPresented: $showingImportNameSheet, onDismiss: cancelPendingImport) {
            PieceImportSheet(
                suggestedTitle    : pendingSuggestedTitle,
                suggestedComposer : pendingSuggestedComposer
            ) { title, composer, _ in
                finishImport(title: title, composer: composer)
            }
        }
        // ── 에러 알림 ──────────────────────────────────────────
        .alert("가져오기 실패", isPresented: Binding(
            get: { importErrorMessage != nil },
            set: { if !$0 { importErrorMessage = nil } }
        )) {
            Button("확인", role: .cancel) { importErrorMessage = nil }
        } message: {
            Text(importErrorMessage ?? "")
        }
    }

    // MARK: - Sub-views

    private var headerBar: some View {
        HStack(spacing: 8) {
            Menu {
                Picker("정렬", selection: $sortOption) {
                    ForEach(PieceSortOption.allCases) { Text($0.rawValue).tag($0) }
                }
            } label: {
                Image(systemName: "arrow.up.arrow.down")
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                showingIMSLP = true
            } label: {
                Label("IMSLP", systemImage: "magnifyingglass")
            }
            .buttonStyle(.bordered)
            .tint(.orange)

            Menu {
                Button { showingFilePicker = true } label: {
                    Label("파일 가져오기", systemImage: "folder")
                }
                if DocumentScannerView.isSupported {
                    Button { showingScanner = true } label: {
                        Label("문서 스캔", systemImage: "doc.viewfinder")
                    }
                }
                Button { showingURLImport = true } label: {
                    Label("URL 입력", systemImage: "link")
                }
            } label: {
                Label("가져오기", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
        }
        .padding(.horizontal)
        .padding(.top, 12)
        .padding(.bottom, 4)
    }

    private var searchField: some View {
        TextField("곡명 검색", text: $searchText)
            .textFieldStyle(.roundedBorder)
            .padding(.horizontal)
    }

    private var pieceList: some View {
        List {
            if filteredAndSortedPieces.isEmpty {
                ContentUnavailableView(
                    "악보가 없습니다",
                    systemImage: "music.pages",
                    description: Text("PDF 또는 MusicXML을 가져와 주세요.")
                )
            } else {
                ForEach(filteredAndSortedPieces) { piece in
                    Button { onSelectPiece(piece) } label: { pieceRow(piece) }
                        .buttonStyle(.plain)
                }
                .onDelete(perform: deletePieces)
            }
        }
        .listStyle(.plain)
    }

    @ViewBuilder
    private func pieceRow(_ piece: Piece) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "music.pages")
                .font(.title3)
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 3) {
                Text(piece.title)
                    .font(.body)
                    .foregroundStyle(.primary)

                if let composer = piece.composer, !composer.isEmpty {
                    Text(composer)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(piece.importedAt, format: .dateTime.year().month().day())
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text((piece.scoreFormat ?? "pdf").uppercased())
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.orange)
            }

            Spacer()

            if piece.completedAt != nil {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        }
        .contentShape(Rectangle())
    }

    // MARK: - Filtering / Sorting

    private var filteredAndSortedPieces: [Piece] {
        let keyword = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let filtered = pieces.filter { piece in
            guard !keyword.isEmpty else { return true }
            return piece.title.lowercased().contains(keyword)
                || (piece.composer ?? "").lowercased().contains(keyword)
        }
        switch sortOption {
        case .importedRecent:
            return filtered.sorted { $0.importedAt > $1.importedAt }
        case .title:
            return filtered.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .recentlyOpened:
            return filtered.sorted { ($0.lastOpenedAt ?? .distantPast) > ($1.lastOpenedAt ?? .distantPast) }
        }
    }

    // MARK: - Delete

    private func deletePieces(offsets: IndexSet) {
        for index in offsets {
            let piece = filteredAndSortedPieces[index]
            ScoreFileStore.removePieceDirectory(pieceID: piece.id)
            modelContext.delete(piece)
        }
    }

    // MARK: - Import Handlers

    private func handleFilePickerResult(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            // 보안 스코프 안에서 임시 복사 후 이름 입력 시트로 넘긴다.
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            do {
                let tempURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString + "_" + url.lastPathComponent)
                try FileManager.default.copyItem(at: url, to: tempURL)
                let rawTitle = url.deletingPathExtension().lastPathComponent
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                queueImport(tempURL: tempURL,
                            suggestedTitle: rawTitle.isEmpty ? "Untitled Score" : rawTitle,
                            suggestedComposer: "")
            } catch {
                importErrorMessage = error.localizedDescription
            }
        case .failure(let error):
            importErrorMessage = error.localizedDescription
        }
    }

    private func handleScanResult(_ result: Result<Data, Error>) {
        switch result {
        case .success(let pdfData):
            guard !pdfData.isEmpty else { return }
            do {
                let tempURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString + ".pdf")
                try pdfData.write(to: tempURL)
                queueImport(tempURL: tempURL,
                            suggestedTitle: "스캔한 악보",
                            suggestedComposer: "")
            } catch {
                importErrorMessage = error.localizedDescription
            }
        case .failure(let error):
            importErrorMessage = error.localizedDescription
        }
    }

    // MARK: - Pending Import Flow

    /// 임시 파일과 제안 정보를 저장하고 이름 입력 시트를 표시한다.
    private func queueImport(tempURL: URL, suggestedTitle: String, suggestedComposer: String) {
        pendingTempURL            = tempURL
        pendingSuggestedTitle     = suggestedTitle
        pendingSuggestedComposer  = suggestedComposer
        showingImportNameSheet    = true
    }

    /// 이름 입력 확인 — ScoreFileStore에 저장하고 Piece를 생성한다.
    private func finishImport(title: String, composer: String) {
        guard let tempURL = pendingTempURL else { return }
        pendingTempURL = nil      // onDismiss에서 cleanup하지 않도록 먼저 nil 처리

        do {
            let pieceID  = UUID()
            let imported = try ScoreFileStore.importScore(from: tempURL, pieceID: pieceID)
            try? FileManager.default.removeItem(at: tempURL)   // 임시 파일 정리

            let finalTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
            let piece = Piece(
                id: pieceID,
                title: finalTitle.isEmpty ? "Untitled Score" : finalTitle,
                composer: composer.isEmpty ? nil : composer,
                pdfRelativePath: imported.type == .pdf ? imported.relativePath : nil,
                scoreRelativePath: imported.relativePath,
                scoreFormat: imported.type.rawValue,
                importedAt: .now,
                createdAt: .now
            )
            modelContext.insert(piece)
            onSelectPiece(piece)
        } catch {
            importErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// 이름 입력 취소 또는 시트 스와이프 닫기 — 임시 파일 정리.
    private func cancelPendingImport() {
        if let url = pendingTempURL {
            try? FileManager.default.removeItem(at: url)
            pendingTempURL = nil
        }
    }

    // MARK: - Allowed Types

    private func allowedScoreTypes() -> [UTType] {
        var types: [UTType] = [.pdf, .xml]
        if let musicXML = UTType(filenameExtension: "musicxml") { types.append(musicXML) }
        if let mxl      = UTType(filenameExtension: "mxl")      { types.append(mxl) }
        return types
    }
}

// MARK: - String Helper

private extension String {
    /// "score.pdf" → "score"
    var deletingPDFExtension: String {
        (self as NSString).deletingPathExtension
    }
}
