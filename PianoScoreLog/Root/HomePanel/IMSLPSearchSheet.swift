import SwiftUI

#if os(iOS)

/// IMSLP 브라우저 시트.
///
/// WKWebView로 IMSLP 검색 페이지를 직접 표시한다.
/// 네이티브 검색창은 사용하지 않는다 — IMSLP 자체 검색창을 그대로 사용해 봇 감지를 피한다.
/// PDF 다운로드는 WKDownloadDelegate가 가로채어 onImport 콜백으로 전달한다.
struct IMSLPSearchSheet: View {
    /// (임시 파일 URL, 파일명, IMSLP 페이지 제목) — 호출자가 PieceImportSheet를 띄운다.
    let onImport: (URL, String, String) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var navigateTo       : URL? = nil
    @State private var showDownloadConfirm = false
    @State private var downloadedURL       : URL?
    @State private var downloadedFilename  = ""

    // IMSLP 검색 페이지로 바로 시작 — 검색창이 즉시 보인다.
    private let startURL = URL(string: "https://imslp.org/wiki/Special:Search")!

    // MARK: - Body

    var body: some View {
        NavigationStack {
            IMSLPBrowserViewWithProgress(
                initialURL: startURL,
                navigateTo: $navigateTo
            ) { tempURL, filename in
                downloadedURL       = tempURL
                downloadedFilename  = filename
                showDownloadConfirm = true
            }
            .ignoresSafeArea(edges: .bottom)
            // ── 상단 바 ────────────────────────────────────────
            .navigationTitle("IMSLP 악보 검색")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("닫기") { dismiss() }
                }
            }
            // ── 다운로드 확인 ──────────────────────────────────
            .alert("PDF 가져오기", isPresented: $showDownloadConfirm) {
                Button("가져오기") {
                    if let url = downloadedURL {
                        let hint = downloadedFilename
                            .replacingOccurrences(of: ".pdf", with: "", options: .caseInsensitive)
                        onImport(url, downloadedFilename, hint)
                    }
                    dismiss()
                }
                Button("취소", role: .cancel) {
                    if let url = downloadedURL {
                        try? FileManager.default.removeItem(at: url)
                    }
                    downloadedURL = nil
                }
            } message: {
                Text("'\(downloadedFilename)'을(를) 악보 라이브러리에 추가하겠습니까?")
            }
        }
    }
}

#endif
