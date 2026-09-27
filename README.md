# MoreNotes

A handwriting note-taking app for iPad with a built-in AI tutor. Write with an Apple Pencil (or a Bluetooth stylus) on GoodNotes-style paper templates, and let Claude read your pages, catch mistakes as you work, connect ideas across notebooks, and quiz you on what you have studied.

Built for the iPad (8th generation) with Apple Pencil 1st gen, and works on any iPad running iPadOS 17 or later.

## What it does

**Writing**
- PencilKit canvas with pressure and tilt: ballpoint pen, pencil, highlighter, monoline, fountain pen, watercolor, crayon.
- Adjustable width and opacity per brush, 15 swatches plus a full color picker, saved favorites.
- Three erasers: stroke, pixel, and precise (fixed width). Lasso selection and a ruler.
- 15 paper templates (narrow/college/wide ruled, 5/7.5/10 mm grid, dot grid, Cornell, graph with axes, isometric, music staff, checklist, daily planner, engineering) on five paper colors, at Letter, A4, iPad, square, or landscape sizes.
- Pinch zoom, palm rejection through PencilKit, optional finger drawing, Pencil 2 double-tap support, undo/redo, page export as an image.

**AI tutor (Claude)**
- **Live Tutor**: a few seconds after your pencil rests, the page is sent to Claude as an image. Mistakes are drawn on the page as highlighted regions with a badge. Tap a badge for a hint first, then the full explanation. Works on math steps, sign errors, wrong rules, units, chemistry, and so on.
- **Check my work**: same review on demand, optionally with a question like "is step 3 right?".
- **Chat**: ask anything. Each question retrieves the most relevant passages from every notebook you own, includes the current page, and knows which concepts you have struggled with.
- **Insights**: "what am I working on?" across all notebooks. Builds a concept list, links related concepts, and points to likely weak spots.
- **Quizzes**: generated from your own notes, biased toward concepts you missed on earlier quizzes or that the tutor flagged. Multiple choice is graded on device; short answers and worked problems are graded by Claude with feedback. Every question links back to the page it came from.

**Knowledge base (on device)**
- Handwriting is recognized with Apple's Vision framework, chunked, and embedded with Apple's on-device sentence embeddings. Nothing leaves the device until you use an AI feature.
- Concept mastery is tracked from quiz results and tutor findings.

## Requirements

- A Mac with Xcode 16 or newer.
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) to generate the project: `brew install xcodegen`.
- An iPad on iPadOS 17+ (iPad 8th gen supports this) and an Apple Developer account for on-device installs. A free account works for personal sideloading.
- An Anthropic API key from https://console.anthropic.com for the AI features. The rest of the app works without one.

## Build and run

```bash
git clone https://github.com/nicooneone/MoreNotes.git
cd MoreNotes
xcodegen generate
open MoreNotes.xcodeproj
```

In Xcode: select the MoreNotes target, set your Team under Signing & Capabilities, plug in the iPad, and Run. On first launch the app opens Settings so you can paste your API key. It is stored in the iOS Keychain.

Run the unit tests with Cmd+U. They cover the Server-Sent Events parser, the request body shape sent to the Claude API, embedding packing, text chunking, and template metadata.

## AI settings and cost

Settings lets you pick the model, the effort level for background reviews versus chat, how long the pencil must rest before a review, and the minimum gap between reviews. Every review sends one JPEG of the page (about 1500 px on the long side), so the interval settings directly control API usage. Handwriting recognition and embeddings are on-device and free.

Default model is Claude Opus 5 with server-side refusal fallbacks enabled. Claude Sonnet 5 is cheaper for heavy Live Tutor use.

If you would rather not keep the API key on the iPad, set a proxy URL in Settings. The app then posts the same request body to `<proxy>/v1/messages` and expects the proxy to add the `x-api-key` header.

## Project layout

```
project.yml                 XcodeGen spec (generates MoreNotes.xcodeproj)
MoreNotes/
  App/        MoreNotesApp.swift            entry point, SwiftData container, AppState
  Models/     Models.swift, Settings.swift  SwiftData models: Notebook, Page, NoteChunk, Concept, TutorFinding, Quiz...
  Templates/  PageTemplate.swift, TemplateRenderer.swift
  Canvas/     CanvasView.swift (PKCanvasView wrapper), ToolState.swift, ToolPaletteView.swift,
              FindingsOverlayView.swift (tutor highlights), PageRenderer.swift
  AI/         ClaudeClient.swift (raw HTTP + SSE), KeychainStore.swift, Prompts.swift,
              HandwritingRecognizer.swift (Vision), KnowledgeBase.swift (embeddings + retrieval),
              TutorService.swift, ChatService.swift, QuizService.swift, InsightsService.swift
  Views/      RootView, NotebookView, PageEditorView, AIPanelView, QuizViews, InsightsView, SettingsView
MoreNotesTests/             XCTest unit tests
docs/ARCHITECTURE.md        how the pieces fit together
```

## Status

This is the first cut. The code was written without access to a Mac, so it has not yet been compiled in Xcode. Expect to fix a handful of compiler complaints on the first build; the structure and API calls were checked against current Anthropic API documentation. See `docs/ARCHITECTURE.md` for the design and the list of next steps.
