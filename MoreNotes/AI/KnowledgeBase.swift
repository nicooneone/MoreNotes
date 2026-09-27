import Foundation
import SwiftData
import NaturalLanguage
import PencilKit

/// The user's personal knowledge base: every page's text, chunked and embedded
/// on-device, plus the concepts Claude has extracted. Retrieval is a cosine
/// search over the stored vectors; nothing leaves the device until a Claude call.
@MainActor
final class KnowledgeBase {
    static let shared = KnowledgeBase()

    private lazy var embedder: NLEmbedding? = NLEmbedding.sentenceEmbedding(for: .english)

    struct Hit: Identifiable {
        let id: UUID
        let text: String
        let score: Float
        let pageID: UUID?
        let pageTitle: String
        let notebookTitle: String
    }

    // MARK: - Embedding

    func embed(_ text: String) -> [Float]? {
        guard let embedder, let v = embedder.vector(for: text) else { return nil }
        return v.map { Float($0) }
    }

    /// Splits text into ~350-character chunks on line boundaries.
    static func chunk(_ text: String, maxLength: Int = 350) -> [String] {
        var chunks: [String] = []
        var current = ""
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if current.count + line.count + 1 > maxLength, !current.isEmpty {
                chunks.append(current)
                current = ""
            }
            current += (current.isEmpty ? "" : "\n") + line
        }
        if !current.isEmpty { chunks.append(current) }
        return chunks
    }

    // MARK: - Indexing

    /// Recognizes the page's handwriting and rebuilds its chunks/embeddings.
    /// Skips work if the drawing has not changed since the last run.
    func index(page: Page, drawing: PKDrawing, context: ModelContext, force: Bool = false) async {
        let hash = drawing.dataRepresentation().hashValue
        if !force, hash == page.lastIndexedHash { return }
        let image = PageRenderer.imageForAI(drawing: drawing, pageSize: page.pageSize.size, maxDimension: 1600)
        let lines = (try? await HandwritingRecognizer.recognize(image)) ?? []
        let text = HandwritingRecognizer.text(from: lines)
        page.recognizedText = text
        page.lastIndexedHash = hash
        page.updatedAt = .now
        rebuildChunks(for: page, context: context)
        try? context.save()
    }

    /// Replaces a page's chunks from its best available text.
    func rebuildChunks(for page: Page, context: ModelContext) {
        for old in page.chunks { context.delete(old) }
        page.chunks = []
        for piece in Self.chunk(page.bestText) {
            guard let vec = embed(piece) else { continue }
            let chunk = NoteChunk(text: piece, embedding: vec)
            context.insert(chunk)
            chunk.page = page
        }
    }

    // MARK: - Retrieval

    func search(_ query: String, limit: Int = 8, context: ModelContext, excludingPage: UUID? = nil) -> [Hit] {
        guard let q = embed(query) else { return [] }
        let all = (try? context.fetch(FetchDescriptor<NoteChunk>())) ?? []
        var scored: [Hit] = []
        scored.reserveCapacity(all.count)
        for c in all {
            if let ex = excludingPage, c.page?.id == ex { continue }
            let s = EmbeddingCodec.cosineSimilarity(q, c.embedding)
            guard s > 0.35 else { continue }
            scored.append(Hit(id: c.id, text: c.text, score: s, pageID: c.page?.id,
                              pageTitle: c.page?.title ?? "Untitled page",
                              notebookTitle: c.page?.notebook?.title ?? "Notebook"))
        }
        return Array(scored.sorted { $0.score > $1.score }.prefix(limit))
    }

    /// Formats retrieval hits for a prompt.
    static func contextBlock(from hits: [Hit]) -> String {
        guard !hits.isEmpty else { return "" }
        return hits.enumerated().map { i, h in
            "[\(i + 1)] (\(h.notebookTitle) › \(h.pageTitle))\n\(h.text)"
        }.joined(separator: "\n\n")
    }

    // MARK: - Concepts / mastery

    func concept(named name: String, context: ModelContext, createIfMissing: Bool = true) -> Concept? {
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return nil }
        let all = (try? context.fetch(FetchDescriptor<Concept>())) ?? []
        if let existing = all.first(where: { $0.name.lowercased() == normalized }) { return existing }
        guard createIfMissing else { return nil }
        let c = Concept(name: name.trimmingCharacters(in: .whitespacesAndNewlines), summary: "")
        context.insert(c)
        return c
    }

    func recordTutorIssue(concept name: String, pageID: UUID, context: ModelContext) {
        guard let c = concept(named: name, context: context) else { return }
        c.tutorIssueCount += 1
        if !c.pageIDs.contains(pageID) { c.pageIDs.append(pageID) }
        c.updatedAt = .now
    }

    func recordQuizResult(concept name: String, correct: Bool, context: ModelContext) {
        guard let c = concept(named: name, context: context) else { return }
        if correct { c.correctCount += 1 } else { c.incorrectCount += 1 }
        c.updatedAt = .now
    }

    /// Concepts the user has struggled with most, for targeted quizzes and chat context.
    func weakConcepts(limit: Int = 8, context: ModelContext) -> [Concept] {
        let all = (try? context.fetch(FetchDescriptor<Concept>())) ?? []
        return Array(all
            .filter { $0.incorrectCount + $0.tutorIssueCount > 0 }
            .sorted { a, b in a.mastery != b.mastery ? a.mastery < b.mastery : a.updatedAt > b.updatedAt }
            .prefix(limit))
    }

    static func masteryBlock(_ concepts: [Concept]) -> String {
        guard !concepts.isEmpty else { return "" }
        return concepts.map { c in
            "- \(c.name): \(c.correctCount) correct, \(c.incorrectCount) incorrect on quizzes, \(c.tutorIssueCount) mistakes flagged while writing"
        }.joined(separator: "\n")
    }
}
