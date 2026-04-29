import SwiftUI
import SwiftData
import UniformTypeIdentifiers

// MARK: - Sort Option

private enum LibrarySortOption: String, CaseIterable, Identifiable {
    case importedRecent = "가져온 순"
    case title          = "제목순"
    case recentlyOpened = "최근 연 순"
    var id: String { rawValue }
}

// MARK: - Pending Import

/// 가져오기 시트에 전달할 데이터 묶음.
/// .sheet(item:)에 직접 전달해 타이밍 문제로 인한 @State 초기화 오류를 방지한다.
private struct PendingImport: Identifiable {
    let id             = UUID()
    let tempURL        : URL
    let suggestedTitle : String
    let suggestedComposer: String
    let folderID       : UUID?
}

// MARK: - Top-Level Container

/// 전체 화면 라이브러리.
/// "악보" 탭(폴더+목록)과 "피출" 탭(플레이스홀더)으로 구성된다.
struct LibraryHomeView: View {
    let onSelectPiece: (Piece) -> Void
    @Binding var isPanelOpen: Bool

    var body: some View {
        TabView {
            NavigationStack {
                LibraryRootView(currentFolder: nil) { piece in
                    onSelectPiece(piece)
                    isPanelOpen = false
                }
            }
            .tabItem { Label("Score", systemImage: "music.pages.fill") }

            NavigationStack {
                PianologSection()
                    .navigationTitle("Log")
            }
            .tabItem { Label("Log", systemImage: "flame") }
        }
    }
}

// MARK: - Library Root (폴더 내부 재사용)

/// 루트(currentFolder=nil)와 폴더 내부(currentFolder!=nil) 양쪽에서 재사용된다.
struct LibraryRootView: View {
    var currentFolder: ScoreFolder? = nil
    let onSelectPiece: (Piece) -> Void

    @Environment(\.modelContext) private var modelContext
    @Query private var allPieces: [Piece]
    @Query(sort: \ScoreFolder.createdAt) private var allFolders: [ScoreFolder]

    @State private var sortOption: LibrarySortOption = .importedRecent
    @State private var searchText = ""

    // Import
    @State private var showingFilePicker  = false
    @State private var showingScanner     = false
    @State private var showingURLImport   = false
    @State private var showingIMSLP       = false
    @State private var pendingImport      : PendingImport?      // 가져오기 시트용
    @State private var imslpIncoming      : (tempURL: URL, title: String)? // IMSLP 타이밍용
    @State private var importErrorMessage : String?

    // Folder actions
    @State private var showingNewFolderAlert = false
    @State private var newFolderName         = ""
    @State private var pieceToMove           : Piece?
    @State private var showingMovePicker     = false
    @State private var renameTarget          : ScoreFolder?
    @State private var renameText            = ""
    @State private var showingRenameAlert    = false

    // MARK: Computed

    private var contextPieces: [Piece] {
        if let folder = currentFolder {
            return allPieces.filter { $0.folderID == folder.id }
        }
        return allPieces.filter { $0.folderID == nil }
    }

    private var filteredPieces: [Piece] {
        let kw = searchText.lowercased().trimmingCharacters(in: .whitespaces)
        let base = contextPieces.filter { piece in
            kw.isEmpty
                || piece.title.lowercased().contains(kw)
                || (piece.composer ?? "").lowercased().contains(kw)
        }
        switch sortOption {
        case .importedRecent:
            return base.sorted { $0.importedAt > $1.importedAt }
        case .title:
            return base.sorted {
                $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
        case .recentlyOpened:
            return base.sorted {
                ($0.lastOpenedAt ?? .distantPast) > ($1.lastOpenedAt ?? .distantPast)
            }
        }
    }

    private func pieceCount(in folder: ScoreFolder) -> Int {
        allPieces.filter { $0.folderID == folder.id }.count
    }

    // MARK: Body

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: .sectionHeaders) {
                // 폴더 그리드 — 루트에서만, 폴더가 있을 때만
                if currentFolder == nil && !allFolders.isEmpty {
                    folderGridSection
                }
                // 악보 목록
                piecesSection
            }
        }
        .searchable(text: $searchText, prompt: "곡명 / 작곡가")
        .navigationTitle(currentFolder?.name ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .navigationDestination(for: ScoreFolder.self) { folder in
            LibraryRootView(currentFolder: folder, onSelectPiece: onSelectPiece)
        }
        // ── Import Sheets ──────────────────────────────────────
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
                onCancel: { showingScanner = false }
            )
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showingURLImport) {
            URLImportSheet { tempURL, filename in
                queueImport(tempURL: tempURL,
                            suggestedTitle: filename.deletingScoreExtension,
                            suggestedComposer: "")
            }
        }
        .sheet(isPresented: $showingIMSLP) {
            IMSLPSearchSheet { tempURL, filename, _ in
                // IMSLP 내부 dismiss()와 동시에 pendingImport를 설정하면
                // 고스트 시트 및 타이틀 공란 문제가 발생한다.
                // imslpIncoming에만 저장하고, 시트가 완전히 사라진 뒤 onDisappear에서 설정한다.
                imslpIncoming = (tempURL, filename.deletingScoreExtension)
            }
            .onDisappear {
                guard let inc = imslpIncoming else { return }
                imslpIncoming = nil
                pendingImport = PendingImport(
                    tempURL:          inc.tempURL,
                    suggestedTitle:   inc.title,
                    suggestedComposer: "",
                    folderID:         currentFolder?.id
                )
            }
        }
        // .sheet(item:) — 데이터를 pending에 직접 담아 @State 타이밍 문제를 원천 차단
        .sheet(item: $pendingImport) { pending in
            PieceImportSheet(
                suggestedTitle:    pending.suggestedTitle,
                suggestedComposer: pending.suggestedComposer,
                defaultFolderID:   pending.folderID
            ) { title, composer, folderID in
                finishImport(pending: pending, title: title, composer: composer, folderID: folderID)
            }
        }
        // ── Move Sheet ─────────────────────────────────────────
        .sheet(isPresented: $showingMovePicker) {
            MoveToPieceSheet(allFolders: allFolders) { folder in
                pieceToMove?.folderID = folder?.id
                showingMovePicker = false
                pieceToMove = nil
            }
        }
        // ── Alerts ─────────────────────────────────────────────
        .alert("새 폴더", isPresented: $showingNewFolderAlert) {
            TextField("폴더 이름", text: $newFolderName)
            Button("만들기") { createFolder() }
            Button("취소", role: .cancel) { newFolderName = "" }
        }
        .alert("이름 변경", isPresented: $showingRenameAlert) {
            TextField("새 이름", text: $renameText)
            Button("확인") {
                renameTarget?.name = renameText.trimmingCharacters(in: .whitespaces)
                renameTarget = nil
            }
            Button("취소", role: .cancel) { renameTarget = nil }
        }
        .alert("가져오기 실패", isPresented: Binding(
            get: { importErrorMessage != nil },
            set: { if !$0 { importErrorMessage = nil } }
        )) {
            Button("확인", role: .cancel) { importErrorMessage = nil }
        } message: {
            Text(importErrorMessage ?? "")
        }
    }

    // MARK: - Folder Grid Section

    @ViewBuilder
    private var folderGridSection: some View {
        Section {
            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible())],
                spacing: 12
            ) {
                ForEach(allFolders) { folder in
                    NavigationLink(value: folder) {
                        FolderCard(name: folder.name, count: pieceCount(in: folder))
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button {
                            renameTarget = folder
                            renameText   = folder.name
                            showingRenameAlert = true
                        } label: { Label("이름 변경", systemImage: "pencil") }

                        Button(role: .destructive) { deleteFolder(folder) } label: {
                            Label("폴더 삭제", systemImage: "trash")
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        } header: {
            SectionHeader(title: "폴더")
        }
    }

    // MARK: - Pieces Section

    @ViewBuilder
    private var piecesSection: some View {
        Section {
            if filteredPieces.isEmpty {
                ContentUnavailableView(
                    "악보가 없습니다",
                    systemImage: "music.pages",
                    description: Text("IMSLP 또는 파일 가져오기로 추가하세요.")
                )
                .padding(.top, 40)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(filteredPieces) { piece in
                        PieceLibraryRow(piece: piece)
                            .contentShape(Rectangle())
                            .onTapGesture { onSelectPiece(piece) }
                            .contextMenu { pieceContextMenu(piece) }
                        Divider().padding(.leading, 56)
                    }
                }
            }
        } header: {
            HStack {
                SectionHeader(title: currentFolder == nil ? "미분류 악보" : "악보")
                Spacer()
                Menu {
                    Picker("정렬", selection: $sortOption) {
                        ForEach(LibrarySortOption.allCases) {
                            Text($0.rawValue).tag($0)
                        }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                        .foregroundStyle(.secondary)
                        .padding(.trailing, 16)
                        .padding(.vertical, 8)
                }
            }
            .background(.background)
        }
    }

    @ViewBuilder
    private func pieceContextMenu(_ piece: Piece) -> some View {
        if !allFolders.isEmpty {
            Button {
                pieceToMove = piece
                showingMovePicker = true
            } label: { Label("폴더로 이동", systemImage: "folder") }
        }
        Button(role: .destructive) { deletePiece(piece) } label: {
            Label("삭제", systemImage: "trash")
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            HStack {
                // 새 폴더 — 루트에서만
                if currentFolder == nil {
                    Button {
                        newFolderName = ""
                        showingNewFolderAlert = true
                    } label: {
                        Image(systemName: "folder.badge.plus")
                    }
                }

                // IMSLP — 텍스트만
                Button("IMSLP") { showingIMSLP = true }

                // 가져오기 메뉴
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
                    Image(systemName: "square.and.arrow.down")
                }
            }
        }
    }

    // MARK: - Folder Actions

    private func createFolder() {
        let name = newFolderName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        modelContext.insert(ScoreFolder(name: name))
        newFolderName = ""
    }

    private func deleteFolder(_ folder: ScoreFolder) {
        // 소속 악보 → 미분류로
        for piece in allPieces where piece.folderID == folder.id {
            piece.folderID = nil
        }
        modelContext.delete(folder)
    }

    private func deletePiece(_ piece: Piece) {
        ScoreFileStore.removePieceDirectory(pieceID: piece.id)
        modelContext.delete(piece)
    }

    // MARK: - Import Handlers

    private func handleFilePickerResult(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            do {
                let tmp = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString + "_" + url.lastPathComponent)
                try FileManager.default.copyItem(at: url, to: tmp)
                let rawTitle = url.deletingPathExtension().lastPathComponent
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                queueImport(tempURL: tmp,
                            suggestedTitle: rawTitle.isEmpty ? "무제 악보" : rawTitle,
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
                let tmp = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString + ".pdf")
                try pdfData.write(to: tmp)
                queueImport(tempURL: tmp, suggestedTitle: "스캔", suggestedComposer: "")
            } catch {
                importErrorMessage = error.localizedDescription
            }
        case .failure(let error):
            importErrorMessage = error.localizedDescription
        }
    }

    private func queueImport(tempURL: URL, suggestedTitle: String, suggestedComposer: String) {
        pendingImport = PendingImport(
            tempURL:          tempURL,
            suggestedTitle:   suggestedTitle,
            suggestedComposer: suggestedComposer,
            folderID:         currentFolder?.id
        )
    }

    private func finishImport(pending: PendingImport, title: String, composer: String, folderID: UUID?) {
        do {
            let pieceID  = UUID()
            let imported = try ScoreFileStore.importScore(from: pending.tempURL, pieceID: pieceID)
            try? FileManager.default.removeItem(at: pending.tempURL)

            let finalTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
            let piece = Piece(
                id: pieceID,
                title: finalTitle.isEmpty ? "무제 악보" : finalTitle,
                composer: composer.isEmpty ? nil : composer,
                pdfRelativePath: imported.type == .pdf ? imported.relativePath : nil,
                scoreRelativePath: imported.relativePath,
                scoreFormat: imported.type.rawValue,
                importedAt: .now,
                createdAt: .now,
                folderID: folderID
            )
            modelContext.insert(piece)
            onSelectPiece(piece)
        } catch {
            importErrorMessage =
                (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func allowedScoreTypes() -> [UTType] {
        var types: [UTType] = [.pdf, .xml]
        if let t = UTType(filenameExtension: "musicxml") { types.append(t) }
        if let t = UTType(filenameExtension: "mxl")      { types.append(t) }
        return types
    }
}

// MARK: - Piece Row

struct PieceLibraryRow: View {
    let piece: Piece

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "music.pages")
                .font(.title3)
                .foregroundStyle(.orange)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(piece.title)
                    .font(.body)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    if let composer = piece.composer, !composer.isEmpty {
                        Text(composer)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text((piece.scoreFormat ?? "pdf").uppercased())
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundStyle(.orange)
                }
            }

            Spacer()

            if piece.completedAt != nil {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.subheadline)
            }

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

// MARK: - Folder Card

private struct FolderCard: View {
    let name: String
    let count: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: "folder.fill")
                .font(.system(size: 30))
                .foregroundStyle(.orange)

            Text(name)
                .font(.subheadline)
                .fontWeight(.medium)
                .lineLimit(2)
                .foregroundStyle(.primary)

            Text("\(count)곡")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Section Header

private struct SectionHeader: View {
    let title: String
    var body: some View {
        Text(title)
            .font(.headline)
            .foregroundStyle(.primary)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background)
    }
}

// MARK: - Move Sheet

private struct MoveToPieceSheet: View {
    let allFolders: [ScoreFolder]
    let onMove: (ScoreFolder?) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Button {
                    onMove(nil)
                } label: {
                    Label("미분류 (폴더 없음)", systemImage: "tray")
                        .foregroundStyle(.primary)
                }

                ForEach(allFolders) { folder in
                    Button {
                        onMove(folder)
                    } label: {
                        Label(folder.name, systemImage: "folder")
                            .foregroundStyle(.primary)
                    }
                }
            }
            .navigationTitle("폴더로 이동")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("취소") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - String Helper

private extension String {
    var deletingScoreExtension: String {
        (self as NSString).deletingPathExtension
    }
}
