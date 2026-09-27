# Architecture

## Stack

- **SwiftUI + SwiftData** (iOS 17). One `ModelContainer` holds everything.
- **PencilKit** for ink. `PKCanvasView` handles Apple Pencil, palm rejection, pressure, and the built-in ink renderers. `PKDrawing` is stored per page as its native binary (`Page.drawingData`).
- **Vision** (`VNRecognizeTextRequest`) for on-device handwriting to text.
- **NaturalLanguage** (`NLEmbedding.sentenceEmbedding`) for on-device 512-dimension sentence vectors.
- **Anthropic Messages API** over raw `URLSession` (no official Swift SDK). Non-streaming JSON for structured tasks, Server-Sent Events for chat.

## Data model

```
Notebook 1─* Page 1─* NoteChunk      (text chunk + embedding)
                  1─* TutorFinding   (issue + normalized rect on the page)
         1─* ChatMessageRecord
         1─* Quiz 1─* QuizQuestion
Concept  (name, summary, related names, page ids, correct/incorrect/tutorIssue counts)
```

`Concept` deliberately stores page ids instead of a relationship so a concept can span notebooks and survive notebook deletion.

## Canvas

`CanvasView` wraps `PKCanvasView`. Two extra subviews live inside the scroll content so they pan and zoom with the page:

1. A `UIImageView` at index 0 showing the template rendered by `TemplateRenderer` (cached per template/paper/size/scale).
2. `FindingsOverlayView` on top, which draws tutor findings and only intercepts touches on its badges (`hitTest` returns nil elsewhere), so the pencil keeps drawing.

`ToolState` is an `@Observable` object shared across pages. `ToolState.pkTool` maps the UI state to a `PKInkingTool`, `PKEraserTool`, or `PKLassoTool`. The editor passes a `toolSignature` string to the representable so every property change reaches `updateUIView`.

## Page lifecycle in the editor

1. Strokes change → binding updates → save debounced 700 ms → `Page.drawingData`.
2. Pencil lifts → idle timer (default 4 s). When it fires:
   - thumbnail regenerated,
   - `KnowledgeBase.index` runs Vision OCR and rebuilds the page's chunks and embeddings (skipped if the drawing hash is unchanged),
   - if Live Tutor is on, `TutorService.review(automatic: true)` runs, subject to the minimum interval and unchanged-hash checks.

## AI services

All services are `@MainActor` singletons that take `Settings` and a `ModelContext`.

| Service | Input | Output | API features |
|---|---|---|---|
| `TutorService` | Page JPEG + OCR text | `Review` JSON: transcript, concepts, overall verdict, issues with normalized regions | vision input, structured outputs (`output_config.format`) |
| `ChatService` | Question, page image, retrieved chunks, weak concepts, last 20 messages | streamed text | SSE streaming, prompt-cached system prompt |
| `QuizService` | Up to 40 most recent pages labeled P1..Pn, weak concepts | `Generated` quiz JSON, then per-answer `Grade` JSON | structured outputs |
| `InsightsService` | Up to 60 pages labeled P1..Pn | concept graph + weak spots + suggestions | structured outputs |

Pages are labeled `P1`, `P2`... in prompts and mapped back to UUIDs locally so the model never has to reproduce identifiers.

Request conventions (see `ClaudeClient`):
- `thinking` is omitted (adaptive thinking is the default on current models); depth is controlled by `output_config.effort`.
- `fallbacks: "default"` with the `server-side-fallback-2026-07-01` beta header on Opus 5 / Fable models.
- `stop_reason == "refusal"` and `"max_tokens"` are turned into typed errors before content is read.
- System prompts in `Prompts.swift` are stable strings with `cache_control` so they cache as a prefix; volatile context goes in the user turn.

## Retrieval

`KnowledgeBase.search` embeds the query and does a brute-force cosine search over every `NoteChunk`. At personal note-taking scale (thousands of chunks) this is a few milliseconds. If it ever grows, swap in a small on-device vector index; the `Hit` interface stays the same.

## Mastery tracking

- Tutor `error`/`warning` findings increment `Concept.tutorIssueCount` for the named concept.
- Quiz grading increments `correctCount` or `incorrectCount`.
- `mastery = correct / (correct + incorrect + tutorIssues)`; `weakConcepts` sorts ascending. Weak concepts feed chat context, quiz generation (`.weakSpots` scope), and the Insights view.

## Security

- API key in Keychain (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`), never in UserDefaults or the store.
- Optional proxy mode keeps the key off the device entirely.
- Page images are only sent when an AI feature runs; OCR and embeddings stay on device.

## Next steps

- Compile on a Mac and fix first-build issues (this repo was authored without Xcode).
- App icon artwork.
- PDF import (annotate lecture slides) and PDF export of notebooks.
- iCloud sync via SwiftData's CloudKit configuration.
- Audio recording synced to ink, like Notability.
- Stroke-level "where did I go wrong" by sending Claude a cropped region when the user circles part of the page with the lasso.
- Replace brute-force retrieval with an ANN index if the note base grows large.
- Handwriting recognition for math (Vision is weak at notation) by caching Claude's transcript per page, which the tutor already writes back into `Page.aiTranscript`.
