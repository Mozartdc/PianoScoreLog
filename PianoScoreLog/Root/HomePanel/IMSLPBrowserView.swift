import SwiftUI
import WebKit

#if os(iOS)

// MARK: - WKWebView Wrapper

/// IMSLP 페이지를 표시하고 PDF 다운로드를 가로채는 WKWebView 래퍼.
///
/// - `initialURL`: 처음 로드할 URL.
/// - `navigateTo`: 외부에서 새 URL로 이동시키려면 이 Binding에 값을 넣는다.
///   UIViewRepresentable의 updateUIView에서 소비한 뒤 nil로 초기화된다.
/// - `onPDFDownloaded`: PDF 다운로드 완료 시 (임시파일 URL, 파일명) 전달.
struct IMSLPBrowserView: UIViewRepresentable {
    let initialURL: URL
    @Binding var navigateTo: URL?
    let onPDFDownloaded: (URL, String) -> Void

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator

        // Safari Mobile과 동일한 User-Agent — 봇 감지 방지
        webView.customUserAgent =
            "Mozilla/5.0 (iPad; CPU OS 17_0 like Mac OS X) " +
            "AppleWebKit/605.1.15 (KHTML, like Gecko) " +
            "Version/17.0 Mobile/15E148 Safari/604.1"

        // IMSLP 다운로드 disclaimer 쿠키 미리 설정
        // — 없으면 PDF 클릭 시 disclaimer 페이지로 리다이렉트되어 WKDownload가 막힘
        let cookieProps: [HTTPCookiePropertyKey: Any] = [
            .domain:  "imslp.org",
            .path:    "/",
            .name:    "imslpdisclaimeraccepted",
            .value:   "yes",
            .secure:  "TRUE",
            .expires: Date(timeIntervalSinceNow: 60 * 60 * 24 * 365)
        ]
        if let cookie = HTTPCookie(properties: cookieProps) {
            webView.configuration.websiteDataStore.httpCookieStore.setCookie(cookie)
        }

        webView.allowsBackForwardNavigationGestures = true
        webView.load(URLRequest(url: initialURL))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        // 외부에서 navigateTo가 설정된 경우만 이동
        guard let url = navigateTo else { return }
        webView.load(URLRequest(url: url))
        // 다음 런루프에서 소비 (updateUIView 재진입 방지)
        DispatchQueue.main.async { navigateTo = nil }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    // MARK: - Coordinator

    final class Coordinator: NSObject, WKNavigationDelegate {
        let parent: IMSLPBrowserView
        private var pendingDestinationURL: URL?
        private var pendingSuggestedFilename = "score.pdf"

        init(_ parent: IMSLPBrowserView) { self.parent = parent }

        // MARK: Response policy — PDF 응답 시 다운로드로 전환

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationResponse: WKNavigationResponse,
            decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
        ) {
            let mime = navigationResponse.response.mimeType ?? ""
            let ext  = navigationResponse.response.url?.pathExtension.lowercased() ?? ""
            let disposition = (navigationResponse.response as? HTTPURLResponse)?
                .value(forHTTPHeaderField: "Content-Disposition") ?? ""
            let isPDF = mime == "application/pdf"
                || ext == "pdf"
                || disposition.lowercased().contains("attachment")

            if isPDF {
                if #available(iOS 14.5, *) {
                    pendingSuggestedFilename =
                        navigationResponse.response.suggestedFilename ?? "score.pdf"
                    decisionHandler(.download)
                } else {
                    if let pdfURL = navigationResponse.response.url {
                        downloadManually(from: pdfURL,
                                         filename: navigationResponse.response.suggestedFilename ?? "score.pdf")
                    }
                    decisionHandler(.cancel)
                }
            } else {
                decisionHandler(.allow)
            }
        }

        // MARK: iOS 14.5+ download wiring

        @available(iOS 14.5, *)
        func webView(_ webView: WKWebView,
                     navigationResponse: WKNavigationResponse,
                     didBecome download: WKDownload) {
            download.delegate = self
        }

        // MARK: Fallback (iOS < 14.5)

        private func downloadManually(from url: URL, filename: String) {
            Task {
                do {
                    let (data, _) = try await URLSession.shared.data(from: url)
                    let dest = FileManager.default.temporaryDirectory
                        .appendingPathComponent(UUID().uuidString + "_" + filename)
                    try data.write(to: dest)
                    await MainActor.run { self.parent.onPDFDownloaded(dest, filename) }
                } catch { /* 조용히 실패 */ }
            }
        }
    }
}

// MARK: - WKDownloadDelegate (iOS 14.5+)

@available(iOS 14.5, *)
extension IMSLPBrowserView.Coordinator: WKDownloadDelegate {

    func download(
        _ download: WKDownload,
        decideDestinationUsing response: URLResponse,
        suggestedFilename: String,
        completionHandler: @escaping (URL?) -> Void
    ) {
        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + "_" + suggestedFilename)
        pendingDestinationURL    = dest
        pendingSuggestedFilename = suggestedFilename
        completionHandler(dest)
    }

    func downloadDidFinish(_ download: WKDownload) {
        guard let dest = pendingDestinationURL else { return }
        let filename = pendingSuggestedFilename
        pendingDestinationURL = nil
        DispatchQueue.main.async { self.parent.onPDFDownloaded(dest, filename) }
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        pendingDestinationURL = nil
    }
}

// MARK: - Single-work browser sheet (검색 결과에서 작품 페이지를 여는 용도)

/// 특정 IMSLP 작품 페이지를 표시하는 시트.
/// 현재는 IMSLPSearchSheet(전체 브라우저)가 대체하므로 직접 사용되지 않지만 보존한다.
struct IMSLPBrowserSheet: View {
    let pageURL: URL
    let pageTitle: String
    let onImport: (URL, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var navigateTo      : URL? = nil
    @State private var downloadedURL   : URL?
    @State private var downloadedFilename = ""
    @State private var showConfirmation   = false

    var body: some View {
        NavigationStack {
            IMSLPBrowserView(
                initialURL: pageURL,
                navigateTo: $navigateTo,
                onPDFDownloaded: { tempURL, filename in
                    downloadedURL      = tempURL
                    downloadedFilename = filename
                    showConfirmation   = true
                }
            )
            .navigationTitle(pageTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("닫기") { dismiss() }
                }
            }
            .alert("PDF 가져오기", isPresented: $showConfirmation) {
                Button("가져오기") {
                    if let url = downloadedURL { onImport(url, downloadedFilename) }
                    dismiss()
                }
                Button("취소", role: .cancel) {
                    if let url = downloadedURL { try? FileManager.default.removeItem(at: url) }
                    downloadedURL = nil
                }
            } message: {
                Text("'\(downloadedFilename)'을(를) 라이브러리에 추가하겠습니까?")
            }
        }
    }
}

// MARK: - Progress overlay helper

/// WKWebView에 진행률 표시줄을 추가하는 래퍼 뷰.
struct IMSLPBrowserViewWithProgress: View {
    let initialURL: URL
    @Binding var navigateTo: URL?
    let onPDFDownloaded: (URL, String) -> Void

    // WKWebView의 estimatedProgress를 직접 관찰할 수 없어
    // 간단한 인디케이터(overlay ProgressView)로 대체한다.
    @State private var isLoading = true

    var body: some View {
        ZStack(alignment: .top) {
            IMSLPBrowserView(
                initialURL: initialURL,
                navigateTo: $navigateTo,
                onPDFDownloaded: onPDFDownloaded
            )

            if isLoading {
                ProgressView()
                    .padding(8)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                    .padding(.top, 8)
            }
        }
        // 실제 로딩 완료 신호가 없으므로 2초 후 자동 숨김
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                withAnimation { isLoading = false }
            }
        }
        .onChange(of: navigateTo) { _, url in
            if url != nil {
                withAnimation { isLoading = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                    withAnimation { isLoading = false }
                }
            }
        }
    }
}

#endif
