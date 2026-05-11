import SwiftUI

#if os(iOS)

/// PDF URL을 직접 입력해서 다운로드하는 시트.
/// 성공 시 임시 파일 URL과 파일명을 onImport 콜백으로 전달한다.
struct URLImportSheet: View {
    /// (임시 파일 URL, 파일명 제안) — 호출자가 Piece 이름 입력 시트를 띄운다.
    let onImport: (URL, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var urlText      = ""
    @State private var isDownloading = false
    @State private var errorMessage : String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("https://example.com/score.pdf", text: $urlText)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                } header: {
                    Text("직접 링크 (PDF URL)")
                } footer: {
                    Text(
                        "공개된 직접 다운로드 링크만 지원됩니다.\n" +
                        "Google Drive · Dropbox 등 로그인이 필요한 링크는 작동하지 않습니다. " +
                        "대신 '파일 가져오기'를 사용하거나, Google Drive의 경우 " +
                        "파일을 공개 설정 후 직접 링크를 사용하세요."
                    )
                    .font(.caption)
                }

                if let msg = errorMessage {
                    Section {
                        Label(msg, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("URL로 가져오기")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("취소") { dismiss() }
                        .disabled(isDownloading)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if isDownloading {
                        ProgressView()
                    } else {
                        Button("다운로드") { startDownload() }
                            .fontWeight(.semibold)
                            .disabled(trimmedURL.isEmpty)
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private var trimmedURL: String {
        urlText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func startDownload() {
        errorMessage = nil
        guard !trimmedURL.isEmpty else { return }

        guard let url = URL(string: trimmedURL) else {
            errorMessage = "유효한 URL이 아닙니다."
            return
        }
        guard url.pathExtension.lowercased() == "pdf" else {
            errorMessage = "PDF 파일 URL을 입력해 주세요 (URL이 .pdf로 끝나야 합니다)."
            return
        }

        isDownloading = true
        Task {
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                if let http = response as? HTTPURLResponse,
                   !(200...299).contains(http.statusCode) {
                    throw URLError(.badServerResponse)
                }
                let filename = url.lastPathComponent.isEmpty ? "score.pdf" : url.lastPathComponent
                let tempURL  = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString + "_" + filename)
                try data.write(to: tempURL)
                await MainActor.run {
                    isDownloading = false
                    onImport(tempURL, filename)
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isDownloading = false
                    errorMessage  = "다운로드 실패: \(error.localizedDescription)"
                }
            }
        }
    }
}

#endif
