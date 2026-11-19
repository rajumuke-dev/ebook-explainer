import Foundation

struct Reference: Codable, Hashable {
    let title: String
    let source: String
    let url: String
    let summary: String
}

/// Free, keyless background reading from Simple English Wikipedia (kid-friendly) and Wikipedia.
enum WebReferences {
    static func search(chapterTitle: String, bookTitle: String) async -> [Reference] {
        let query = query(chapterTitle: chapterTitle, bookTitle: bookTitle)
        async let simple = wikipedia("simple", "Simple English Wikipedia", query)
        async let english = wikipedia("en", "Wikipedia", query)
        return await simple + english
    }

    /// Strips "Chapter 3:"-style numbering; generic titles fall back to the book title.
    static func query(chapterTitle: String, bookTitle: String) -> String {
        let cleaned = chapterTitle
            .replacingRegex(#"^\s*((chapter|part|section|lesson)\s+[\divxlc]+|\d+(\.\d+)*)[\s.:)\-–]*"#, with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let generic: Set = ["", "introduction", "preface", "foreword", "conclusion", "summary", "index",
                            "appendix", "contents", "acknowledgements", "acknowledgments", "about the author"]
        if generic.contains(cleaned.lowercased()) || cleaned.hasPrefix("Pages ") || cleaned.hasPrefix("Section ") {
            return bookTitle
        }
        return cleaned
    }

    private static func wikipedia(_ language: String, _ source: String, _ query: String) async -> [Reference] {
        var components = URLComponents(string: "https://\(language).wikipedia.org/w/api.php")!
        components.queryItems = [
            "action": "query", "format": "json", "formatversion": "2", "redirects": "1",
            "generator": "search", "gsrsearch": String(query.prefix(200)), "gsrlimit": "2",
            "prop": "extracts|info", "exintro": "1", "explaintext": "1", "exlimit": "2", "inprop": "url",
        ].map { URLQueryItem(name: $0.key, value: $0.value) }
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 15
        request.setValue("EbookExplainer/1.0 (macOS learning app)", forHTTPHeaderField: "User-Agent")

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let pages = (json["query"] as? [String: Any])?["pages"] as? [[String: Any]]
        else { return [] }

        return pages
            .sorted { ($0["index"] as? Int ?? 0) < ($1["index"] as? Int ?? 0) }
            .compactMap { page in
                guard let title = page["title"] as? String,
                      let url = page["fullurl"] as? String, url.hasPrefix("https://"),
                      let extract = page["extract"] as? String, extract.count > 80
                else { return nil }
                return Reference(title: title, source: source, url: url, summary: String(extract.prefix(1000)))
            }
    }
}
