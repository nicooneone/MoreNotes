import SwiftUI
import SwiftData

/// All quizzes across notebooks, plus generation.
struct QuizListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Quiz.createdAt, order: .reverse) private var quizzes: [Quiz]
    var openPage: (UUID) -> Void

    @State private var showGenerator = false

    var body: some View {
        List {
            if quizzes.isEmpty {
                ContentUnavailableView {
                    Label("No quizzes yet", systemImage: "checklist")
                } description: {
                    Text("Generate a quiz from your notes. The AI targets the concepts you have struggled with.")
                } actions: {
                    Button("Generate Quiz") { showGenerator = true }.buttonStyle(.borderedProminent)
                }
            }
            ForEach(quizzes) { quiz in
                NavigationLink {
                    QuizTakeView(quiz: quiz, openPage: openPage)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(quiz.title).font(.headline)
                        Text(quiz.focus).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        HStack {
                            let s = quiz.score
                            Text(quiz.completedAt == nil ? "\(s.total) questions" : "Score \(s.correct)/\(s.total)")
                            Spacer()
                            Text(quiz.createdAt, style: .date)
                        }
                        .font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            .onDelete { idx in
                for i in idx { context.delete(quizzes[i]) }
                try? context.save()
            }
        }
        .navigationTitle("Quizzes")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showGenerator = true } label: { Label("New Quiz", systemImage: "plus") }
            }
        }
        .sheet(isPresented: $showGenerator) { QuizGeneratorSheet(scope: .everything) }
    }
}

struct QuizGeneratorSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State var scope: QuizService.Scope
    @State private var count = 8
    @State private var working = false
    @State private var error: String?
    @State private var scopeChoice = 0

    init(scope: QuizService.Scope) {
        _scope = State(initialValue: scope)
        if case .notebook = scope { _scopeChoice = State(initialValue: 0) } else { _scopeChoice = State(initialValue: 1) }
    }

    private var notebookName: String? {
        if case .notebook(let nb) = scope { return nb.title }
        return nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("What to quiz") {
                    if let name = notebookName {
                        Picker("Scope", selection: $scopeChoice) {
                            Text("This notebook: \(name)").tag(0)
                            Text("Everything").tag(1)
                            Text("My weak spots").tag(2)
                        }
                    } else {
                        Picker("Scope", selection: $scopeChoice) {
                            Text("Everything").tag(1)
                            Text("My weak spots").tag(2)
                        }
                    }
                    Stepper("\(count) questions", value: $count, in: 3...20)
                }
                Section {
                    Text("Questions are generated from the text recognized in your handwriting, and target concepts you have missed on past quizzes or that the tutor flagged.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if let error {
                    Section { Text(error).foregroundStyle(.red).font(.footnote) }
                }
            }
            .navigationTitle("Generate Quiz")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(working) }
                ToolbarItem(placement: .confirmationAction) {
                    if working { ProgressView() } else { Button("Generate") { generate() } }
                }
            }
            .interactiveDismissDisabled(working)
        }
        .presentationDetents([.medium])
    }

    private func generate() {
        working = true
        error = nil
        let effective: QuizService.Scope
        switch scopeChoice {
        case 0: effective = scope
        case 2: effective = .weakSpots
        default: effective = .everything
        }
        Task {
            do {
                _ = try await QuizService.shared.generate(scope: effective, count: count, settings: appState.settings, context: context)
                dismiss()
            } catch {
                self.error = error.localizedDescription
            }
            working = false
        }
    }
}

/// Take a quiz question by question.
struct QuizTakeView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var appState
    @Bindable var quiz: Quiz
    var openPage: (UUID) -> Void

    @State private var index = 0
    @State private var answer = ""
    @State private var grading = false
    @State private var error: String?

    private var questions: [QuizQuestion] { quiz.sortedQuestions }
    private var question: QuizQuestion? { questions.indices.contains(index) ? questions[index] : nil }

    var body: some View {
        VStack(spacing: 0) {
            if let q = question {
                ProgressView(value: Double(index + 1), total: Double(max(1, questions.count)))
                    .padding(.horizontal)
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Text("Question \(index + 1) of \(questions.count)").font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Label(q.conceptName, systemImage: "tag").font(.caption).foregroundStyle(.secondary)
                        }
                        Text(LocalizedStringKey(q.prompt)).font(.title3).textSelection(.enabled)

                        if q.kind == .multipleChoice {
                            ForEach(q.choices, id: \.self) { choice in
                                Button {
                                    guard q.isCorrect == nil else { return }
                                    answer = choice
                                    submit()
                                } label: {
                                    HStack {
                                        Text(LocalizedStringKey(choice)).multilineTextAlignment(.leading)
                                        Spacer()
                                        if q.isCorrect != nil {
                                            if choice.caseInsensitiveCompare(q.correctAnswer) == .orderedSame {
                                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                                            } else if choice == q.userAnswer {
                                                Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
                                            }
                                        }
                                    }
                                    .padding()
                                    .frame(maxWidth: .infinity)
                                    .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
                                }
                                .buttonStyle(.plain)
                            }
                        } else {
                            if q.isCorrect == nil {
                                TextField(q.kind == .workedProblem ? "Work it out and write your final answer with the key steps" : "Your answer",
                                          text: $answer, axis: .vertical)
                                    .textFieldStyle(.roundedBorder)
                                    .lineLimit(2...8)
                                Button { submit() } label: {
                                    if grading { ProgressView() } else { Text("Submit").frame(maxWidth: .infinity) }
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(answer.trimmingCharacters(in: .whitespaces).isEmpty || grading)
                            } else {
                                GroupBox("Your answer") { Text(q.userAnswer ?? "").frame(maxWidth: .infinity, alignment: .leading) }
                            }
                        }

                        if let correct = q.isCorrect {
                            VStack(alignment: .leading, spacing: 8) {
                                Label(correct ? "Correct" : "Not quite", systemImage: correct ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .foregroundStyle(correct ? .green : .red).font(.headline)
                                if let fb = q.feedback { Text(LocalizedStringKey(fb)) }
                                if !correct {
                                    Text("Answer: \(q.correctAnswer)").font(.subheadline.weight(.medium))
                                    Text(LocalizedStringKey(q.explanation)).font(.subheadline).foregroundStyle(.secondary)
                                }
                                if let pid = q.sourcePageID {
                                    Button { openPage(pid) } label: { Label("Open the page this came from", systemImage: "doc.text.magnifyingglass") }
                                        .font(.subheadline)
                                }
                            }
                            .padding()
                            .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                        }

                        if let error { Text(error).foregroundStyle(.red).font(.footnote) }
                    }
                    .padding()
                }
                HStack {
                    Button { index -= 1; answer = "" } label: { Label("Previous", systemImage: "chevron.left") }.disabled(index == 0)
                    Spacer()
                    if index < questions.count - 1 {
                        Button { index += 1; answer = "" } label: { Label("Next", systemImage: "chevron.right") }
                    } else {
                        let s = quiz.score
                        Text("Score \(s.correct)/\(s.total)").font(.headline)
                    }
                }
                .padding()
            } else {
                ContentUnavailableView("No questions", systemImage: "questionmark")
            }
        }
        .navigationTitle(quiz.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func submit() {
        guard let q = question else { return }
        grading = true
        error = nil
        Task {
            do {
                try await QuizService.shared.grade(q, answer: answer, settings: appState.settings, context: context)
            } catch {
                self.error = error.localizedDescription
            }
            grading = false
        }
    }
}
