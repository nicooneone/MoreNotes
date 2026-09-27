import Foundation

// MARK: - Request model

/// A content block in a user/assistant message. Only the shapes this app uses.
enum ContentBlock {
    case text(String)
    case imageBase64(mediaType: String, data: String)

    var json: [String: Any] {
        switch self {
        case .text(let t):
            return ["type": "text", "text": t]
        case .imageBase64(let mediaType, let data):
            return ["type": "image", "source": ["type": "base64", "media_type": mediaType, "data": data]]
        }
    }
}

struct ClaudeMessage {
    enum Role: String { case user, assistant }
    var role: Role
    var content: [ContentBlock]

    init(role: Role, text: String) {
        self.role = role
        self.content = [.text(text)]
    }

    init(role: Role, content: [ContentBlock]) {
        self.role = role
        self.content = content
    }

    var json: [String: Any] {
        ["role": role.rawValue, "content": content.map { $0.json }]
    }
}

struct ClaudeRequest {
    var model: String
    var system: String?
    var messages: [ClaudeMessage]
    var maxTokens: Int = 16000
    var effort: Settings.Effort = .high
    /// JSON schema for structured output (`output_config.format`).
    var jsonSchema: [String: Any]? = nil
    var stream = false
    /// Cache the system prompt (stable prefix) across requests.
    var cacheSystemPrompt = true

    func body() -> [String: Any] {
        var b: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "messages": messages.map { $0.json },
        ]
        if let system {
            if cacheSystemPrompt {
                b["system"] = [["type": "text", "text": system, "cache_control": ["type": "ephemeral"]]]
            } else {
                b["system"] = system
            }
        }
        var outputConfig: [String: Any] = ["effort": effort.rawValue]
        if let jsonSchema {
            outputConfig["format"] = ["type": "json_schema", "schema": jsonSchema]
        }
        b["output_config"] = outputConfig
        if stream { b["stream"] = true }
        if ClaudeClient.supportsServerSideFallback(model) {
            // Safety classifiers on these models can decline a request. "default"
            // re-runs the request on Anthropic's recommended fallback server-side.
            b["fallbacks"] = "default"
        }
        return b
    }
}

// MARK: - Response model

struct ClaudeResponse: Decodable {
    struct Block: Decodable {
        let type: String
        let text: String?
    }
    struct Usage: Decodable {
        let input_tokens: Int?
        let output_tokens: Int?
        let cache_read_input_tokens: Int?
        let cache_creation_input_tokens: Int?
    }
    struct StopDetails: Decodable {
        let type: String?
        let category: String?
        let explanation: String?
    }

    let id: String
    let model: String
    let content: [Block]
    let stop_reason: String?
    let stop_details: StopDetails?
    let usage: Usage?

    /// All text blocks concatenated.
    var text: String {
        content.compactMap { $0.type == "text" ? $0.text : nil }.joined()
    }
}

enum ClaudeError: LocalizedError {
    case missingAPIKey
    case badURL
    case http(status: Int, message: String)
    case refusal(category: String?, explanation: String?)
    case truncated
    case decoding(String)
    case network(Error)
    case message(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Add your Anthropic API key in Settings to use the AI features."
        case .badURL:
            return "The API endpoint URL is invalid."
        case .http(let status, let message):
            return "The AI service returned an error (\(status)): \(message)"
        case .refusal(let category, let explanation):
            return "The AI declined this request" + (category.map { " (\($0))" } ?? "") + (explanation.map { ": \($0)" } ?? ".")
        case .truncated:
            return "The response was cut off. Try a shorter request."
        case .decoding(let s):
            return "Could not read the AI response: \(s)"
        case .network(let e):
            return "Network error: \(e.localizedDescription)"
        case .message(let m):
            return m
        }
    }
}

// MARK: - Client

/// Raw HTTP client for the Anthropic Messages API (there is no official Swift SDK).
/// Supports plain JSON responses, structured outputs, and SSE streaming.
final class ClaudeClient {
    static let shared = ClaudeClient()

    private let session: URLSession
    private let apiVersion = "2023-06-01"

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 600
        config.timeoutIntervalForResource = 900
        config.waitsForConnectivity = true
        session = URLSession(configuration: config)
    }

    static func supportsServerSideFallback(_ model: String) -> Bool {
        model.hasPrefix("claude-opus-5") || model.hasPrefix("claude-fable-5")
    }

    private func endpoint(settings: Settings) throws -> URL {
        let base = settings.proxyBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let urlString = base.isEmpty ? "https://api.anthropic.com/v1/messages" : base.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/v1/messages"
        guard let url = URL(string: urlString) else { throw ClaudeError.badURL }
        return url
    }

    private func urlRequest(for req: ClaudeRequest, settings: Settings) throws -> URLRequest {
        var r = URLRequest(url: try endpoint(settings: settings))
        r.httpMethod = "POST"
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.setValue(apiVersion, forHTTPHeaderField: "anthropic-version")
        if ClaudeClient.supportsServerSideFallback(req.model) {
            r.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
        }
        // Direct calls need the key. A proxy is expected to add it server-side.
        if settings.proxyBaseURL.isEmpty {
            guard let key = KeychainStore.apiKey, !key.isEmpty else { throw ClaudeError.missingAPIKey }
            r.setValue(key, forHTTPHeaderField: "x-api-key")
        } else if let key = KeychainStore.apiKey, !key.isEmpty {
            r.setValue(key, forHTTPHeaderField: "x-api-key")
        }
        r.httpBody = try JSONSerialization.data(withJSONObject: req.body(), options: [.sortedKeys])
        return r
    }

    /// One-shot request. Returns the parsed response after checking stop reasons.
    func send(_ req: ClaudeRequest, settings: Settings) async throws -> ClaudeResponse {
        var request = req
        request.stream = false
        let urlReq = try urlRequest(for: request, settings: settings)
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: urlReq)
        } catch {
            throw ClaudeError.network(error)
        }
        try Self.checkHTTP(response, data: data)
        let decoded: ClaudeResponse
        do {
            decoded = try JSONDecoder().decode(ClaudeResponse.self, from: data)
        } catch {
            throw ClaudeError.decoding(String(data: data.prefix(400), encoding: .utf8) ?? "\(error)")
        }
        try Self.checkStopReason(decoded)
        return decoded
    }

    /// Convenience: send and decode structured JSON output into `T`.
    func sendStructured<T: Decodable>(_ req: ClaudeRequest, settings: Settings, as type: T.Type) async throws -> T {
        let response = try await send(req, settings: settings)
        let text = response.text
        guard let data = text.data(using: .utf8) else { throw ClaudeError.decoding("empty") }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw ClaudeError.decoding("\(error)\n\(text.prefix(300))")
        }
    }

    /// Streams text deltas. The stream finishes when the message stops.
    func stream(_ req: ClaudeRequest, settings: Settings) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var request = req
                    request.stream = true
                    let urlReq = try urlRequest(for: request, settings: settings)
                    let (bytes, response) = try await session.bytes(for: urlReq)
                    if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                        var body = Data()
                        for try await b in bytes { body.append(b); if body.count > 4000 { break } }
                        try Self.checkHTTP(response, data: body)
                    }
                    var parser = SSEParser()
                    for try await line in bytes.lines {
                        if Task.isCancelled { break }
                        for event in parser.feed(line: line) {
                            switch event {
                            case .textDelta(let t):
                                continuation.yield(t)
                            case .stop(let reason, let category, let explanation):
                                if reason == "refusal" {
                                    throw ClaudeError.refusal(category: category, explanation: explanation)
                                }
                            case .error(let message):
                                throw ClaudeError.http(status: 200, message: message)
                            case .other:
                                break
                            }
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Checks

    private static func checkHTTP(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            var message = String(data: data, encoding: .utf8) ?? "unknown error"
            if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let err = obj["error"] as? [String: Any],
               let m = err["message"] as? String {
                message = m
            }
            throw ClaudeError.http(status: http.statusCode, message: message)
        }
    }

    private static func checkStopReason(_ r: ClaudeResponse) throws {
        switch r.stop_reason {
        case "refusal":
            throw ClaudeError.refusal(category: r.stop_details?.category, explanation: r.stop_details?.explanation)
        case "max_tokens":
            throw ClaudeError.truncated
        default:
            break
        }
    }
}

// MARK: - SSE parsing

/// Incremental Server-Sent Events parser for the Messages API stream.
struct SSEParser {
    enum Event: Equatable {
        case textDelta(String)
        case stop(reason: String?, category: String?, explanation: String?)
        case error(String)
        case other
    }

    private var currentEvent: String?
    private var dataLines: [String] = []

    /// Feed one line (without the trailing newline). Returns zero or more events.
    mutating func feed(line: String) -> [Event] {
        if line.isEmpty {
            defer { currentEvent = nil; dataLines = [] }
            guard !dataLines.isEmpty else { return [] }
            return [parse(event: currentEvent, data: dataLines.joined(separator: "\n"))]
        }
        if line.hasPrefix("event:") {
            currentEvent = line.dropFirst(6).trimmingCharacters(in: .whitespaces)
        } else if line.hasPrefix("data:") {
            dataLines.append(String(line.dropFirst(5).trimmingCharacters(in: .whitespaces)))
        }
        return []
    }

    private func parse(event: String?, data: String) -> Event {
        guard let jsonData = data.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            return .other
        }
        let type = (obj["type"] as? String) ?? event ?? ""
        switch type {
        case "content_block_delta":
            if let delta = obj["delta"] as? [String: Any],
               (delta["type"] as? String) == "text_delta",
               let text = delta["text"] as? String {
                return .textDelta(text)
            }
            return .other
        case "message_delta":
            let delta = obj["delta"] as? [String: Any]
            let details = delta?["stop_details"] as? [String: Any]
            return .stop(reason: delta?["stop_reason"] as? String,
                         category: details?["category"] as? String,
                         explanation: details?["explanation"] as? String)
        case "error":
            let err = obj["error"] as? [String: Any]
            return .error((err?["message"] as? String) ?? "stream error")
        default:
            return .other
        }
    }
}
