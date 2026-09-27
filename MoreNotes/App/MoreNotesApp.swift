import SwiftUI
import SwiftData

@main
struct MoreNotesApp: App {
    /// One SwiftData container for the whole app. All notebooks, pages,
    /// recognized text, embeddings, tutor findings and quiz history live here.
    let container: ModelContainer

    @State private var appState = AppState()

    init() {
        let schema = Schema([
            Notebook.self,
            Page.self,
            NoteChunk.self,
            Concept.self,
            TutorFinding.self,
            Quiz.self,
            QuizQuestion.self,
            ChatMessageRecord.self,
        ])
        let config = ModelConfiguration("MoreNotes", schema: schema, isStoredInMemoryOnly: false)
        do {
            container = try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Could not create SwiftData container: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appState)
        }
        .modelContainer(container)
    }
}

/// Lightweight app-wide observable state that is not persisted.
@Observable
final class AppState {
    /// The drawing tool configuration shared across pages.
    var tools = ToolState()
    /// Whether the AI side panel is visible in the editor.
    var showAIPanel = true
    /// Whether the live tutor watches the page and flags mistakes.
    var liveTutorEnabled = true
    /// Whether the user can draw with a finger (in addition to the pencil).
    var allowFingerDrawing = false
    /// User-facing settings (persisted via UserDefaults inside Settings).
    var settings = Settings.load()
}
