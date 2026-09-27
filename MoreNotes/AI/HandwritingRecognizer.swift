import UIKit
import Vision

/// On-device handwriting recognition (Apple Vision). Free, offline, and fast enough
/// to run every time the pencil rests. Used for search and the knowledge index.
/// Math notation is recognized poorly by Vision, so the tutor uses Claude's vision instead.
enum HandwritingRecognizer {
    struct Line {
        let text: String
        /// Normalized rect, origin top-left, 0...1.
        let rect: NormalizedRect
        let confidence: Float
    }

    static func recognize(_ image: UIImage) async throws -> [Line] {
        guard let cg = image.cgImage else { return [] }
        return try await withCheckedThrowingContinuation { cont in
            let request = VNRecognizeTextRequest { req, error in
                if let error { cont.resume(throwing: error); return }
                let lines: [Line] = (req.results as? [VNRecognizedTextObservation] ?? []).compactMap { obs in
                    guard let top = obs.topCandidates(1).first else { return nil }
                    // Vision uses a bottom-left origin; flip to top-left.
                    let b = obs.boundingBox
                    let rect = NormalizedRect(x: b.minX, y: 1 - b.maxY, width: b.width, height: b.height)
                    return Line(text: top.string, rect: rect, confidence: top.confidence)
                }
                cont.resume(returning: lines)
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["en-US"]
            let handler = VNImageRequestHandler(cgImage: cg, options: [:])
            DispatchQueue.global(qos: .userInitiated).async {
                do { try handler.perform([request]) } catch { cont.resume(throwing: error) }
            }
        }
    }

    static func text(from lines: [Line]) -> String {
        lines.sorted { a, b in
            if abs(a.rect.y - b.rect.y) > 0.015 { return a.rect.y < b.rect.y }
            return a.rect.x < b.rect.x
        }
        .map(\.text)
        .joined(separator: "\n")
    }
}
