import Foundation

// MARK: - Domain Model

struct IMSLPSearchResult: Identifiable, Sendable {
    let id: Int
    /// IMSLP 위키 페이지 제목 (URL 경로 인코딩용)
    let pageTitle: String
    /// 화면에 표시할 곡명 (괄호 안 작곡가 포함)
    let displayTitle: String
    /// HTML 태그 제거된 스니펫
    let snippet: String

    /// IMSLP 작품 페이지 URL
    var pageURL: URL? {
        guard let encoded = pageTitle.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else { return nil }
        return URL(string: "https://imslp.org/wiki/\(encoded)")
    }
}

// MARK: - Service

/// IMSLP MediaWiki API를 통해 악보를 검색한다.
/// actor 격리로 URLSession 호출 순서를 보장한다.
actor IMSLPService {
    static let shared = IMSLPService()
    private init() {}

    // MediaWiki 표준 경로: /w/api.php
    private let apiBase = "https://imslp.org/w/api.php"

    /// 작곡가/곡명 키워드로 IMSLP를 검색한다.
    func search(query: String) async throws -> [IMSLPSearchResult] {
        let keyword = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return [] }

        // origin=* 는 브라우저 CORS 전용 — iOS 네이티브 앱에서는 제거
        guard let encoded = keyword.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "\(apiBase)?action=query&list=search&srsearch=\(encoded)&srlimit=20&format=json")
        else { return [] }

        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("PianoScoreLog/1.0 (iOS score viewer; imslp search)",
                         forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)

        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw NSError(
                domain: "IMSLPService",
                code: http.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "서버 오류 (HTTP \(http.statusCode))"]
            )
        }

        return try parseResults(data)
    }

    // MARK: - Parsing (JSONSerialization — API 구조 변경에 강건함)

    private func parseResults(_ data: Data) throws -> [IMSLPSearchResult] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(domain: "IMSLPService", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "응답 파싱 실패"])
        }

        // API 오류 감지
        if let errorBlock = json["error"] as? [String: Any],
           let info = errorBlock["info"] as? String {
            throw NSError(domain: "IMSLPService", code: -2,
                          userInfo: [NSLocalizedDescriptionKey: "IMSLP API 오류: \(info)"])
        }

        guard let queryBlock  = json["query"]  as? [String: Any],
              let searchArray = queryBlock["search"] as? [[String: Any]]
        else { return [] }

        return searchArray.compactMap { item -> IMSLPSearchResult? in
            guard let pageid = item["pageid"] as? Int,
                  let title  = item["title"]  as? String
            else { return nil }

            let rawSnippet = item["snippet"] as? String ?? ""
            let snippet = rawSnippet
                .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)

            return IMSLPSearchResult(
                id: pageid,
                pageTitle: title,
                displayTitle: title,
                snippet: snippet
            )
        }
    }
}

// MARK: - Title Parsing Helper

extension IMSLPSearchResult {
    /// "Work Title (Composer Last, First)" 형식에서 곡명과 작곡가를 분리한다.
    /// 예: "Waltz in B minor, Op.69 No.2 (Chopin, Frédéric)" →
    ///     title: "Waltz in B minor, Op.69 No.2", composer: "Frédéric Chopin"
    func parsedTitleAndComposer() -> (title: String, composer: String) {
        let pattern = #"^(.+?)\s*\(([^,)]+),\s*([^)]+)\)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                  in: displayTitle,
                  range: NSRange(displayTitle.startIndex..., in: displayTitle)
              ),
              match.numberOfRanges == 4,
              let r1 = Range(match.range(at: 1), in: displayTitle),
              let r2 = Range(match.range(at: 2), in: displayTitle),
              let r3 = Range(match.range(at: 3), in: displayTitle)
        else {
            return (displayTitle, "")
        }
        let workTitle  = String(displayTitle[r1])
        let lastName   = String(displayTitle[r2]).trimmingCharacters(in: .whitespaces)
        let firstName  = String(displayTitle[r3]).trimmingCharacters(in: .whitespaces)
        return (workTitle, "\(firstName) \(lastName)")
    }
}
