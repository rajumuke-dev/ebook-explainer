import AppKit
import Foundation

@MainActor
final class AppModel: ObservableObject {
    @Published var book: Book?
    @Published var selectedID: Int?
    @Published var isOpening = false
    @Published var openError: String?
    @Published private(set) var lessons: [Int: Lesson] = [:]
    @Published private(set) var lessonErrors: [Int: String] = [:]
    @Published private(set) var images: [String: NSImage] = [:]
    @Published private(set) var imageErrors: [String: String] = [:]
    @Published private(set) var apiKey: String?
    @Published var provider: Provider {
        didSet { UserDefaults.standard.set(provider.rawValue, forKey: "provider") }
    }

    @Published var voiceEngine: VoiceEngine {
        didSet { UserDefaults.standard.set(voiceEngine.rawValue, forKey: "voiceEngine") }
    }

    init() {
        provider = UserDefaults.standard.string(forKey: "provider").flatMap(Provider.init) ?? .free
        voiceEngine = UserDefaults.standard.string(forKey: "voiceEngine").flatMap(VoiceEngine.init) ?? .mac
        reloadKey()
    }

    /// nil only when OpenAI is selected without a key.
    var client: AIClient? {
        switch provider {
        case .free: AIClient(provider: .free, apiKey: nil)
        case .openai: apiKey.map { AIClient(provider: .openai, apiKey: $0) }
        }
    }
    /// OpenAI client for narration; nil means use the built-in Mac voice.
    var speechClient: AIClient? {
        voiceEngine == .openai ? apiKey.map { AIClient(provider: .openai, apiKey: $0) } : nil
    }
    /// Changes whenever lessons should be (re)attempted.
    var clientID: String { "\(provider.rawValue)-\(apiKey != nil)" }
    var selectedChapter: Chapter? { book?.chapters.first { $0.id == selectedID } }

    func reloadKey() {
        let env = ProcessInfo.processInfo.environment["OPENAI_API_KEY"]
        apiKey = Keychain.read() ?? (env?.isEmpty == false ? env : nil)
    }

    func open(_ url: URL) {
        isOpening = true
        Task {
            do {
                let book = try await Task.detached(priority: .userInitiated) { try BookLoader.load(url) }.value
                lessons = [:]; lessonErrors = [:]; images = [:]; imageErrors = [:]
                self.book = book
                selectedID = book.chapters.first?.id
            } catch {
                openError = error.localizedDescription
            }
            isOpening = false
        }
    }

    private var generating: Set<Int> = []

    func prepare(_ chapter: Chapter) async {
        guard let book, lessons[chapter.id] == nil, !generating.contains(chapter.id) else { return }
        lessonErrors[chapter.id] = nil
        let file = cacheDir(book).appendingPathComponent("chapter-\(chapter.id).json")

        if let data = try? Data(contentsOf: file), let cached = try? JSONDecoder().decode(Lesson.self, from: data) {
            lessons[chapter.id] = cached
            drawImages(cached, chapter.id, book)
            return
        }
        guard let client else {
            lessonErrors[chapter.id] = "Add your OpenAI API key in Settings (⌘,), or switch to the free provider."
            return
        }

        generating.insert(chapter.id)
        defer { generating.remove(chapter.id) }
        do {
            let references = await WebReferences.search(chapterTitle: chapter.title, bookTitle: book.title)
            var lesson = try await client.lesson(for: chapter, bookTitle: book.title, references: references)
            lesson.references = references
            try? JSONEncoder().encode(lesson).write(to: file)
            guard self.book?.cacheKey == book.cacheKey else { return }
            lessons[chapter.id] = lesson
            drawImages(lesson, chapter.id, book)
        } catch {
            guard self.book?.cacheKey == book.cacheKey else { return }
            lessonErrors[chapter.id] = error.localizedDescription
        }
    }

    private func drawImages(_ lesson: Lesson, _ chapterID: Int, _ book: Book) {
        // One at a time: the free tier allows about one image every 45 seconds.
        Task {
            for (i, step) in lesson.steps.enumerated() {
                let key = Lesson.imageKey(chapterID, i)
                let file = cacheDir(book).appendingPathComponent("\(key).img")
                if let image = NSImage(contentsOf: file) {
                    images[key] = image
                    continue
                }
                guard let client else {
                    imageErrors[key] = "Pictures need the free provider or an API key."
                    continue
                }
                do {
                    let data = try await client.image(prompt: step.imagePrompt)
                    guard let image = NSImage(data: data) else { throw AppError("The picture couldn't be read.") }
                    try? data.write(to: file)
                    guard self.book?.cacheKey == book.cacheKey else { return }
                    images[key] = image
                } catch {
                    guard self.book?.cacheKey == book.cacheKey else { return }
                    imageErrors[key] = error.localizedDescription
                }
            }
        }
    }

    private func cacheDir(_ book: Book) -> URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("EbookExplainer/\(book.cacheKey)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
