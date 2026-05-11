import SwiftUI
import WebKit

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

    @State private var navigateTo          : URL? = nil
    @State private var showDownloadConfirm = false
    @State private var downloadedURL       : URL?
    @State private var downloadedFilename  = ""

    // 뒤로/앞으로 버튼을 위해 WKWebView 인스턴스를 보유
    @State private var webView             : WKWebView? = nil
    @State private var canGoBack           : Bool = false
    @State private var canGoForward        : Bool = false

    // IMSLP 검색 페이지로 바로 시작 — 검색창이 즉시 보인다.
    private let startURL = URL(string: "https://imslp.org/wiki/Special:Search")!

    // MARK: - Body

    var body: some View {
        NavigationStack {
            IMSLPBrowserViewWithProgress(
                initialURL: startURL,
                navigateTo: $navigateTo,
                onWebViewCreated: { wv in
                    webView = wv
                    // WKWebView canGoBack/canGoForward 변화를 KVO로 추적
                    observeNavigation(wv)
                }
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
                // 뒤로 / 앞으로
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        webView?.goBack()
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .disabled(!canGoBack)
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        webView?.goForward()
                    } label: {
                        Image(systemName: "chevron.right")
                    }
                    .disabled(!canGoForward)
                }
                // 닫기
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
        // fullScreenCover로 표시되므로 SwiftUI 레이아웃도 키보드를 무시하도록 설정.
        // WKWebView 자체가 포커스된 입력 필드로 스크롤해주므로 별도 회피 불필요.
        .ignoresSafeArea(.keyboard)
    }

    // MARK: - KVO

    private func observeNavigation(_ wv: WKWebView) {
        // WKWebView의 canGoBack / canGoForward는 @Published가 아니므로
        // navigationDelegate didFinish / didFail 에서 폴링하는 것이 가장 단순하다.
        // 여기서는 IMSLPBrowserViewWithProgress 가 이미 NavigationDelegate를 점유하므로
        // 주기적으로 폴링하는 간단한 방식으로 처리한다.
        updateNavState(wv)
        // 상태 변경 감지: 약간의 딜레이를 두고 반복 폴링
        pollNavState(wv)
    }

    private func updateNavState(_ wv: WKWebView) {
        canGoBack    = wv.canGoBack
        canGoForward = wv.canGoForward
    }

    private func pollNavState(_ wv: WKWebView) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak wv] in
            guard let wv else { return }
            updateNavState(wv)
            pollNavState(wv)
        }
    }
}

#endif
