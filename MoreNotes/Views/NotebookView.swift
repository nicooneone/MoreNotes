import SwiftUI
import SwiftData
import PencilKit

/// Grid of page thumbnails for one notebook.
struct NotebookView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var appState
    @Bindable var notebook: Notebook
    var openPage: (UUID) -> Void

    @State private var showTemplatePicker = false
    @State private var newTemplate: PageTemplate = .ruledCollege
    @State private var newPaper: PaperColor = .white
    @State private var renaming = false
    @State private var newTitle = ""
    @State private var showQuizSheet = false

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 200), spacing: 20)], spacing: 24) {
                ForEach(notebook.sortedPages) { page in
                    Button { openPage(page.id) } label: {
                        VStack(spacing: 6) {
                            PageThumbnailView(page: page)
                                .aspectRatio(page.pageSize.size.width / page.pageSize.size.height, contentMode: .fit)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
                            Text(page.title).font(.caption).lineLimit(1)
                            if !page.findings.filter({ $0.severity == .error || $0.severity == .warning }).isEmpty {
                                Label("\(page.findings.count) notes from tutor", systemImage: "exclamationmark.circle")
                                    .font(.caption2).foregroundStyle(.orange)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button(role: .destructive) { delete(page) } label: { Label("Delete Page", systemImage: "trash") }
                    }
                }
                Button {
                    newTemplate = notebook.defaultTemplate
                    newPaper = notebook.defaultPaper
                    showTemplatePicker = true
                } label: {
                    VStack {
                        Image(systemName: "plus").font(.largeTitle)
                        Text("New Page").font(.caption)
                    }
                    .frame(maxWidth: .infinity)
                    .aspectRatio(0.77, contentMode: .fit)
                    .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [6])).foregroundStyle(.secondary))
                }
                .buttonStyle(.plain)
            }
            .padding(24)
        }
        .navigationTitle(notebook.title)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button { showQuizSheet = true } label: { Label("Quiz me", systemImage: "checklist") }
                Menu {
                    Button { newTitle = notebook.title; renaming = true } label: { Label("Rename", systemImage: "pencil") }
                    Button { addPage(template: notebook.defaultTemplate, paper: notebook.defaultPaper) } label: { Label("Add Page (default paper)", systemImage: "doc.badge.plus") }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
        .sheet(isPresented: $showTemplatePicker) {
            NavigationStack {
                Form {
                    Section("Choose paper for the new page") {
                        TemplatePickerGrid(template: $newTemplate, paper: $newPaper)
                    }
                }
                .navigationTitle("New Page")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showTemplatePicker = false } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Add") {
                            addPage(template: newTemplate, paper: newPaper)
                            showTemplatePicker = false
                        }
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showQuizSheet) {
            QuizGeneratorSheet(scope: .notebook(notebook))
        }
        .alert("Rename Notebook", isPresented: $renaming) {
            TextField("Title", text: $newTitle)
            Button("Save") { notebook.title = newTitle; try? context.save() }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func addPage(template: PageTemplate, paper: PaperColor) {
        let page = Page(index: notebook.pages.count, template: template, paper: paper)
        context.insert(page)
        page.notebook = notebook
        notebook.updatedAt = .now
        try? context.save()
        openPage(page.id)
    }

    private func delete(_ page: Page) {
        context.delete(page)
        for (i, p) in notebook.sortedPages.filter({ $0.id != page.id }).enumerated() {
            p.index = i
            if p.title.hasPrefix("Page ") { p.title = "Page \(i + 1)" }
        }
        try? context.save()
    }
}

struct PageThumbnailView: View {
    let page: Page
    var body: some View {
        if let data = page.thumbnailData, let img = UIImage(data: data) {
            Image(uiImage: img).resizable()
        } else {
            TemplateThumbnail(template: page.template, paper: page.paper)
        }
    }
}
