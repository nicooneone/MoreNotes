import Foundation
import SwiftData
import PencilKit

/// Looks at a page and produces structured feedback ("you dropped a minus sign in
/// step 3"). Runs on demand and, when Live Tutor is on, automatically after the
/// pencil has been idle for a few seconds.
@MainActor
final class TutorService {
    static let shared = TutorService()

    struct Review: Decodable {
        struct Issue: Decodable {
            struct Region: Decodable { let x: Double; let y: Double; let width: Double; let height: Double }
            let title: String
            let explanation: String
            let hint: String
            let severity: String
            let concept: String
            let region: Region
        }
        let transcript: String
        let subject: String
        let concepts: [String]
        let overall: String            // correct | issues_found | incomplete | not_academic_work
        let summary: String
        let issues: [Issue]
        let next_step_hint: String
    }

    static let schema: [String: Any] = [
        "type": "object",
        "additionalProperties": false,
        "required": ["transcript", "subject", "concepts", "overall", "summary", "issues", "next_step_hint"],
        "properties": [
            "transcript": ["type": "string", "description": "Everything written on the page, in reading order. LaTeX-style math."],
            "subject": ["type": "string"],
            "concepts": ["type": "array", "items": ["type": "string"]],
            "overall": ["type": "string", "enum": ["correct", "issues_found", "incomplete", "not_academic_work"]],
            "summary": ["type": "string", "description": "One or two sentences for the student."],
            "issues": [
                "type": "array",
                "items": [
                    "type": "object",
                    "additionalProperties": false,
                    "required": ["title", "explanation", "hint", "severity", "concept", "region"],
                    "properties": [
                        "title": ["type": "string"],
                        "explanation": ["type": "string"],
                        "hint": ["type": "string"],
                        "severity": ["type": "string", "enum": ["error", "warning", "hint", "praise"]],
                        "concept": ["type": "string"],
                        "region": [
                            "type": "object",
                            "additionalProperties": false,
                            "required": ["x", "y", "width", "height"],
                            "properties": [
                                "x": ["type": "number"], "y": ["type": "number"],
                                "width": ["type": "number"], "height": ["type": "number"],
                            ],
                        ],
                    ],
                ],
            ],
            "next_step_hint": ["type": "string"],
        ],
    ]

    private var inFlight: Set<UUID> = []
    private var lastRun: [UUID: Date] = [:]

    /// Reviews the page. Returns the review, and persists findings + concepts.
    /// `automatic` runs respect the minimum interval and skip unchanged pages.
    @discardableResult
    func review(page: Page, drawing: PKDrawing, settings: Settings, context: ModelContext,
                automatic: Bool, extraInstruction: String? = nil) async throws -> Review? {
        guard !drawing.strokes.isEmpty else { return nil }
        let hash = drawing.dataRepresentation().hashValue
        if automatic {
            if hash == page.lastTutorHash { return nil }
            if let last = lastRun[page.id], Date().timeIntervalSince(last) < settings.tutorMinInterval { return nil }
        }
        guard !inFlight.contains(page.id) else { return nil }
        inFlight.insert(page.id)
        defer { inFlight.remove(page.id) }

        let image = PageRenderer.imageForAI(drawing: drawing, pageSize: page.pageSize.size)
        guard let b64 = PageRenderer.jpegBase64(image) else { return nil }

        var userText = "Here is the current page from the notebook \"\(page.notebook?.title ?? "Untitled")\""
        if let subject = page.notebook?.subject, !subject.isEmpty { userText += " (subject: \(subject))" }
        userText += ". Review the work."
        if !page.recognizedText.isEmpty {
            userText += "\n\nOn-device text recognition (may be inaccurate):\n\(page.recognizedText)"
        }
        if let extraInstruction, !extraInstruction.isEmpty {
            userText += "\n\nThe student asks: \(extraInstruction)"
        }

        let req = ClaudeRequest(
            model: settings.model,
            system: Prompts.tutor,
            messages: [ClaudeMessage(role: .user, content: [
                .imageBase64(mediaType: "image/jpeg", data: b64),
                .text(userText),
            ])],
            maxTokens: 8000,
            effort: automatic ? settings.tutorEffort : settings.chatEffort,
            jsonSchema: Self.schema
        )

        let review = try await ClaudeClient.shared.sendStructured(req, settings: settings, as: Review.self)
        lastRun[page.id] = .now
        page.lastTutorHash = hash
        apply(review, to: page, context: context)
        return review
    }

    private func apply(_ review: Review, to page: Page, context: ModelContext) {
        if !review.transcript.isEmpty {
            page.aiTranscript = review.transcript
            KnowledgeBase.shared.rebuildChunks(for: page, context: context)
        }
        // Replace previous findings with the fresh review.
        for old in page.findings { context.delete(old) }
        page.findings = []
        for issue in review.issues {
            let severity = FindingSeverity(rawValue: issue.severity) ?? .hint
            let rect = NormalizedRect(x: issue.region.x.clamped01, y: issue.region.y.clamped01,
                                      width: issue.region.width.clamped01, height: issue.region.height.clamped01)
            let finding = TutorFinding(title: issue.title, explanation: issue.explanation, hint: issue.hint,
                                       severity: severity, rect: rect, conceptName: issue.concept)
            context.insert(finding)
            finding.page = page
            if severity == .error || severity == .warning {
                KnowledgeBase.shared.recordTutorIssue(concept: issue.concept, pageID: page.id, context: context)
            }
        }
        for name in review.concepts {
            if let c = KnowledgeBase.shared.concept(named: name, context: context), !c.pageIDs.contains(page.id) {
                c.pageIDs.append(page.id)
            }
        }
        page.updatedAt = .now
        try? context.save()
    }
}

extension Double {
    var clamped01: Double { Swift.min(1, Swift.max(0, self)) }
}
