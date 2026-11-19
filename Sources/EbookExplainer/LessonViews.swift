import SwiftUI

struct LessonScreen: View {
    let chapter: Chapter
    let mode: Mode
    @EnvironmentObject private var model: AppModel
    @StateObject private var narrator = Narrator()

    var body: some View {
        Group {
            if let lesson = model.lessons[chapter.id] {
                let slides = lesson.slides(chapterID: chapter.id)
                switch mode {
                case .listen: ListenView(lesson: lesson, slides: slides, narrator: narrator)
                case .read: ReadView(lesson: lesson, slides: slides, narrator: narrator, showsPlayer: false)
                case .both: ReadView(lesson: lesson, slides: slides, narrator: narrator, showsPlayer: true)
                }
            } else if let error = model.lessonErrors[chapter.id] {
                ContentUnavailableView {
                    Label("Couldn't make this lesson", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error)
                } actions: {
                    Button("Try again") { Task { await model.prepare(chapter) } }
                    if model.client == nil { SettingsLink { Text("Open Settings") } }
                }
            } else {
                VStack(spacing: 16) {
                    ProgressView().controlSize(.large)
                    Text("Turning “\(chapter.title)” into a fun story… 🪄").font(.title3)
                    Text("This usually takes 10–30 seconds.").foregroundStyle(.secondary)
                }
            }
        }
        .task(id: model.clientID) { await model.prepare(chapter) }
        .onChange(of: mode) { narrator.stop() }
        .onDisappear { narrator.stop() }
    }
}

struct ListenView: View {
    let lesson: Lesson
    let slides: [Slide]
    @ObservedObject var narrator: Narrator
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 20) {
            if narrator.index < slides.count {
                let slide = slides[narrator.index]
                Text("\(slide.emoji) \(slide.heading)")
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)
                if let key = slide.imageKey {
                    LessonImage(key: key, emoji: slide.emoji).frame(maxHeight: .infinity)
                } else {
                    Text(slide.emoji).font(.system(size: 160)).frame(maxHeight: .infinity)
                }
                ScrollView {
                    Text(slide.text).font(.title3).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                .frame(maxWidth: 720, maxHeight: 140)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        QuizView(quiz: lesson.quiz)
                        ReferencesView(references: lesson.references ?? [])
                    }
                    .frame(maxWidth: 720)
                }
            }
            PlayerControls(slides: slides, narrator: narrator)
        }
        .padding(30)
        .onAppear { narrator.play(slides, from: 0, voice: model.speechClient) }
    }
}

struct ReadView: View {
    let lesson: Lesson
    let slides: [Slide]
    @ObservedObject var narrator: Narrator
    let showsPlayer: Bool

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        ForEach(slides.indices, id: \.self) { i in
                            SlideCard(slide: slides[i], highlighted: showsPlayer && narrator.isPlaying && narrator.index == i)
                                .id(i)
                        }
                        QuizView(quiz: lesson.quiz).id(slides.count)
                        ReferencesView(references: lesson.references ?? [])
                    }
                    .padding(30)
                    .frame(maxWidth: 820)
                    .frame(maxWidth: .infinity)
                }
                .onChange(of: narrator.index) { _, i in
                    if showsPlayer { withAnimation { proxy.scrollTo(i, anchor: .top) } }
                }
            }
            if showsPlayer {
                Divider()
                PlayerControls(slides: slides, narrator: narrator).padding(12)
            }
        }
    }
}

struct SlideCard: View {
    let slide: Slide
    let highlighted: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("\(slide.emoji) \(slide.heading)").font(.title2.bold())
            if let key = slide.imageKey { LessonImage(key: key, emoji: slide.emoji).frame(height: 340) }
            Text(slide.text)
                .font(.title3)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 20).fill(.background.secondary))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(highlighted ? Color.accentColor : .clear, lineWidth: 3))
    }
}

struct LessonImage: View {
    let key: String
    let emoji: String
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Group {
            if let image = model.images[key] {
                Image(nsImage: image).resizable().scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            } else {
                // Emoji stand in for the picture until it arrives (or if drawing fails).
                VStack(spacing: 12) {
                    Text(emoji).font(.system(size: 110))
                    if let error = model.imageErrors[key] {
                        Label(error, systemImage: "photo.badge.exclamationmark")
                    } else {
                        ProgressView("Drawing a picture…").controlSize(.small)
                    }
                }
                .font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 200)
    }
}

struct PlayerControls: View {
    let slides: [Slide]
    @ObservedObject var narrator: Narrator
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 28) {
            Button { narrator.play(slides, from: narrator.index - 1, voice: model.speechClient) } label: {
                Image(systemName: "backward.fill")
            }
            .disabled(narrator.index == 0)
            .help("Previous")

            Button {
                if narrator.isPlaying {
                    narrator.togglePause()
                } else {
                    narrator.play(slides, from: narrator.index >= slides.count ? 0 : narrator.index, voice: model.speechClient)
                }
            } label: {
                Image(systemName: narrator.isPlaying && !narrator.isPaused ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 46))
            }
            .keyboardShortcut(.space, modifiers: [])
            .help("Play / Pause (Space)")

            Button { narrator.play(slides, from: narrator.index + 1, voice: model.speechClient) } label: {
                Image(systemName: "forward.fill")
            }
            .disabled(narrator.index >= slides.count)
            .help("Next")

            Text(narrator.index < slides.count ? "\(narrator.index + 1) / \(slides.count)" : "Quiz")
                .monospacedDigit().foregroundStyle(.secondary)
            if narrator.isLoadingAudio { ProgressView().controlSize(.small) }

            Picker("Voice", selection: $model.voiceEngine) {
                ForEach(VoiceEngine.allCases) { engine in
                    Text(engine == .openai && model.apiKey == nil ? "\(engine.label) – needs API key" : engine.label).tag(engine)
                }
            }
            .pickerStyle(.menu)
            .fixedSize()
            .font(.body)
            .help("Both voices are female. The Mac voice is free; the OpenAI voice needs a key in Settings.")
        }
        .buttonStyle(.plain)
        .font(.title2)
        .onChange(of: model.voiceEngine) {
            // Re-read the current slide with the newly chosen voice.
            if narrator.isPlaying { narrator.play(slides, from: narrator.index, voice: model.speechClient) }
        }
    }
}

struct ReferencesView: View {
    let references: [Reference]

    var body: some View {
        if !references.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("📚 Learn more online").font(.title2.bold())
                ForEach(references, id: \.url) { ref in
                    if let url = URL(string: ref.url) {
                        Link(destination: url) {
                            Text("\(ref.title) — \(ref.source)")
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct QuizView: View {
    let quiz: [Lesson.Question]
    @StateObject private var answers = ViewState<[Int: Int]>([:])
    private var picked: [Int: Int] { answers.value }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("🧠 Quiz time!").font(.title.bold())
            ForEach(quiz.indices, id: \.self) { q in
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(q + 1). \(quiz[q].question)").font(.headline)
                    ForEach(quiz[q].options.indices, id: \.self) { o in
                        Button { answers.value[q] = o } label: {
                            HStack {
                                Text(quiz[q].options[o])
                                Spacer()
                                if picked[q] == o { Text(o == quiz[q].answerIndex ? "✅" : "❌") }
                            }
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 10).fill(color(q, o).opacity(0.2)))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            if !quiz.isEmpty, picked.count == quiz.count {
                let score = quiz.indices.filter { picked[$0] == quiz[$0].answerIndex }.count
                Text("You got \(score) out of \(quiz.count)! \(score == quiz.count ? "🏆" : "🎉")").font(.title2.bold())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func color(_ q: Int, _ o: Int) -> Color {
        guard let choice = picked[q] else { return .gray }
        if o == quiz[q].answerIndex { return .green }
        return o == choice ? .red : .gray
    }
}
