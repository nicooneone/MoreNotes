import Foundation
import SwiftData
import PencilKit

/// Streams a chat turn with the notebook's history, the current page, and
/// retrieved notes from the knowledge base as context.
@MainActor
final class ChatService {
    static let shared = ChatService()

    struct Turn {
        let systemContext: String
        let messages: [ClaudeMessage]
    }

    func buildTurn(question: String, notebook: Notebook?, currentPage: Page?, currentDrawing: PKDrawing?,
                   settings: Settings, context: ModelContext) -> Turn {
        // Retrieval across every notebook.
        let hits = KnowledgeBase.shared.search(question, limit: 8, context: context, excludingPage: currentPage?.id)
        let weak = KnowledgeBase.shared.weakConcepts(limit: 6, context: context)

        var ctx = ""
        if let nb = notebook {
            ctx += "Current notebook: \(nb.title)" + (nb.subject.isEmpty ? "" : " (\(nb.subject))") + "\n"
        }
        if let p = currentPage, !p.bestText.isEmpty {
            ctx += "\nText on the current page (\(p.title)):\n\(p.bestText.prefix(3000))\n"
        }
        let retrieved = KnowledgeBase.contextBlock(from: hits)
        if !retrieved.isEmpty { ctx += "\nRelevant excerpts from the user's other notes:\n\(retrieved)\n" }
        let mastery = KnowledgeBase.masteryBlock(weak)
        if !mastery.isEmpty { ctx += "\nConcepts the user has struggled with:\n\(mastery)\n" }

        // History: last 20 stored messages, text only.
        var messages: [ClaudeMessage] = []
        if let nb = notebook {
            let history = nb.chatHistory.sorted { $0.createdAt < $1.createdAt }.suffix(20)
            for m in history where !m.text.isEmpty {
                messages.append(ClaudeMessage(role: m.roleRaw == "user" ? .user : .assistant, text: m.text))
            }
        }
        // Merge consecutive same-role messages (API requires alternation).
        messages = Self.alternating(messages)

        var content: [ContentBlock] = []
        if settings.attachPageImageToChat, let drawing = currentDrawing, !drawing.strokes.isEmpty, let page = currentPage {
            let img = PageRenderer.imageForAI(drawing: drawing, pageSize: page.pageSize.size, maxDimension: 1200)
            if let b64 = PageRenderer.jpegBase64(img, quality: 0.7) {
                content.append(.imageBase64(mediaType: "image/jpeg", data: b64))
            }
        }
        var text = question
        if !ctx.isEmpty { text = "<context>\n\(ctx)\n</context>\n\n\(question)" }
        content.append(.text(text))
        if messages.last?.role == .user {
            // Should not happen after alternating(), but never send two user turns in a row.
            messages.removeLast()
        }
        messages.append(ClaudeMessage(role: .user, content: content))
        return Turn(systemContext: Prompts.chat, messages: messages)
    }

    func stream(turn: Turn, settings: Settings) -> AsyncThrowingStream<String, Error> {
        let req = ClaudeRequest(model: settings.model, system: turn.systemContext, messages: turn.messages,
                                maxTokens: 16000, effort: settings.chatEffort, stream: true)
        return ClaudeClient.shared.stream(req, settings: settings)
    }

    static func alternating(_ messages: [ClaudeMessage]) -> [ClaudeMessage] {
        var out: [ClaudeMessage] = []
        for m in messages {
            if let last = out.last, last.role == m.role {
                let merged = ClaudeMessage(role: m.role, content: last.content + m.content)
                out[out.count - 1] = merged
            } else {
                out.append(m)
            }
        }
        // Conversation must start with a user message.
        while let first = out.first, first.role == .assistant { out.removeFirst() }
        return out
    }
}
