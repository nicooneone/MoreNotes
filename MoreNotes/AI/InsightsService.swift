import Foundation
import SwiftData

/// "What am I working on?" — builds the concept graph across all notebooks.
@MainActor
final class InsightsService {
    static let shared = InsightsService()

    struct Insights: Decodable {
        struct ConceptInfo: Decodable {
            let name: String
            let summary: String
            let related: [String]
            let page_labels: [String]
        }
        let summary: String
        let current_focus: String
        let concepts: [ConceptInfo]
        let likely_weak_spots: [String]
        let suggestions: [String]
    }

    static let schema: [String: Any] = [
        "type": "object",
        "additionalProperties": false,
        "required": ["summary", "current_focus", "concepts", "likely_weak_spots", "suggestions"],
        "properties": [
            "summary": ["type": "string"],
            "current_focus": ["type": "string"],
            "concepts": [
                "type": "array",
                "items": [
                    "type": "object",
                    "additionalProperties": false,
                    "required": ["name", "summary", "related", "page_labels"],
                    "properties": [
                        "name": ["type": "string"],
                        "summary": ["type": "string"],
                        "related": ["type": "array", "items": ["type": "string"]],
                        "page_labels": ["type": "array", "items": ["type": "string"]],
                    ],
                ],
            ],
            "likely_weak_spots": ["type": "array", "items": ["type": "string"]],
            "suggestions": ["type": "array", "items": ["type": "string"]],
        ],
    ]

    private(set) var latest: Insights?
    private(set) var lastRun: Date?

    func refresh(settings: Settings, context: ModelContext) async throws -> Insights {
        let pages = ((try? context.fetch(FetchDescriptor<Page>())) ?? [])
            .filter { !$0.bestText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { $0.updatedAt > $1.updatedAt }
        guard !pages.isEmpty else {
            throw ClaudeError.message("No recognized notes yet. Write a page and let the tutor or indexer run first.")
        }
        var labels: [String: UUID] = [:]
        var block = ""
        for (i, p) in pages.prefix(60).enumerated() {
            let label = "P\(i + 1)"
            labels[label] = p.id
            let nbTitle = p.notebook?.title ?? "Notebook"
            let subject = p.notebook?.subject ?? ""
            let subjectPart = subject.isEmpty ? "" : " (\(subject))"
            let edited = p.updatedAt.formatted(date: .abbreviated, time: .omitted)
            block += "\n\n### \(label) — \(nbTitle)\(subjectPart) › \(p.title), edited \(edited)\n\(String(p.bestText.prefix(1800)))"
        }
        let weak = KnowledgeBase.shared.weakConcepts(context: context)
        var user = "Analyze these notes."
        let mastery = KnowledgeBase.masteryBlock(weak)
        if !mastery.isEmpty { user += "\n\nRecorded struggles so far:\n\(mastery)" }
        user += block

        let req = ClaudeRequest(model: settings.model, system: Prompts.insights,
                                messages: [ClaudeMessage(role: .user, text: user)],
                                maxTokens: 12000, effort: settings.chatEffort, jsonSchema: Self.schema)
        let insights = try await ClaudeClient.shared.sendStructured(req, settings: settings, as: Insights.self)

        // Merge into the Concept store.
        for info in insights.concepts {
            guard let c = KnowledgeBase.shared.concept(named: info.name, context: context) else { continue }
            c.summary = info.summary
            c.relatedConceptNames = info.related
            for label in info.page_labels {
                if let id = labels[label], !c.pageIDs.contains(id) { c.pageIDs.append(id) }
            }
            c.updatedAt = .now
        }
        try? context.save()
        latest = insights
        lastRun = .now
        return insights
    }
}
