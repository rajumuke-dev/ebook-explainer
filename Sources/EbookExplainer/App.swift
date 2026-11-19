import AppKit
import SwiftUI
import UniformTypeIdentifiers

@main
struct EbookExplainerApp: App {
    @StateObject private var model = AppModel()

    init() {
        // Needed when launched via `swift run` (outside an .app bundle).
        NSApplication.shared.setActivationPolicy(.regular)
    }

    var body: some Scene {
        WindowGroup("Ebook Explainer") {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 960, minHeight: 640)
                .onAppear { NSApp.activate(ignoringOtherApps: true) }
        }
        Settings {
            SettingsView().environmentObject(model)
        }
    }
}

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @AppStorage("mode") private var mode: Mode = .listen
    @StateObject private var importing = ViewState(false)

    var body: some View {
        NavigationSplitView {
            List(model.book?.chapters ?? [], selection: $model.selectedID) { chapter in
                Text(chapter.title).lineLimit(2).tag(chapter.id)
            }
            .navigationTitle(model.book?.title ?? "No book yet")
            .navigationSplitViewColumnWidth(min: 220, ideal: 280)
        } detail: {
            if model.isOpening {
                ProgressView("Reading your book…").controlSize(.large)
            } else if let chapter = model.selectedChapter {
                LessonScreen(chapter: chapter, mode: mode).id(chapter.id)
            } else {
                ContentUnavailableView {
                    Label("Drop a technical ebook here", systemImage: "books.vertical")
                } description: {
                    Text("PDF or EPUB. Each chapter becomes a picture story you can read or listen to — explained like you're 10.")
                } actions: {
                    Button("Open Book…") { importing.value = true }.buttonStyle(.borderedProminent)
                    if model.client == nil { SettingsLink { Text("Add OpenAI API key") } }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Mode", selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .help("Read: text and pictures · Listen: narrated slideshow · Read + Listen: both")
            }
            ToolbarItem {
                Button { importing.value = true } label: { Label("Open Book", systemImage: "plus") }
                    .keyboardShortcut("o")
            }
        }
        .fileImporter(isPresented: $importing.value, allowedContentTypes: [.pdf, .epub]) { result in
            if case let .success(url) = result { model.open(url) }
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            model.open(url)
            return true
        }
        .alert("Couldn't open book", isPresented: Binding(get: { model.openError != nil }, set: { if !$0 { model.openError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.openError ?? "")
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @StateObject private var key = ViewState("")
    @StateObject private var status = ViewState("")

    var body: some View {
        Form {
            Picker("AI provider", selection: $model.provider) {
                ForEach(Provider.allCases) { Text($0.label).tag($0) }
            }
            Text(model.provider == .free
                 ? "Free: no key needed. About one picture every 45 seconds."
                 : "OpenAI: faster lessons and pictures. Uses your OpenAI credits.")
                .font(.caption).foregroundStyle(.secondary)
            Divider()
            SecureField("OpenAI API key", text: $key.value)
            HStack {
                Button("Save") {
                    let ok = Keychain.save(key.value.trimmingCharacters(in: .whitespacesAndNewlines))
                    status.value = ok ? "Saved to Keychain ✓" : "Couldn't save to Keychain"
                    key.value = ""
                    model.reloadKey()
                }
                .disabled(key.value.trimmingCharacters(in: .whitespaces).isEmpty)
                Button("Remove") {
                    Keychain.save("")
                    model.reloadKey()
                    status.value = "Removed"
                }
                Text(status.value).foregroundStyle(.secondary)
            }
            Text(model.apiKey == nil ? "No key set. Create one at platform.openai.com/api-keys." : "A key is set ✓")
            Text("Chapter text is sent to the selected AI provider, and chapter titles to Wikipedia for background reading. Lessons and pictures are cached on this Mac, so reopening a chapter costs nothing.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(width: 480)
    }
}
