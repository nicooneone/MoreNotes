import XCTest
import SwiftUI
@testable import MoreNotes

final class SSEParserTests: XCTestCase {
    func testParsesTextDeltasAndStop() {
        var p = SSEParser()
        var events: [SSEParser.Event] = []
        let lines = [
            "event: message_start",
            "data: {\"type\":\"message_start\",\"message\":{\"id\":\"msg_1\"}}",
            "",
            "event: content_block_delta",
            "data: {\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"text_delta\",\"text\":\"Hel\"}}",
            "",
            "event: content_block_delta",
            "data: {\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"text_delta\",\"text\":\"lo\"}}",
            "",
            "event: message_delta",
            "data: {\"type\":\"message_delta\",\"delta\":{\"stop_reason\":\"end_turn\"},\"usage\":{\"output_tokens\":2}}",
            "",
        ]
        for l in lines { events.append(contentsOf: p.feed(line: l)) }
        XCTAssertEqual(events, [.other, .textDelta("Hel"), .textDelta("lo"), .stop(reason: "end_turn", category: nil, explanation: nil)])
    }

    func testRefusalStopCarriesCategory() {
        var p = SSEParser()
        _ = p.feed(line: "event: message_delta")
        _ = p.feed(line: "data: {\"type\":\"message_delta\",\"delta\":{\"stop_reason\":\"refusal\",\"stop_details\":{\"type\":\"refusal\",\"category\":\"cyber\"}}}")
        let events = p.feed(line: "")
        XCTAssertEqual(events, [.stop(reason: "refusal", category: "cyber", explanation: nil)])
    }
}

final class EmbeddingCodecTests: XCTestCase {
    func testRoundTrip() {
        let v: [Float] = [0.1, -2.5, 3.75, 0]
        XCTAssertEqual(EmbeddingCodec.unpack(EmbeddingCodec.pack(v)), v)
    }

    func testCosine() {
        XCTAssertEqual(EmbeddingCodec.cosineSimilarity([1, 0], [1, 0]), 1, accuracy: 1e-6)
        XCTAssertEqual(EmbeddingCodec.cosineSimilarity([1, 0], [0, 1]), 0, accuracy: 1e-6)
        XCTAssertEqual(EmbeddingCodec.cosineSimilarity([1, 0], [-1, 0]), -1, accuracy: 1e-6)
        XCTAssertEqual(EmbeddingCodec.cosineSimilarity([], []), 0)
    }
}

final class ClaudeRequestTests: XCTestCase {
    func testBodyShape() throws {
        let req = ClaudeRequest(model: "claude-opus-5", system: "sys",
                                messages: [ClaudeMessage(role: .user, text: "hi")],
                                maxTokens: 100, effort: .medium,
                                jsonSchema: ["type": "object", "additionalProperties": false, "properties": [:], "required": []])
        let body = req.body()
        XCTAssertEqual(body["model"] as? String, "claude-opus-5")
        XCTAssertEqual(body["max_tokens"] as? Int, 100)
        XCTAssertEqual(body["fallbacks"] as? String, "default")
        XCTAssertNil(body["thinking"], "adaptive thinking is the default; do not send a thinking param")
        let output = try XCTUnwrap(body["output_config"] as? [String: Any])
        XCTAssertEqual(output["effort"] as? String, "medium")
        let format = try XCTUnwrap(output["format"] as? [String: Any])
        XCTAssertEqual(format["type"] as? String, "json_schema")
        let system = try XCTUnwrap(body["system"] as? [[String: Any]])
        XCTAssertNotNil(system.first?["cache_control"])
        XCTAssertNoThrow(try JSONSerialization.data(withJSONObject: body))
    }

    func testFallbackOnlyForSupportedModels() {
        XCTAssertTrue(ClaudeClient.supportsServerSideFallback("claude-opus-5"))
        XCTAssertTrue(ClaudeClient.supportsServerSideFallback("claude-fable-5-1"))
        XCTAssertFalse(ClaudeClient.supportsServerSideFallback("claude-sonnet-5"))
        let body = ClaudeRequest(model: "claude-sonnet-5", system: nil, messages: []).body()
        XCTAssertNil(body["fallbacks"])
    }
}

final class KnowledgeBaseTests: XCTestCase {
    func testChunkingRespectsMaxLength() {
        let text = (0..<40).map { "line \($0) with some words in it" }.joined(separator: "\n")
        let chunks = KnowledgeBase.chunk(text, maxLength: 120)
        XCTAssertGreaterThan(chunks.count, 3)
        for c in chunks { XCTAssertLessThanOrEqual(c.count, 140) }
        XCTAssertEqual(chunks.joined(separator: "\n"), text)
    }

    func testAlternatingMergesSameRoleAndDropsLeadingAssistant() {
        let msgs = [
            ClaudeMessage(role: .assistant, text: "hello"),
            ClaudeMessage(role: .user, text: "a"),
            ClaudeMessage(role: .user, text: "b"),
            ClaudeMessage(role: .assistant, text: "c"),
        ]
        let out = ChatService.alternating(msgs)
        XCTAssertEqual(out.count, 2)
        XCTAssertEqual(out[0].role, .user)
        XCTAssertEqual(out[0].content.count, 2)
        XCTAssertEqual(out[1].role, .assistant)
    }
}

final class TemplateTests: XCTestCase {
    func testEveryTemplateHasNameAndIcon() {
        for t in PageTemplate.allCases {
            XCTAssertFalse(t.displayName.isEmpty)
            XCTAssertFalse(t.systemImage.isEmpty)
            XCTAssertGreaterThan(t.pitch, 0)
        }
    }

    func testColorHexRoundTrip() {
        for hex in Swatches.all {
            let c = Color(hex: hex)
            XCTAssertNotNil(c)
            XCTAssertEqual(c?.hexString, hex)
        }
    }
}
