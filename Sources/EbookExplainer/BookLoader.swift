import CryptoKit
import Foundation
import PDFKit

enum BookLoader {
    static func load(_ url: URL) throws -> Book {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        let cacheKey = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined().prefix(24)
        let fallbackTitle = url.deletingPathExtension().lastPathComponent

        let (title, raw): (String?, [Chapter])
        switch url.pathExtension.lowercased() {
        case "pdf": (title, raw) = try pdfChapters(url)
        case "epub": (title, raw) = try epubChapters(url)
        default: throw AppError("Unsupported file type .\(url.pathExtension). Please use a PDF or EPUB.")
        }

        // Drop covers, blank pages and other near-empty sections.
        let chapters = raw.filter { $0.text.count > 200 }.enumerated().map { i, c in
            Chapter(id: i, title: c.title, text: c.text)
        }
        guard !chapters.isEmpty else {
            throw AppError("No readable text found. Scanned (image-only) books aren't supported.")
        }
        let cleanTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return Book(title: cleanTitle.isEmpty ? fallbackTitle : cleanTitle, chapters: chapters, cacheKey: String(cacheKey))
    }

    // MARK: PDF

    static func pdfChapters(_ url: URL) throws -> (String?, [Chapter]) {
        guard let doc = PDFDocument(url: url) else { throw AppError("Couldn't open this PDF.") }
        guard !doc.isLocked else { throw AppError("This PDF is password protected.") }
        let title = doc.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String

        // Use the table of contents when present; skip single wrapper levels (e.g. a root "Book" node).
        var marks: [(title: String, page: Int)] = []
        if var level = doc.outlineRoot {
            while level.numberOfChildren == 1, let only = level.child(at: 0) { level = only }
            for i in 0..<level.numberOfChildren {
                guard let item = level.child(at: i),
                      let page = (item.destination ?? (item.action as? PDFActionGoTo)?.destination)?.page
                else { continue }
                marks.append((item.label ?? "Section \(i + 1)", doc.index(for: page)))
            }
        }
        var seen = Set<Int>()
        marks = marks.sorted { $0.page < $1.page }.filter { seen.insert($0.page).inserted }

        func text(_ range: Range<Int>) -> String {
            range.compactMap { doc.page(at: $0)?.string }.joined(separator: "\n")
        }

        if marks.count >= 2 {
            return (title, marks.enumerated().map { i, mark in
                let end = i + 1 < marks.count ? marks[i + 1].page : doc.pageCount
                return Chapter(id: i, title: mark.title, text: text(mark.page..<max(end, mark.page + 1)))
            })
        }

        let size = 15
        return (title, stride(from: 0, to: doc.pageCount, by: size).enumerated().map { i, start in
            let end = min(start + size, doc.pageCount)
            return Chapter(id: i, title: "Pages \(start + 1)–\(end)", text: text(start..<end))
        })
    }

    // MARK: EPUB

    static func epubChapters(_ url: URL) throws -> (String?, [Chapter]) {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("ebook-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: dir) }

        let unzip = Process()
        unzip.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        unzip.arguments = ["-qq", "-o", url.path, "-d", dir.path]
        unzip.standardOutput = FileHandle.nullDevice
        unzip.standardError = FileHandle.nullDevice
        try unzip.run()
        unzip.waitUntilExit()
        // unzip exits 1 for warnings only.
        guard unzip.terminationStatus <= 1 else { throw AppError("Couldn't unpack this EPUB.") }

        let container = try String(contentsOf: dir.appendingPathComponent("META-INF/container.xml"), encoding: .utf8)
        guard let opfPath = container.captures(#"full-path\s*=\s*["']([^"']+)["']"#).first else {
            throw AppError("This EPUB is missing its package file.")
        }
        let root = dir.standardizedFileURL.path
        let opfURL = dir.appendingPathComponent(opfPath).standardizedFileURL
        guard opfURL.path.hasPrefix(root) else { throw AppError("Invalid EPUB.") }
        let opf = try String(contentsOf: opfURL, encoding: .utf8)
        let base = opfURL.deletingLastPathComponent()

        var manifest: [String: String] = [:]
        for tag in opf.captures(#"(<item\b[^>]*>)"#) {
            if let id = attribute("id", in: tag), let href = attribute("href", in: tag) { manifest[id] = href }
        }
        let title = opf.captures(#"<dc:title[^>]*>(.*?)</dc:title>"#).first.map(htmlToText)
        let spine = opf.captures(#"<itemref\b[^>]*\bidref\s*=\s*["']([^"']+)["']"#)

        let chapters: [Chapter] = spine.enumerated().compactMap { i, id in
            guard let href = manifest[id] else { return nil }
            let path = String(href.split(separator: "#").first ?? "")
            let file = base.appendingPathComponent(path.removingPercentEncoding ?? path).standardizedFileURL
            guard file.path.hasPrefix(root), let html = try? String(contentsOf: file, encoding: .utf8) else { return nil }
            let heading = (html.captures(#"<h[1-3][^>]*>(.*?)</h[1-3]>"#).first
                ?? html.captures(#"<title[^>]*>(.*?)</title>"#).first).map(htmlToText) ?? ""
            return Chapter(id: i, title: heading.isEmpty ? "Section \(i + 1)" : heading, text: htmlToText(html))
        }
        return (title, chapters)
    }

    static func attribute(_ name: String, in tag: String) -> String? {
        tag.captures(#"\b"# + name + #"\s*=\s*["']([^"']*)["']"#).first
    }

    static func htmlToText(_ html: String) -> String {
        html.replacingRegex(#"<(script|style|head)\b[^>]*>.*?</\1>"#, with: " ")
            .replacingRegex(#"<br\s*/?>|</(p|div|h[1-6]|li|tr|pre)>"#, with: "\n")
            .replacingRegex(#"<[^>]+>"#, with: "")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&#160;", with: " ")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingRegex(#"[ \t]+"#, with: " ")
            .replacingRegex(#"\s*\n\s*"#, with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension String {
    private static let regexOptions: NSRegularExpression.Options = [.caseInsensitive, .dotMatchesLineSeparators]

    func replacingRegex(_ pattern: String, with template: String) -> String {
        guard let re = try? NSRegularExpression(pattern: pattern, options: Self.regexOptions) else { return self }
        return re.stringByReplacingMatches(in: self, range: NSRange(startIndex..., in: self), withTemplate: template)
    }

    /// First capture group of every match.
    func captures(_ pattern: String) -> [String] {
        guard let re = try? NSRegularExpression(pattern: pattern, options: Self.regexOptions) else { return [] }
        return re.matches(in: self, range: NSRange(startIndex..., in: self)).compactMap {
            Range($0.range(at: 1), in: self).map { String(self[$0]) }
        }
    }
}
