import SwiftUI
import SwiftData
import UniformTypeIdentifiers

private enum PieceSortOption: String, CaseIterable, Identifiable {
    case importedRecent = "가져온 순"
    case title = "제목순"
    case recentlyOpened = "최근 연 순"

    var id: String { rawValue }
}

struct ScoreLibrarySection: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var pieces: [Piece]

    let onSelectPiece: (Piece) -> Void
    @Binding var isPanelOpen: Bool

    @State private var sortOption: PieceSortOption = .importedRecent
    @State private var searchText = ""
    @State private var showingImporter = false
    @State private var showingIMSLPSearch = false
    @State private var importErrorMessage: String?

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Menu {
                    Picker("정렬", selection: $sortOption) {
                        ForEach(PieceSortOption.allCases) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                } label: {
                    Label("정렬", systemImage: "arrow.up.arrow.down")
                }

                Spacer()

                Button {
                    showingIMSLPSearch = true
                } label: {
                    Label("IMSLP", systemImage: "magnifyingglass")
                }

                Button {
                    showingImporter = true
                } label: {
                    Label("가져오기", systemImage: "square.and.arrow.down")
                }
            }
            .padding(.horizontal)
            .padding(.top)

            TextField("곡명 검색", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal)

            List {
                if filteredAndSortedPieces.isEmpty {
                    ContentUnavailableView(
                        "악보가 없습니다",
                        systemImage: "music.note.list",
                        description: Text("PDF 또는 MusicXML을 가져와 주세요.")
                    )
                } else {
                    ForEach(filteredAndSortedPieces) { piece in
                        Button {
                            onSelectPiece(piece)
                        } label: {
                            pieceRow(piece)
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete(perform: deletePieces)
                }
            }
            .listStyle(.plain)
        }
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: allowedScoreTypes(),
            allowsMultipleSelection: false
        ) { result in
            handleImportResult(result)
        }
        .sheet(isPresented: $showingIMSLPSearch) {
            IMSLPSearchSheet()
        }
        .alert("가져오기 실패", isPresented: Binding(
            get: { importErrorMessage != nil },
            set: { if !$0 { importErrorMessage = nil } }
        )) {
            Button("확인", role: .cancel) {
                importErrorMessage = nil
            }
        } message: {
            Text(importErrorMessage ?? "")
        }
    }

    private var filteredAndSortedPieces: [Piece] {
        let keyword = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let filtered = pieces.filter { piece in
            if keyword.isEmpty { return true }
            let titleMatched = piece.title.lowercased().contains(keyword)
            let composerMatched = (piece.composer ?? "").lowercased().contains(keyword)
            return titleMatched || composerMatched
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

    @ViewBuilder
    private func pieceRow(_ piece: Piece) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "doc.richtext")
                .font(.title3)
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 4) {
                Text(piece.title)
                    .font(.body)
                    .foregroundStyle(.primary)

                Text(piece.importedAt, format: .dateTime.year().month().day().hour().minute())
                    .font(.caption)
                    .foregroundStyle(.secondary)

                let formatLabel = (piece.scoreFormat ?? "pdf").uppercased()
                Text(formatLabel)
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

    private func handleImportResult(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            do {
                let pieceID = UUID()
                let imported = try ScoreFileStore.importScore(from: url, pieceID: pieceID)
                let title = url.deletingPathExtension().lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
                let finalTitle = title.isEmpty ? "Untitled Score" : title
                let piece = Piece(
                    id: pieceID,
                    title: finalTitle,
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
        case .failure(let error):
            importErrorMessage = error.localizedDescription
        }
    }

    private func deletePieces(offsets: IndexSet) {
        for index in offsets {
            let piece = filteredAndSortedPieces[index]
            ScoreFileStore.removePieceDirectory(pieceID: piece.id)
            modelContext.delete(piece)
        }
    }

    private func allowedScoreTypes() -> [UTType] {
        var types: [UTType] = [.pdf, .xml]
        if let musicXML = UTType(filenameExtension: "musicxml") {
            types.append(musicXML)
        }
        if let mxl = UTType(filenameExtension: "mxl") {
            types.append(mxl)
        }
        return types
    }
}

private struct IMSLPSearchSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private let mockResults = [
        "Chopin - Waltz Op.69 No.2",
        "Beethoven - Moonlight Sonata",
        "Bach - Invention No.1"
    ]

    private var filtered: [String] {
        let keyword = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if keyword.isEmpty { return mockResults }
        return mockResults.filter { $0.lowercased().contains(keyword) }
    }

    var body: some View {
        NavigationStack {
            List(filtered, id: \.self) { item in
                VStack(alignment: .leading, spacing: 4) {
                    Text(item)
                    Text("IMSLP 연동은 다음 단계에서 실제 API 연결")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .searchable(text: $query, prompt: "작곡가 / 곡명 검색")
            .navigationTitle("IMSLP 검색")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("닫기") {
                        dismiss()
                    }
                }
            }
        }
    }
}
