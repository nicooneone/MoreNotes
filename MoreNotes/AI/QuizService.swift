import Foundation
import SwiftData

/// Generates quizzes from the user's notes and grades free-form answers.
@MainActor
final class QuizService {
    static let shared = QuizService()

    struct Generated: Decodable {
        struct Question: Decodable {
            let kind: String
            let prompt: String
            let choices: [String]
            let correct_answer: String
            let explanation: String
            let concept: String
            let source_page_label: String
        }
        let title: String
        let questions: [Question]
    }

    static let generateSchema: [String: Any] = [
        "type": "object",
        "additionalProperties": false,
        "required": ["title", "questions"],
        "properties": [
            "title": ["type": "string"],
            "questions": [
                "type": "array",
                "items": [
                    "type": "object",
                    "additionalProperties": false,
                    "required": ["kind", "prompt", "choices", "correct_answer", "explanation", "concept", "source_page_label"],
                    "properties": [
                        "kind": ["type": "string", "enum": ["multiple_choice", "short_answer", "worked_problem"]],
                        "prompt": ["type": "string"],
                        "choices": ["type": "array", "items": ["type": "string"], "description": "Exactly 4 for multiple_choice, empty otherwise."],
                        "correct_answer": ["type": "string"],
                        "explanation": ["type": "string"],
                        "concept": ["type": "string"],
                        "source_page_label": ["type": "string", "description": "The page label (e.g. P3) the question is based on."],
                    ],
                ],
            ],
        ],
    ]

    struct Grade: Decodable {
        let is_correct: Bool
        let feedback: String
    }

    static let gradeSchema: [String: Any] = [
        "type": "object",
        "additionalProperties": false,
        "required": ["is_correct", "feedback"],
        "properties": [
            "is_correct": ["type": "boolean"],
            "feedback": ["type": "string"],
        ],
    ]

    enum Scope {
        case notebook(Notebook)
        case everything
        case weakSpots
    }

    /// Builds a quiz and stores it. `pages` are labeled P1, P2... so Claude can reference them safely.
    func generate(scope: Scope, count: Int, settings: Settings, context: ModelContext) async throws -> Quiz {
        let allPages = (try? context.fetch(FetchDescriptor<Page>())) ?? []
        var pages: [Page]
        var focus: String
        var notebook: Notebook?
        switch scope {
        case .notebook(let nb):
            pages = nb.sortedPages
            focus = "Notebook: \(nb.title)"
            notebook = nb
        case .everything:
            pages = allPages
            focus = "All notebooks"
        case .weakSpots:
            let weak = KnowledgeBase.shared.weakConcepts(context: context)
            let ids = Set(weak.flatMap(\.pageIDs))
            pages = allPages.filter { ids.contains($0.id) }
            if pages.isEmpty { pages = allPages }
            focus = "Weak spots: " + weak.map(\.name).joined(separator: ", ")
        }
        pages = pages.filter { !$0.bestText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !pages.isEmpty else {
            throw ClaudeError.message("There is no recognized text in these notes yet. Write something first, or run the tutor on a page.")
        }

        // Keep the prompt bounded: newest 40 pages, trimmed text.
        let selected = Array(pages.sorted { $0.updatedAt > $1.updatedAt }.prefix(40))
        var labels: [String: UUID] = [:]
        var notesBlock = ""
        for (i, p) in selected.enumerated() {
            let label = "P\(i + 1)"
            labels[label] = p.id
            notesBlock += "\n\n### \(label) — \(p.notebook?.title ?? "Notebook") › \(p.title)\n\(String(p.bestText.prefix(2500)))"
        }
        let weak = KnowledgeBase.shared.weakConcepts(context: context)
        var user = "Create a quiz with \(count) questions.\nFocus: \(focus)."
        let masteryBlock = KnowledgeBase.masteryBlock(weak)
        if !masteryBlock.isEmpty { user += "\n\nConcepts the student has struggled with:\n\(masteryBlock)" }
        user += "\n\nThe student's notes:" + notesBlock

        let req = ClaudeRequest(model: settings.model, system: Prompts.quiz,
                                messages: [ClaudeMessage(role: .user, text: user)],
                                maxTokens: 12000, effort: settings.chatEffort, jsonSchema: Self.generateSchema)
        let generated = try await ClaudeClient.shared.sendStructured(req, settings: settings, as: Generated.self)

        let quiz = Quiz(title: generated.title, focus: focus)
        context.insert(quiz)
        quiz.notebook = notebook
        for (i, q) in generated.questions.enumerated() {
            let kind = QuestionKind(rawValue: q.kind) ?? .shortAnswer
            let question = QuizQuestion(order: i, kind: kind, prompt: q.prompt,
                                        choices: kind == .multipleChoice ? q.choices : [],
                                        correctAnswer: q.correct_answer, explanation: q.explanation,
                                        conceptName: q.concept, sourcePageID: labels[q.source_page_label])
            context.insert(question)
            question.quiz = quiz
        }
        try? context.save()
        return quiz
    }

    /// Grades one answer. Multiple choice is graded locally; the rest ask Claude.
    func grade(_ question: QuizQuestion, answer: String, settings: Settings, context: ModelContext) async throws {
        let trimmed = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        question.userAnswer = trimmed
        if question.kind == .multipleChoice {
            let correct = trimmed.caseInsensitiveCompare(question.correctAnswer) == .orderedSame
            question.isCorrect = correct
            question.feedback = correct ? "Correct." : "Not quite. \(question.explanation)"
        } else {
            let user = """
            Question: \(question.prompt)
            Reference answer: \(question.correctAnswer)
            Reference explanation: \(question.explanation)
            Student's answer: \(trimmed)
            """
            let req = ClaudeRequest(model: settings.model, system: Prompts.grader,
                                    messages: [ClaudeMessage(role: .user, text: user)],
                                    maxTokens: 2000, effort: .medium, jsonSchema: Self.gradeSchema)
            let g = try await ClaudeClient.shared.sendStructured(req, settings: settings, as: Grade.self)
            question.isCorrect = g.is_correct
            question.feedback = g.feedback
        }
        KnowledgeBase.shared.recordQuizResult(concept: question.conceptName, correct: question.isCorrect == true, context: context)
        if let quiz = question.quiz, quiz.questions.allSatisfy({ $0.isCorrect != nil }) {
            quiz.completedAt = .now
        }
        try? context.save()
    }
}
