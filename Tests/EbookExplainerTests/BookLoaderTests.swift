import AppKit
import Foundation
import XCTest
@testable import EbookExplainer

private func tempDir() throws -> URL {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ebook-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

private let longText = String(repeating: "A packet travels across the network like a letter in the mail. ", count: 10)

final class BookLoaderTests: XCTestCase {

func testHtmlToTextStripsTagsScriptsAndDecodesEntities() {
    let html = "<html><head><title>T</title></head><body><script>evil()</script><h1>Intro</h1><p>a &lt;b&gt; &amp; c</p></body></html>"
    XCTAssertEqual(BookLoader.htmlToText(html), "Intro\na <b> & c")
}

func testLoadsEpubChaptersInSpineOrder() throws {
    let dir = try tempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let src = dir.appendingPathComponent("src")
    let files: [String: String] = [
        "mimetype": "application/epub+zip",
        "META-INF/container.xml": #"<container><rootfiles><rootfile full-path="OEBPS/content.opf"/></rootfiles></container>"#,
        "OEBPS/content.opf": """
        <package><metadata><dc:title>Networks 101</dc:title></metadata>
        <manifest>
          <item href="ch2.xhtml" id="c2" media-type="application/xhtml+xml"/>
          <item id="c1" href="ch1.xhtml" media-type="application/xhtml+xml"/>
          <item id="cover" href="cover.xhtml" media-type="application/xhtml+xml"/>
          <item id="bad" href="../../../etc/hosts" media-type="application/xhtml+xml"/>
        </manifest>
        <spine><itemref idref="cover"/><itemref idref="c1"/><itemref idref="c2"/><itemref idref="bad"/></spine></package>
        """,
        "OEBPS/cover.xhtml": "<html><body><img src='c.png'/></body></html>",
        "OEBPS/ch1.xhtml": "<html><body><h1>Packets</h1><p>\(longText)</p></body></html>",
        "OEBPS/ch2.xhtml": "<html><head><title>Routing</title></head><body><p>\(longText)</p></body></html>",
    ]
    for (path, content) in files {
        let url = src.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try content.write(to: url, atomically: true, encoding: .utf8)
    }
    let epub = dir.appendingPathComponent("book.epub")
    let zip = Process()
    zip.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
    zip.currentDirectoryURL = src
    zip.arguments = ["-qr", epub.path, "."]
    try zip.run()
    zip.waitUntilExit()

    let book = try BookLoader.load(epub)
    XCTAssertEqual(book.title, "Networks 101")
    XCTAssertEqual(book.chapters.map(\.title), ["Packets", "Routing"])
    XCTAssertEqual(book.chapters.map(\.id), [0, 1])
    XCTAssertTrue(book.chapters[0].text.contains("letter in the mail"))
}

func testPdfWithoutOutlineIsSplitIntoPageChunks() throws {
    let dir = try tempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let url = dir.appendingPathComponent("book.pdf")
    var box = CGRect(x: 0, y: 0, width: 612, height: 792)
    let ctx = try XCTUnwrap(CGContext(url as CFURL, mediaBox: &box, nil))
    for _ in 0..<20 {
        ctx.beginPDFPage(nil)
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        (longText as NSString).draw(in: box.insetBy(dx: 40, dy: 40), withAttributes: [.font: NSFont.systemFont(ofSize: 12)])
        ctx.endPDFPage()
    }
    ctx.closePDF()

    let book = try BookLoader.load(url)
    XCTAssertEqual(book.chapters.map(\.title), ["Pages 1–15", "Pages 16–20"])
    XCTAssertTrue(book.chapters[0].text.contains("packet travels"))
}

func testRejectsUnsupportedFiles() throws {
    let dir = try tempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let url = dir.appendingPathComponent("notes.txt")
    try "hello".write(to: url, atomically: true, encoding: .utf8)
    XCTAssertThrowsError(try BookLoader.load(url)) { XCTAssertTrue($0 is AppError) }
}

func testLessonDecodesAndBuildsSlides() throws {
    let json = """
    {"title":"T","hook":"H","steps":[{"heading":"S1","explanation":"E1","emoji":"📦","imagePrompt":"P1"},
    {"heading":"S2","explanation":"E2","imagePrompt":"P2"}],"example":"X","recap":"R",
    "quiz":[{"question":"Q","options":["a","b"],"answerIndex":1}]}
    """
    let lesson = try JSONDecoder().decode(Lesson.self, from: Data(json.utf8))
    let slides = lesson.slides(chapterID: 3)
    XCTAssertEqual(slides.map(\.heading), ["T", "S1", "S2", "Real-life example", "Quick recap"])
    XCTAssertEqual(slides.map(\.imageKey), [nil, "c3-s0", "c3-s1", nil, nil])
    XCTAssertEqual(slides[1].narration, "S1. E1")
    XCTAssertEqual(slides.map(\.emoji), ["🚀", "📦", "💡", "🌍", "⭐️"])  // missing step emoji falls back
}

func testLessonWithFunFactAddsSlideBeforeRecap() throws {
    let json = """
    {"title":"T","hook":"H","steps":[],"example":"X","recap":"R","funFact":"F","quiz":[]}
    """
    let slides = try JSONDecoder().decode(Lesson.self, from: Data(json.utf8)).slides(chapterID: 0)
    XCTAssertEqual(slides.map(\.heading), ["T", "Real-life example", "Did you know?", "Quick recap"])
}

func testReferenceQueryCleansChapterTitles() {
    XCTAssertEqual(WebReferences.query(chapterTitle: "Chapter 4: Domain Name System", bookTitle: "B"), "Domain Name System")
    XCTAssertEqual(WebReferences.query(chapterTitle: "2.1 Routing", bookTitle: "B"), "Routing")
    XCTAssertEqual(WebReferences.query(chapterTitle: "Chapter IV. Caching", bookTitle: "B"), "Caching")
    XCTAssertEqual(WebReferences.query(chapterTitle: "Civil Engineering", bookTitle: "B"), "Civil Engineering")
    XCTAssertEqual(WebReferences.query(chapterTitle: "Introduction", bookTitle: "Networks 101"), "Networks 101")
    XCTAssertEqual(WebReferences.query(chapterTitle: "Pages 1–15", bookTitle: "Networks 101"), "Networks 101")
}
}
