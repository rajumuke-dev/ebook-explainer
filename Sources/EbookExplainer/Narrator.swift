import AVFoundation
import Foundation

/// Plays lesson slides aloud one after another with a female voice: OpenAI's when a cloud `voice`
/// client is given, otherwise (or on any failure) the free built-in macOS voice.
@MainActor
final class Narrator: NSObject, ObservableObject, AVAudioPlayerDelegate, AVSpeechSynthesizerDelegate {
    @Published private(set) var index = 0
    @Published private(set) var isPlaying = false
    @Published private(set) var isPaused = false
    @Published private(set) var isLoadingAudio = false

    private var task: Task<Void, Never>?
    private var player: AVAudioPlayer?
    private var utterance: AVSpeechUtterance?
    private let synth = AVSpeechSynthesizer()
    private var continuation: CheckedContinuation<Void, Never>?
    private var audio: [String: Task<Data, Error>] = [:]

    override init() {
        super.init()
        synth.delegate = self
    }

    func play(_ slides: [Slide], from start: Int, voice: AIClient?) {
        stop()
        let start = min(max(start, 0), slides.count)
        index = start
        isPlaying = true
        task = Task {
            for i in start..<slides.count {
                index = i
                if let voice, i + 1 < slides.count { _ = audioTask(slides[i + 1].narration, voice) }
                await speak(slides[i].narration, voice)
                if Task.isCancelled { return }
            }
            index = slides.count
            isPlaying = false
        }
    }

    func togglePause() {
        guard isPlaying else { return }
        isPaused.toggle()
        if isPaused {
            player?.pause()
            synth.pauseSpeaking(at: .word)
        } else {
            player?.play()
            synth.continueSpeaking()
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        player?.stop()
        synth.stopSpeaking(at: .immediate)
        isPlaying = false
        isPaused = false
        isLoadingAudio = false
        finishCurrent()
    }

    private func audioTask(_ text: String, _ client: AIClient) -> Task<Data, Error> {
        if let existing = audio[text] { return existing }
        let task = Task { try await client.speech(text) }
        audio[text] = task
        return task
    }

    private func speak(_ text: String, _ voice: AIClient?) async {
        var data: Data?
        if let voice {
            isLoadingAudio = true
            data = try? await audioTask(text, voice).value
            if !Task.isCancelled { isLoadingAudio = false }
        }
        guard !Task.isCancelled else { return }
        await withCheckedContinuation { c in
            continuation = c
            if let data, let p = try? AVAudioPlayer(data: data) {
                p.delegate = self
                player = p
                if p.play() { return }
                player = nil
            }
            let u = AVSpeechUtterance(string: text)
            u.rate = 0.48
            u.voice = Self.femaleVoice
            utterance = u
            synth.speak(u)
        }
    }

    /// Best-quality installed female English voice, preferring US English (e.g. Samantha).
    static let femaleVoice = AVSpeechSynthesisVoice.speechVoices()
        .filter { $0.language.hasPrefix("en") && $0.gender == .female && !$0.voiceTraits.contains(.isNoveltyVoice) }
        .max { ($0.quality.rawValue, $0.language == "en-US" ? 1 : 0) < ($1.quality.rawValue, $1.language == "en-US" ? 1 : 0) }

    private func finishCurrent() {
        player = nil
        utterance = nil
        continuation?.resume()
        continuation = nil
    }

    nonisolated func audioPlayerDidFinishPlaying(_ p: AVAudioPlayer, successfully flag: Bool) {
        let id = ObjectIdentifier(p)
        Task { @MainActor in if self.player.map(ObjectIdentifier.init) == id { self.finishCurrent() } }
    }

    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish u: AVSpeechUtterance) {
        let id = ObjectIdentifier(u)
        Task { @MainActor in if self.utterance.map(ObjectIdentifier.init) == id { self.finishCurrent() } }
    }
}
