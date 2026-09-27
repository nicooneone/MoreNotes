import Foundation
import SwiftData

// MARK: - Notebook

@Model
final class Notebook {
    @Attribute(.unique) var id: UUID
    var title: String
    var subject: String            // e.g. "Calculus II", "Organic Chemistry"
    var coverColorHex: String
    var createdAt: Date
    var updatedAt: Date
    var defaultTemplateRaw: String
    var defaultPaperRaw: String

    @Relationship(deleteRule: .cascade, inverse: \Page.notebook)
    var pages: [Page] = []

    @Relationship(deleteRule: .cascade, inverse: \ChatMessageRecord.notebook)
    var chatHistory: [ChatMessageRecord] = []

    @Relationship(deleteRule: .cascade, inverse: \Quiz.notebook)
    var quizzes: [Quiz] = []

    init(title: String,
         subject: String = "",
         coverColorHex: String = "#4F7CFF",
         template: PageTemplate = .ruledCollege,
         paper: PaperColor = .white) {
        self.id = UUID()
        self.title = title
        self.subject = subject
        self.coverColorHex = coverColorHex
        self.createdAt = .now
        self.updatedAt = .now
        self.defaultTemplateRaw = template.rawValue
        self.defaultPaperRaw = paper.rawValue
    }

    var defaultTemplate: PageTemplate {
        get { PageTemplate(rawValue: defaultTemplateRaw) ?? .ruledCollege }
        set { defaultTemplateRaw = newValue.rawValue }
    }

    var defaultPaper: PaperColor {
        get { PaperColor(rawValue: defaultPaperRaw) ?? .white }
        set { defaultPaperRaw = newValue.rawValue }
    }

    var sortedPages: [Page] { pages.sorted { $0.index < $1.index } }
}

// MARK: - Page

@Model
final class Page {
    @Attribute(.unique) var id: UUID
    var index: Int
    var createdAt: Date
    var updatedAt: Date

    /// Serialized `PKDrawing` (PencilKit's own binary format).
    @Attribute(.externalStorage) var drawingData: Data
    /// Small JPEG preview for the page grid.
    @Attribute(.externalStorage) var thumbnailData: Data?

    var templateRaw: String
    var paperRaw: String
    var pageSizeRaw: String

    /// On-device handwriting recognition result (Vision). Used for search and RAG.
    var recognizedText: String
    /// Claude's transcription of the page (better with math notation). Optional.
    var aiTranscript: String?
    /// Hash of the drawing the last time recognition/tutoring ran, to skip redundant work.
    var lastIndexedHash: Int
    var lastTutorHash: Int
    var title: String

    var notebook: Notebook?

    @Relationship(deleteRule: .cascade, inverse: \NoteChunk.page)
    var chunks: [NoteChunk] = []

    @Relationship(deleteRule: .cascade, inverse: \TutorFinding.page)
    var findings: [TutorFinding] = []

    init(index: Int,
         template: PageTemplate,
         paper: PaperColor,
         pageSize: PageSize = .letter) {
        self.id = UUID()
        self.index = index
        self.createdAt = .now
        self.updatedAt = .now
        self.drawingData = Data()
        self.thumbnailData = nil
        self.templateRaw = template.rawValue
        self.paperRaw = paper.rawValue
        self.pageSizeRaw = pageSize.rawValue
        self.recognizedText = ""
        self.aiTranscript = nil
        self.lastIndexedHash = 0
        self.lastTutorHash = 0
        self.title = "Page \(index + 1)"
        self.notebook = nil
    }

    var template: PageTemplate {
        get { PageTemplate(rawValue: templateRaw) ?? .blank }
        set { templateRaw = newValue.rawValue }
    }

    var paper: PaperColor {
        get { PaperColor(rawValue: paperRaw) ?? .white }
        set { paperRaw = newValue.rawValue }
    }

    var pageSize: PageSize {
        get { PageSize(rawValue: pageSizeRaw) ?? .letter }
        set { pageSizeRaw = newValue.rawValue }
    }

    /// The best available text for this page: Claude's transcript when we have it,
    /// otherwise the on-device recognition.
    var bestText: String {
        if let t = aiTranscript, !t.isEmpty { return t }
        return recognizedText
    }
}

// MARK: - Knowledge base

/// A chunk of recognized note text with its sentence embedding, so the AI can
/// retrieve relevant notes across every notebook.
@Model
final class NoteChunk {
    @Attribute(.unique) var id: UUID
    var text: String
    /// Packed little-endian Float32 vector.
    var embeddingData: Data
    var createdAt: Date
    var page: Page?

    init(text: String, embedding: [Float]) {
        self.id = UUID()
        self.text = text
        self.embeddingData = EmbeddingCodec.pack(embedding)
        self.createdAt = .now
        self.page = nil
    }

    var embedding: [Float] { EmbeddingCodec.unpack(embeddingData) }
}

/// A concept the AI has identified across the user's notes ("chain rule",
/// "integration by parts", "SN2 mechanism"). Links pages together and tracks mastery.
@Model
final class Concept {
    @Attribute(.unique) var id: UUID
    var name: String
    var summary: String
    /// Page ids where this concept appears (kept as ids so concepts can span notebooks).
    var pageIDs: [UUID]
    /// Related concept names (edges in the knowledge graph).
    var relatedConceptNames: [String]
    /// 0 = never assessed. Positive = correct answers, negative-ish = struggles.
    var correctCount: Int
    var incorrectCount: Int
    var tutorIssueCount: Int
    var updatedAt: Date

    init(name: String, summary: String, pageIDs: [UUID] = [], related: [String] = []) {
        self.id = UUID()
        self.name = name
        self.summary = summary
        self.pageIDs = pageIDs
        self.relatedConceptNames = related
        self.correctCount = 0
        self.incorrectCount = 0
        self.tutorIssueCount = 0
        self.updatedAt = .now
    }

    /// 0...1 mastery estimate. Struggles and tutor corrections pull it down.
    var mastery: Double {
        let total = Double(correctCount + incorrectCount + tutorIssueCount)
        guard total > 0 else { return 0.5 }
        return Double(correctCount) / total
    }
}

// MARK: - Tutor

enum FindingSeverity: String, Codable, CaseIterable {
    case error, warning, hint, praise
}

/// One piece of feedback the tutor produced about a page, anchored to a
/// normalized rectangle (0...1 in page coordinates) so it can be drawn over the ink.
@Model
final class TutorFinding {
    @Attribute(.unique) var id: UUID
    var title: String
    var explanation: String
    var hint: String
    var severityRaw: String
    var x: Double
    var y: Double
    var width: Double
    var height: Double
    var conceptName: String
    var createdAt: Date
    var dismissed: Bool
    var page: Page?

    init(title: String, explanation: String, hint: String, severity: FindingSeverity,
         rect: NormalizedRect, conceptName: String) {
        self.id = UUID()
        self.title = title
        self.explanation = explanation
        self.hint = hint
        self.severityRaw = severity.rawValue
        self.x = rect.x
        self.y = rect.y
        self.width = rect.width
        self.height = rect.height
        self.conceptName = conceptName
        self.createdAt = .now
        self.dismissed = false
        self.page = nil
    }

    var severity: FindingSeverity { FindingSeverity(rawValue: severityRaw) ?? .hint }
    var rect: NormalizedRect { NormalizedRect(x: x, y: y, width: width, height: height) }
}

struct NormalizedRect: Codable, Hashable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    static let none = NormalizedRect(x: 0, y: 0, width: 0, height: 0)
    var isEmpty: Bool { width <= 0 || height <= 0 }
}

// MARK: - Quizzes

enum QuestionKind: String, Codable, CaseIterable {
    case multipleChoice = "multiple_choice"
    case shortAnswer = "short_answer"
    case workedProblem = "worked_problem"
}

@Model
final class Quiz {
    @Attribute(.unique) var id: UUID
    var title: String
    var focus: String            // what the quiz targets, e.g. "weak spots in Calc II"
    var createdAt: Date
    var completedAt: Date?
    var notebook: Notebook?

    @Relationship(deleteRule: .cascade, inverse: \QuizQuestion.quiz)
    var questions: [QuizQuestion] = []

    init(title: String, focus: String) {
        self.id = UUID()
        self.title = title
        self.focus = focus
        self.createdAt = .now
        self.completedAt = nil
        self.notebook = nil
    }

    var sortedQuestions: [QuizQuestion] { questions.sorted { $0.order < $1.order } }
    var score: (correct: Int, total: Int) {
        let graded = questions.filter { $0.isCorrect != nil }
        return (graded.filter { $0.isCorrect == true }.count, questions.count)
    }
}

@Model
final class QuizQuestion {
    @Attribute(.unique) var id: UUID
    var order: Int
    var kindRaw: String
    var prompt: String
    var choices: [String]
    var correctAnswer: String
    var explanation: String
    var conceptName: String
    /// Which page this question was derived from, so the user can jump back to their notes.
    var sourcePageID: UUID?

    var userAnswer: String?
    var isCorrect: Bool?
    var feedback: String?
    var quiz: Quiz?

    init(order: Int, kind: QuestionKind, prompt: String, choices: [String],
         correctAnswer: String, explanation: String, conceptName: String,
         sourcePageID: UUID?) {
        self.id = UUID()
        self.order = order
        self.kindRaw = kind.rawValue
        self.prompt = prompt
        self.choices = choices
        self.correctAnswer = correctAnswer
        self.explanation = explanation
        self.conceptName = conceptName
        self.sourcePageID = sourcePageID
        self.userAnswer = nil
        self.isCorrect = nil
        self.feedback = nil
        self.quiz = nil
    }

    var kind: QuestionKind { QuestionKind(rawValue: kindRaw) ?? .shortAnswer }
}

// MARK: - Chat history

@Model
final class ChatMessageRecord {
    @Attribute(.unique) var id: UUID
    var roleRaw: String          // "user" | "assistant"
    var text: String
    var createdAt: Date
    var notebook: Notebook?

    init(role: String, text: String) {
        self.id = UUID()
        self.roleRaw = role
        self.text = text
        self.createdAt = .now
        self.notebook = nil
    }
}

// MARK: - Embedding codec

enum EmbeddingCodec {
    static func pack(_ v: [Float]) -> Data {
        var data = Data(capacity: v.count * 4)
        for f in v {
            var le = f.bitPattern.littleEndian
            withUnsafeBytes(of: &le) { data.append(contentsOf: $0) }
        }
        return data
    }

    static func unpack(_ data: Data) -> [Float] {
        let count = data.count / 4
        var out = [Float](repeating: 0, count: count)
        data.withUnsafeBytes { raw in
            for i in 0..<count {
                let bits = raw.loadUnaligned(fromByteOffset: i * 4, as: UInt32.self)
                out[i] = Float(bitPattern: UInt32(littleEndian: bits))
            }
        }
        return out
    }

    static func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot: Float = 0, na: Float = 0, nb: Float = 0
        for i in 0..<a.count {
            dot += a[i] * b[i]
            na += a[i] * a[i]
            nb += b[i] * b[i]
        }
        let denom = (na.squareRoot() * nb.squareRoot())
        return denom > 0 ? dot / denom : 0
    }
}
