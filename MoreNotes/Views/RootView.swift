import SwiftUI
import SwiftData

enum SidebarItem: Hashable {
    case notebook(UUID)
    case insights
    case quizzes
}

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var appState
    @Query(sort: \Notebook.updatedAt, order: .reverse) private var notebooks: [Notebook]

    @State private var selection: SidebarItem?
    @State private var showNewNotebook = false
    @State private var showSettings = false
    @State private var editorPath = NavigationPath()

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section("Study") {
                    Label("Insights", systemImage: "brain.head.profile").tag(SidebarItem.insights)
                    Label("Quizzes", systemImage: "checklist.checked").tag(SidebarItem.quizzes)
                }
                Section("Notebooks") {
                    ForEach(notebooks) { nb in
                        HStack(spacing: 10) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color(hex: nb.coverColorHex) ?? .blue)
                                .frame(width: 14, height: 20)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(nb.title).lineLimit(1)
                                if !nb.subject.isEmpty {
                                    Text(nb.subject).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                            }
                            Spacer()
                            Text("\(nb.pages.count)").font(.caption2).foregroundStyle(.secondary)
                        }
                        .tag(SidebarItem.notebook(nb.id))
                        .contextMenu {
                            Button(role: .destructive) { delete(nb) } label: { Label("Delete Notebook", systemImage: "trash") }
                        }
                    }
                }
            }
            .navigationTitle("MoreNotes")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showNewNotebook = true } label: { Image(systemName: "plus") }
                }
                ToolbarItem(placement: .secondaryAction) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                }
            }
        } detail: {
            NavigationStack(path: $editorPath) {
                detail
                    .navigationDestination(for: UUID.self) { pageID in
                        if let page = fetchPage(pageID) {
                            PageEditorView(page: page)
                        } else {
                            ContentUnavailableView("Page not found", systemImage: "doc.questionmark")
                        }
                    }
            }
        }
        .sheet(isPresented: $showNewNotebook) {
            NewNotebookSheet { nb in
                context.insert(nb)
                let page = Page(index: 0, template: nb.defaultTemplate, paper: nb.defaultPaper)
                context.insert(page)
                page.notebook = nb
                try? context.save()
                selection = .notebook(nb.id)
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .onAppear {
            if selection == nil, let first = notebooks.first { selection = .notebook(first.id) }
            if KeychainStore.apiKey == nil && !UserDefaults.standard.bool(forKey: "MoreNotes.seenSettings") {
                UserDefaults.standard.set(true, forKey: "MoreNotes.seenSettings")
                showSettings = true
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch selection {
        case .insights:
            InsightsView(openPage: openPage)
        case .quizzes:
            QuizListView(openPage: openPage)
        case .notebook(let id):
            if let nb = notebooks.first(where: { $0.id == id }) {
                NotebookView(notebook: nb, openPage: openPage)
            } else {
                ContentUnavailableView("Select a notebook", systemImage: "book.closed")
            }
        case nil:
            ContentUnavailableView {
                Label("Welcome to MoreNotes", systemImage: "pencil.and.scribble")
            } description: {
                Text("Create a notebook to start writing. The AI tutor watches your work, connects your notes, and quizzes you on what you've studied.")
            } actions: {
                Button("New Notebook") { showNewNotebook = true }.buttonStyle(.borderedProminent)
            }
        }
    }

    private func openPage(_ id: UUID) {
        if let page = fetchPage(id), let nb = page.notebook {
            selection = .notebook(nb.id)
        }
        editorPath.append(id)
    }

    private func fetchPage(_ id: UUID) -> Page? {
        var d = FetchDescriptor<Page>(predicate: #Predicate { $0.id == id })
        d.fetchLimit = 1
        return try? context.fetch(d).first
    }

    private func delete(_ nb: Notebook) {
        if selection == .notebook(nb.id) { selection = nil }
        context.delete(nb)
        try? context.save()
    }
}

// MARK: - New notebook

struct NewNotebookSheet: View {
    @Environment(\.dismiss) private var dismiss
    var onCreate: (Notebook) -> Void

    @State private var title = ""
    @State private var subject = ""
    @State private var colorHex = "#4F7CFF"
    @State private var template: PageTemplate = .ruledCollege
    @State private var paper: PaperColor = .white

    private let colors = ["#4F7CFF", "#D62828", "#2E8B57", "#F77F00", "#9B5DE5", "#0FA3B1", "#3A3A3C", "#FF66B3"]

    var body: some View {
        NavigationStack {
            Form {
                Section("Notebook") {
                    TextField("Title (e.g. Calculus II)", text: $title)
                    TextField("Subject (optional, helps the AI)", text: $subject)
                }
                Section("Cover") {
                    HStack {
                        ForEach(colors, id: \.self) { hex in
                            Button { colorHex = hex } label: {
                                RoundedRectangle(cornerRadius: 6).fill(Color(hex: hex) ?? .blue)
                                    .frame(width: 34, height: 44)
                                    .overlay { if hex == colorHex { RoundedRectangle(cornerRadius: 6).strokeBorder(.primary, lineWidth: 2) } }
                            }.buttonStyle(.plain)
                        }
                    }
                }
                Section("Default paper") {
                    TemplatePickerGrid(template: $template, paper: $paper)
                }
            }
            .navigationTitle("New Notebook")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        let nb = Notebook(title: title.isEmpty ? "Untitled" : title, subject: subject,
                                          coverColorHex: colorHex, template: template, paper: paper)
                        onCreate(nb)
                        dismiss()
                    }
                }
            }
        }
    }
}

/// Visual template + paper picker used when creating notebooks and changing pages.
struct TemplatePickerGrid: View {
    @Binding var template: PageTemplate
    @Binding var paper: PaperColor

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 10) {
                ForEach(PageTemplate.allCases) { t in
                    Button { template = t } label: {
                        VStack(spacing: 4) {
                            TemplateThumbnail(template: t, paper: paper)
                                .frame(width: 64, height: 84)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 6)
                                        .strokeBorder(t == template ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: t == template ? 2.5 : 1)
                                }
                            Text(t.displayName).font(.caption2).lineLimit(1).minimumScaleFactor(0.7)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            Picker("Paper", selection: $paper) {
                ForEach(PaperColor.allCases) { p in Text(p.displayName).tag(p) }
            }
            .pickerStyle(.segmented)
        }
    }
}

struct TemplateThumbnail: View {
    let template: PageTemplate
    let paper: PaperColor
    var body: some View {
        Image(uiImage: TemplateRenderer.shared.image(template: template, paper: paper,
                                                     size: CGSize(width: 306, height: 396), scale: 1))
            .resizable()
            .aspectRatio(contentMode: .fill)
    }
}
