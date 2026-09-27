import SwiftUI
import SwiftData
import PencilKit

/// The AI side panel: Tutor tab (findings on this page) and Chat tab (ask anything
/// about your notes, with retrieval across every notebook).
struct AIPanelView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var appState

    let page: Page
    let drawing: PKDrawing
    let tutorStatus: TutorStatus
    @Binding var selectedFindingID: UUID?
    var onCheckWork: (String?) -> Void
    var onJumpToPage: (UUID) -> Void

    @State private var tab = 0

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) {
                Text("Tutor").tag(0)
                Text("Chat").tag(1)
            }
            .pickerStyle(.segmented)
            .padding(10)
            Divider()
            if tab == 0 {
                TutorTabView(page: page, tutorStatus: tutorStatus, selectedFindingID: $selectedFindingID, onCheckWork: onCheckWork)
            } else {
                ChatTabView(notebook: page.notebook, page: page, drawing: drawing, onJumpToPage: onJumpToPage)
            }
        }
        .background(Color(uiColor: .secondarySystemBackground))
    }
}

// MARK: - Tutor tab

struct TutorTabView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var appState
    let page: Page
    let tutorStatus: TutorStatus
    @Binding var selectedFindingID: UUID?
    var onCheckWork: (String?) -> Void

    @State private var question = ""

    private var activeFindings: [TutorFinding] {
        page.findings.filter { !$0.dismissed }.sorted { severityRank($0.severity) < severityRank($1.severity) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                statusCard

                HStack {
                    Button {
                        onCheckWork(question.isEmpty ? nil : question)
                        question = ""
                    } label: {
                        Label("Check my work", systemImage: "checkmark.seal")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(tutorStatus == .reviewing)
                }
                TextField("Ask about this page (optional): e.g. is step 3 right?", text: $question, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...3)

                if !activeFindings.isEmpty {
                    Text("On this page").font(.headline)
                    ForEach(activeFindings) { f in
                        Button { selectedFindingID = f.id } label: {
                            HStack(alignment: .top, spacing: 10) {
                                Circle().fill(color(for: f.severity)).frame(width: 10, height: 10).padding(.top, 5)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(f.title).font(.subheadline.weight(.medium))
                                    Text(f.hint).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                                }
                                Spacer()
                            }
                            .padding(10)
                            .background(Color(uiColor: .tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
                            .overlay {
                                if selectedFindingID == f.id { RoundedRectangle(cornerRadius: 10).strokeBorder(Color.accentColor, lineWidth: 2) }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }

                if let transcript = page.aiTranscript, !transcript.isEmpty {
                    DisclosureGroup("What the tutor read") {
                        Text(transcript).font(.caption.monospaced()).textSelection(.enabled)
                    }
                    .font(.subheadline)
                }

                Text(appState.liveTutorEnabled
                     ? "Live Tutor is on: the page is reviewed about \(Int(appState.settings.tutorIdleSeconds)) s after your pencil rests."
                     : "Live Tutor is off. Use Check my work, or turn it on from the toolbar.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            .padding(12)
        }
    }

    @ViewBuilder
    private var statusCard: some View {
        switch tutorStatus {
        case .idle:
            if activeFindings.isEmpty {
                Label("Write something and the tutor will follow along.", systemImage: "pencil.and.scribble")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        case .reviewing:
            HStack { ProgressView().controlSize(.small); Text("Reading your page…").font(.subheadline) }
        case .reviewed(let summary, let overall, let nextStep, let at):
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: overall == "correct" ? "checkmark.circle.fill" : (overall == "issues_found" ? "exclamationmark.circle.fill" : "info.circle.fill"))
                        .foregroundStyle(overall == "correct" ? .green : (overall == "issues_found" ? .orange : .blue))
                    Text(overallLabel(overall)).font(.headline)
                    Spacer()
                    Text(at, style: .time).font(.caption2).foregroundStyle(.secondary)
                }
                Text(summary).font(.subheadline)
                if !nextStep.isEmpty {
                    Text("Next: \(nextStep)").font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .background(Color(uiColor: .tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.red)
        }
    }

    private func overallLabel(_ s: String) -> String {
        switch s {
        case "correct": return "Looks right"
        case "issues_found": return "Something to look at"
        case "incomplete": return "Not finished yet"
        case "not_academic_work": return "Nothing to check"
        default: return s
        }
    }

    private func severityRank(_ s: FindingSeverity) -> Int {
        switch s { case .error: return 0; case .warning: return 1; case .hint: return 2; case .praise: return 3 }
    }

    private func color(for s: FindingSeverity) -> Color {
        switch s { case .error: return .red; case .warning: return .orange; case .hint: return .blue; case .praise: return .green }
    }
}

// MARK: - Chat tab

struct ChatTabView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var appState
    let notebook: Notebook?
    let page: Page
    let drawing: PKDrawing
    var onJumpToPage: (UUID) -> Void

    @State private var input = ""
    @State private var streamingText = ""
    @State private var isStreaming = false
    @State private var streamTask: Task<Void, Never>?
    @State private var error: String?

    private var history: [ChatMessageRecord] {
        (notebook?.chatHistory ?? []).sorted { $0.createdAt < $1.createdAt }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        if history.isEmpty && !isStreaming {
                            suggestions
                        }
                        ForEach(history) { m in
                            bubble(text: m.text, isUser: m.roleRaw == "user").id(m.id)
                        }
                        if isStreaming {
                            bubble(text: streamingText.isEmpty ? "…" : streamingText, isUser: false).id("streaming")
                        }
                        if let error {
                            Text(error).font(.caption).foregroundStyle(.red)
                        }
                    }
                    .padding(12)
                }
                .onChange(of: streamingText) { _, _ in withAnimation { proxy.scrollTo("streaming", anchor: .bottom) } }
                .onChange(of: history.count) { _, _ in
                    if let last = history.last { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
            Divider()
            HStack(alignment: .bottom, spacing: 8) {
                TextField("Ask about your notes…", text: $input, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...5)
                    .onSubmit(send)
                if isStreaming {
                    Button { streamTask?.cancel() } label: { Image(systemName: "stop.circle.fill").font(.title2) }
                } else {
                    Button(action: send) { Image(systemName: "arrow.up.circle.fill").font(.title2) }
                        .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .padding(10)
            .background(Color(uiColor: .secondarySystemBackground))
        }
        .toolbar {
            ToolbarItem(placement: .secondaryAction) {
                Button(role: .destructive) { clearHistory() } label: { Label("Clear chat", systemImage: "trash") }
                    .disabled(history.isEmpty)
            }
        }
    }

    private var suggestions: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Try asking").font(.caption).foregroundStyle(.secondary)
            ForEach(["Explain what I wrote on this page in simpler terms",
                     "Where did I go wrong in this problem?",
                     "How does this connect to my other notes?",
                     "What should I review before an exam on this?"], id: \.self) { s in
                Button { input = s; send() } label: {
                    Text(s).font(.subheadline).multilineTextAlignment(.leading)
                        .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(uiColor: .tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func bubble(text: String, isUser: Bool) -> some View {
        HStack {
            if isUser { Spacer(minLength: 30) }
            Text(LocalizedStringKey(text))
                .textSelection(.enabled)
                .padding(10)
                .background(isUser ? Color.accentColor.opacity(0.9) : Color(uiColor: .tertiarySystemBackground),
                            in: RoundedRectangle(cornerRadius: 12))
                .foregroundStyle(isUser ? Color.white : Color.primary)
            if !isUser { Spacer(minLength: 30) }
        }
    }

    private func send() {
        let question = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !isStreaming else { return }
        input = ""
        error = nil

        // Build the turn before inserting the new user message so history excludes it.
        let turn = ChatService.shared.buildTurn(question: question, notebook: notebook, currentPage: page,
                                                currentDrawing: drawing, settings: appState.settings, context: context)
        let userRecord = ChatMessageRecord(role: "user", text: question)
        context.insert(userRecord)
        userRecord.notebook = notebook
        try? context.save()

        isStreaming = true
        streamingText = ""
        streamTask = Task {
            var full = ""
            do {
                for try await delta in ChatService.shared.stream(turn: turn, settings: appState.settings) {
                    full += delta
                    streamingText = full
                }
            } catch is CancellationError {
                // user stopped
            } catch {
                self.error = error.localizedDescription
            }
            if !full.isEmpty {
                let assistant = ChatMessageRecord(role: "assistant", text: full)
                context.insert(assistant)
                assistant.notebook = notebook
                try? context.save()
            }
            isStreaming = false
            streamingText = ""
        }
    }

    private func clearHistory() {
        for m in history { context.delete(m) }
        try? context.save()
    }
}
