import Foundation

struct AppError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

struct Chapter: Identifiable, Hashable {
    let id: Int
    let title: String
    let text: String
}

struct Book {
    let title: String
    let chapters: [Chapter]
    /// Hash of the file contents; used as the on-disk cache folder name.
    let cacheKey: String
}

struct Lesson: Codable {
    var title: String
    var hook: String
    var steps: [Step]
    var example: String
    var recap: String
    var funFact: String?
    var quiz: [Question]
    /// Web pages used as background; filled in by the app, not the AI.
    var references: [Reference]?

    struct Step: Codable {
        var heading: String
        var explanation: String
        var emoji: String?
        var imagePrompt: String
    }

    struct Question: Codable {
        var question: String
        var options: [String]
        var answerIndex: Int
    }

    static func imageKey(_ chapterID: Int, _ step: Int) -> String { "c\(chapterID)-s\(step)" }

    func slides(chapterID: Int) -> [Slide] {
        [Slide(emoji: "🚀", heading: title, text: hook, imageKey: nil)]
            + steps.enumerated().map { i, step in
                Slide(emoji: step.emoji ?? "💡", heading: step.heading, text: step.explanation, imageKey: Self.imageKey(chapterID, i))
            }
            + [
                Slide(emoji: "🌍", heading: "Real-life example", text: example, imageKey: nil),
            ]
            + (funFact.map { [Slide(emoji: "🤓", heading: "Did you know?", text: $0, imageKey: nil)] } ?? [])
            + [Slide(emoji: "⭐️", heading: "Quick recap", text: recap, imageKey: nil)]
    }
}

struct Slide {
    let emoji: String
    let heading: String
    let text: String
    let imageKey: String?
    var narration: String { "\(heading). \(text)" }
}

enum VoiceEngine: String, CaseIterable, Identifiable {
    case mac, openai
    var id: Self { self }
    var label: String {
        switch self {
        case .mac: "Mac voice (free)"
        case .openai: "OpenAI voice (natural)"
        }
    }
}

enum Mode: String, CaseIterable, Identifiable {
    case read, listen, both
    var id: Self { self }
    var label: String {
        switch self {
        case .read: "Read"
        case .listen: "Listen"
        case .both: "Read + Listen"
        }
    }
}

/// Stand-in for SwiftUI's `@State`, whose macro plugin isn't shipped with the Command Line Tools.
final class ViewState<Value>: ObservableObject {
    @Published var value: Value
    init(_ value: Value) { self.value = value }
}
