import SwiftUI
import SwiftData

#if os(iOS)

/// 가져오기 완료 후 곡명·작곡가·폴더를 확인/수정하는 시트.
/// 모든 가져오기 경로(파일, 스캔, URL, IMSLP) 공통으로 사용한다.
/// .large detent — 아이폰 17 프로 9:19.5 비율(전체 높이)에 맞춤.
struct PieceImportSheet: View {
    let suggestedTitle    : String
    let suggestedComposer : String
    let defaultFolderID   : UUID?
    /// (최종 곡명, 최종 작곡가, 선택된 폴더ID) — 호출자가 Piece를 생성한다.
    let onConfirm : (String, String, UUID?) -> Void

    @State private var title           : String
    @State private var composer        : String
    @State private var selectedFolderID: UUID?

    // 새 폴더 만들기 알림
    @State private var showNewFolderAlert = false
    @State private var newFolderName      = ""

    @Query(sort: \ScoreFolder.createdAt) private var folders: [ScoreFolder]
    @Environment(\.dismiss)      private var dismiss
    @Environment(\.modelContext) private var modelContext

    init(
        suggestedTitle    : String,
        suggestedComposer : String = "",
        defaultFolderID   : UUID? = nil,
        onConfirm         : @escaping (String, String, UUID?) -> Void
    ) {
        self.suggestedTitle    = suggestedTitle
        self.suggestedComposer = suggestedComposer
        self.defaultFolderID   = defaultFolderID
        self.onConfirm         = onConfirm
        self._title              = State(initialValue: suggestedTitle)
        self._composer           = State(initialValue: suggestedComposer)
        self._selectedFolderID   = State(initialValue: defaultFolderID)
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Form {
                // ── 곡명 ──────────────────────────────────────────
                Section {
                    TextField("곡명 (필수)", text: $title)
                        .autocorrectionDisabled()
                } header: {
                    Text("곡명")
                }

                // ── 작곡가 ────────────────────────────────────────
                Section {
                    TextField("작곡가 (선택)", text: $composer)
                        .autocorrectionDisabled()
                } header: {
                    Text("작곡가")
                }

                // ── 폴더 ──────────────────────────────────────────
                Section {
                    Picker("폴더", selection: $selectedFolderID) {
                        Text("미분류")
                            .tag(nil as UUID?)
                        ForEach(folders) { folder in
                            Text(folder.name)
                                .tag(folder.id as UUID?)
                        }
                    }

                    // 새 폴더 만들기
                    Button {
                        newFolderName = ""
                        showNewFolderAlert = true
                    } label: {
                        Label("새 폴더 만들기", systemImage: "folder.badge.plus")
                            .foregroundStyle(Color.accentColor)
                    }
                } header: {
                    Text("폴더")
                } footer: {
                    Text("나중에 길게 눌러 이동할 수 있습니다.")
                }
            }
            .navigationTitle("악보 정보 입력")
            .navigationBarTitleDisplayMode(.inline)
            // NavigationBar 글래스(UIVisualEffectView)를 처음부터 고정 렌더링.
            // 시트 전환 직후 글래스가 좌상단에서 시작하는 시각 버그 방지.
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("취소", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("추가") {
                        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
                        let c = composer.trimmingCharacters(in: .whitespacesAndNewlines)
                        onConfirm(t.isEmpty ? suggestedTitle : t, c, selectedFolderID)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            // ── 새 폴더 이름 입력 알림 ─────────────────────────
            .alert("새 폴더", isPresented: $showNewFolderAlert) {
                TextField("폴더 이름", text: $newFolderName)
                    .autocorrectionDisabled()
                Button("만들기") { createFolder() }
                    .disabled(newFolderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("취소", role: .cancel) { newFolderName = "" }
            } message: {
                Text("새 폴더 이름을 입력하세요.")
            }
        }
        // 아이폰 17 프로 비율 기준 — 전체 높이 사용
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Actions

    private func createFolder() {
        let name = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let folder = ScoreFolder(name: name)
        modelContext.insert(folder)
        // 방금 만든 폴더를 자동 선택
        selectedFolderID = folder.id
        newFolderName = ""
    }
}

#endif
