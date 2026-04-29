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

    @State private var title          : String
    @State private var composer       : String
    @State private var selectedFolderID: UUID?

    @Query(sort: \ScoreFolder.createdAt) private var folders: [ScoreFolder]
    @Environment(\.dismiss) private var dismiss

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
        self._title             = State(initialValue: suggestedTitle)
        self._composer          = State(initialValue: suggestedComposer)
        self._selectedFolderID  = State(initialValue: defaultFolderID)
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

                // ── 폴더 (폴더가 하나라도 있을 때만) ──────────────
                if !folders.isEmpty {
                    Section {
                        Picker("폴더", selection: $selectedFolderID) {
                            Text("미분류")
                                .tag(nil as UUID?)
                            ForEach(folders) { folder in
                                Text(folder.name)
                                    .tag(folder.id as UUID?)
                            }
                        }
                    } header: {
                        Text("폴더")
                    } footer: {
                        Text("나중에 길게 눌러 이동할 수 있습니다.")
                    }
                }
            }
            .navigationTitle("악보 정보 입력")
            .navigationBarTitleDisplayMode(.inline)
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
        }
        // 아이폰 17 프로 비율 기준 — 전체 높이 사용
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}

#endif
