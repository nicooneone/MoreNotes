import SwiftUI
import SwiftData
import PencilKit

enum TutorStatus: Equatable {
    case idle
    case reviewing
    case reviewed(summary: String, overall: String, nextStep: String, at: Date)
    case failed(String)
}

/// The main writing surface: canvas + floating palette + AI side panel.
struct PageEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var appState

    @State private var current: Page
    @State private var drawing = PKDrawing()
    @State private var canvas: PKCanvasView?
    @State private var canUndo = false
    @State private var canRedo = false
    @State private var selectedFindingID: UUID?
    @State private var tutorStatus: TutorStatus = .idle
    @State private var saveTask: Task<Void, Never>?
    @State private var idleTask: Task<Void, Never>?
    @State private var showTemplateSheet = false
    @State private var editTemplate: PageTemplate = .blank
    @State private var editPaper: PaperColor = .white
    @State private var errorMessage: String?
    @State private var shareItem: ShareImage?

    init(page: Page) {
        _current = State(initialValue: page)
    }

    private var notebook: Notebook? { current.notebook }
    private var pages: [Page] { notebook?.sortedPages ?? [current] }
    private var pageIndex: Int { pages.firstIndex(where: { $0.id == current.id }) ?? 0 }

    var body: some View {
        HStack(spacing: 0) {
            canvasArea
            if appState.showAIPanel {
                Divider()
                AIPanelView(page: current,
                            drawing: drawing,
                            tutorStatus: tutorStatus,
                            selectedFindingID: $selectedFindingID,
                            onCheckWork: { extra in Task { await runTutor(automatic: false, extra: extra) } },
                            onJumpToPage: { id in switchTo(pageID: id) })
                    .frame(width: 360)
            }
        }
        .navigationTitle(current.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .onAppear { load(current) }
        .onDisappear { flushSave(); idleTask?.cancel() }
        .sheet(isPresented: $showTemplateSheet) { templateSheet }
        .sheet(item: $shareItem) { item in
            let img = Image(uiImage: item.image)
            VStack(spacing: 16) {
                img.resizable().scaledToFit().padding()
                ShareLink(item: img, preview: SharePreview(current.title, image: img)) {
                    Label("Share page image", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            .presentationDetents([.large])
        }
        .sheet(item: Binding(get: { selectedFinding }, set: { if $0 == nil { selectedFindingID = nil } })) { finding in
            FindingDetailView(finding: finding) {
                finding.dismissed = true
                try? context.save()
                selectedFindingID = nil
            }
            .presentationDetents([.medium])
        }
        .alert("Something went wrong", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK") { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }

    // MARK: - Canvas

    private var canvasArea: some View {
        ZStack(alignment: .top) {
            Color(uiColor: .systemGroupedBackground).ignoresSafeArea()
            CanvasView(drawing: $drawing,
                       template: current.template,
                       paper: current.paper,
                       pageSize: current.pageSize.size,
                       tools: appState.tools,
                       toolSignature: toolSignature,
                       allowFingerDrawing: appState.allowFingerDrawing,
                       findings: overlayItems,
                       selectedFindingID: selectedFindingID,
                       onDrawingChanged: { _ in drawingChanged() },
                       onStrokeEnded: { scheduleIdleWork() },
                       onFindingTapped: { selectedFindingID = $0 },
                       onCanvasReady: { canvas = $0; refreshUndoState() })
                .ignoresSafeArea(edges: .bottom)

            ToolPaletteView(tools: appState.tools,
                            canUndo: canUndo, canRedo: canRedo,
                            onUndo: { canvas?.undoManager?.undo(); refreshUndoState() },
                            onRedo: { canvas?.undoManager?.redo(); refreshUndoState() },
                            onClearPage: { drawing = PKDrawing(); drawingChanged() })
                .padding(.top, 8)

            if tutorStatus == .reviewing {
                VStack {
                    Spacer()
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Tutor is reading your page…").font(.footnote)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.bottom, 16)
                }
                .transition(.opacity)
            }
        }
    }

    /// Reading every tool property here registers them as dependencies of this view.
    private var toolSignature: String {
        let t = appState.tools
        return "\(t.mode.rawValue)|\(t.brush.rawValue)|\(t.width)|\(t.opacity)|\(t.color.hexString)|\(t.eraser.rawValue)|\(t.eraserWidth)|\(t.rulerActive)"
    }

    private var overlayItems: [FindingsOverlayView.Item] {
        let size = current.pageSize.size
        return current.findings.filter { !$0.dismissed && !$0.rect.isEmpty }.map { f in
            FindingsOverlayView.Item(
                id: f.id,
                rect: CGRect(x: f.x * size.width, y: f.y * size.height, width: f.width * size.width, height: f.height * size.height),
                severity: f.severity)
        }
    }

    private var selectedFinding: TutorFinding? {
        guard let id = selectedFindingID else { return nil }
        return current.findings.first { $0.id == id }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button { goTo(pageIndex - 1) } label: { Image(systemName: "chevron.left") }.disabled(pageIndex == 0)
            Menu {
                ForEach(Array(pages.enumerated()), id: \.element.id) { i, p in
                    Button { goTo(i) } label: {
                        if p.id == current.id { Label(p.title, systemImage: "checkmark") } else { Text(p.title) }
                    }
                }
            } label: {
                Text("\(pageIndex + 1) / \(pages.count)").monospacedDigit().font(.subheadline)
            }
            Button { goTo(pageIndex + 1) } label: { Image(systemName: "chevron.right") }.disabled(pageIndex >= pages.count - 1)
            Button { addPage() } label: { Image(systemName: "plus.rectangle.portrait") }
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Toggle(isOn: Bindable(appState).liveTutorEnabled) {
                Label("Live Tutor", systemImage: appState.liveTutorEnabled ? "eye" : "eye.slash")
            }
            .toggleStyle(.button)
            .help("When on, the tutor reviews the page whenever the pencil rests.")

            Button {
                editTemplate = current.template; editPaper = current.paper; showTemplateSheet = true
            } label: { Image(systemName: "doc.text.image") }
            .help("Change paper template")

            Toggle(isOn: Bindable(appState).allowFingerDrawing) {
                Image(systemName: "hand.draw")
            }
            .toggleStyle(.button)
            .help("Allow drawing with a finger")

            Button { shareItem = ShareImage(image: exportImage()) } label: {
                Image(systemName: "square.and.arrow.up")
            }

            Button { appState.showAIPanel.toggle() } label: {
                Image(systemName: appState.showAIPanel ? "sidebar.trailing" : "sparkles")
            }
        }
    }

    private var templateSheet: some View {
        NavigationStack {
            Form {
                Section("Paper for this page") {
                    TemplatePickerGrid(template: $editTemplate, paper: $editPaper)
                }
                Section("Page size") {
                    Picker("Size", selection: Binding(get: { current.pageSize }, set: { current.pageSize = $0 })) {
                        ForEach(PageSize.allCases) { s in Text(s.displayName).tag(s) }
                    }
                }
            }
            .navigationTitle("Paper")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showTemplateSheet = false } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        current.template = editTemplate
                        current.paper = editPaper
                        try? context.save()
                        showTemplateSheet = false
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Page lifecycle

    private func load(_ page: Page) {
        drawing = (try? PKDrawing(data: page.drawingData)) ?? PKDrawing()
        tutorStatus = .idle
        selectedFindingID = nil
        refreshUndoState()
    }

    private func goTo(_ index: Int) {
        guard index >= 0, index < pages.count else { return }
        switchTo(pageID: pages[index].id)
    }

    private func switchTo(pageID: UUID) {
        guard pageID != current.id else { return }
        flushSave()
        idleTask?.cancel()
        var d = FetchDescriptor<Page>(predicate: #Predicate { $0.id == pageID })
        d.fetchLimit = 1
        if let next = try? context.fetch(d).first {
            current = next
            load(next)
        }
    }

    private func addPage() {
        guard let nb = notebook else { return }
        flushSave()
        let page = Page(index: nb.pages.count, template: nb.defaultTemplate, paper: nb.defaultPaper,
                        pageSize: current.pageSize)
        context.insert(page)
        page.notebook = nb
        try? context.save()
        current = page
        load(page)
    }

    private func drawingChanged() {
        refreshUndoState()
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            persistDrawing()
        }
    }

    private func flushSave() {
        saveTask?.cancel()
        persistDrawing()
    }

    private func persistDrawing() {
        let data = drawing.dataRepresentation()
        guard data != current.drawingData else { return }
        current.drawingData = data
        current.updatedAt = .now
        current.notebook?.updatedAt = .now
        try? context.save()
    }

    private func refreshUndoState() {
        canUndo = canvas?.undoManager?.canUndo ?? false
        canRedo = canvas?.undoManager?.canRedo ?? false
    }

    private func exportImage() -> UIImage {
        PageRenderer.export(drawing: drawing, template: current.template, paper: current.paper, pageSize: current.pageSize.size)
    }

    // MARK: - Idle work: index + live tutor

    private func scheduleIdleWork() {
        idleTask?.cancel()
        let delay = appState.settings.tutorIdleSeconds
        let page = current
        idleTask = Task {
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, page.id == current.id else { return }
            await runIdleWork()
        }
    }

    private func runIdleWork() async {
        persistDrawing()
        let snapshot = drawing
        let page = current
        // Thumbnail for the page grid.
        let thumb = PageRenderer.thumbnail(drawing: snapshot, template: page.template, paper: page.paper, pageSize: page.pageSize.size)
        page.thumbnailData = thumb.jpegData(compressionQuality: 0.7)
        if appState.settings.autoIndex {
            await KnowledgeBase.shared.index(page: page, drawing: snapshot, context: context)
        }
        if appState.liveTutorEnabled {
            await runTutor(automatic: true, extra: nil)
        }
    }

    private func runTutor(automatic: Bool, extra: String?) async {
        let page = current
        let snapshot = drawing
        do {
            // Automatic runs skip unchanged pages; only show the indicator when a request will be made.
            let willRun = !automatic || snapshot.dataRepresentation().hashValue != page.lastTutorHash
            if willRun { tutorStatus = .reviewing }
            let review = try await TutorService.shared.review(page: page, drawing: snapshot,
                                                              settings: appState.settings, context: context,
                                                              automatic: automatic, extraInstruction: extra)
            if let review {
                tutorStatus = .reviewed(summary: review.summary, overall: review.overall, nextStep: review.next_step_hint, at: .now)
            } else if tutorStatus == .reviewing {
                tutorStatus = .idle
            }
        } catch is CancellationError {
            tutorStatus = .idle
        } catch {
            tutorStatus = .failed(error.localizedDescription)
            if !automatic { errorMessage = error.localizedDescription }
        }
    }
}

struct ShareImage: Identifiable {
    let id = UUID()
    let image: UIImage
}

// MARK: - Finding detail

struct FindingDetailView: View {
    let finding: TutorFinding
    var onDismiss: () -> Void
    @State private var revealCorrection = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Image(systemName: icon).foregroundStyle(color).font(.title2)
                        Text(finding.title).font(.title3.weight(.semibold))
                    }
                    if !finding.conceptName.isEmpty {
                        Label(finding.conceptName, systemImage: "tag").font(.caption).foregroundStyle(.secondary)
                    }
                    GroupBox("Hint") {
                        Text(finding.hint).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if revealCorrection {
                        GroupBox("Explanation") {
                            Text(finding.explanation).frame(maxWidth: .infinity, alignment: .leading)
                        }
                    } else {
                        Button("Show the full explanation") { revealCorrection = true }
                            .buttonStyle(.bordered)
                    }
                }
                .padding()
            }
            .navigationTitle(finding.severity.rawValue.capitalized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Got it") { onDismiss() } }
            }
        }
    }

    private var icon: String {
        switch finding.severity {
        case .error: return "xmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .hint: return "lightbulb.fill"
        case .praise: return "checkmark.circle.fill"
        }
    }

    private var color: Color {
        switch finding.severity {
        case .error: return .red
        case .warning: return .orange
        case .hint: return .blue
        case .praise: return .green
        }
    }
}
