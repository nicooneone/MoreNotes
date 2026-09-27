import SwiftUI
import SwiftData

/// "What am I working on?" — cross-notebook concept map and weak spots.
struct InsightsView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var appState
    @Query(sort: \Concept.updatedAt, order: .reverse) private var concepts: [Concept]
    var openPage: (UUID) -> Void

    @State private var working = false
    @State private var error: String?
    @State private var showQuiz = false

    private var insights: InsightsService.Insights? { InsightsService.shared.latest }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let insights {
                    GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(insights.summary)
                            Divider()
                            Label(insights.current_focus, systemImage: "scope").font(.subheadline.weight(.medium))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    } label: {
                        Label("What you're working on", systemImage: "brain.head.profile")
                    }

                    if !insights.likely_weak_spots.isEmpty {
                        GroupBox {
                            ForEach(insights.likely_weak_spots, id: \.self) { s in
                                Label(s, systemImage: "exclamationmark.triangle").font(.subheadline)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            Button { showQuiz = true } label: { Label("Quiz me on my weak spots", systemImage: "checklist") }
                                .buttonStyle(.borderedProminent).padding(.top, 6)
                        } label: {
                            Label("Likely weak spots", systemImage: "waveform.path.ecg")
                        }
                    }

                    if !insights.suggestions.isEmpty {
                        GroupBox {
                            ForEach(insights.suggestions, id: \.self) { s in
                                Label(s, systemImage: "arrow.right.circle").font(.subheadline)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        } label: {
                            Label("Suggested next steps", systemImage: "lightbulb")
                        }
                    }
                } else if !working {
                    ContentUnavailableView {
                        Label("Connect your notes", systemImage: "point.3.connected.trianglepath.dotted")
                    } description: {
                        Text("The AI reads every notebook, figures out what you're working on, links related concepts, and spots where you're shaky.")
                    } actions: {
                        Button("Analyze my notes") { refresh() }.buttonStyle(.borderedProminent)
                    }
                }

                if working {
                    HStack { ProgressView(); Text("Reading all your notes…") }.frame(maxWidth: .infinity)
                }
                if let error { Text(error).foregroundStyle(.red).font(.footnote) }

                if !concepts.isEmpty {
                    Text("Concepts").font(.title3.weight(.semibold))
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 12)], spacing: 12) {
                        ForEach(concepts) { c in
                            ConceptCard(concept: c, openPage: openPage)
                        }
                    }
                }
            }
            .padding(20)
        }
        .navigationTitle("Insights")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { refresh() } label: { Label("Refresh", systemImage: "arrow.clockwise") }.disabled(working)
            }
        }
        .sheet(isPresented: $showQuiz) { QuizGeneratorSheet(scope: .weakSpots) }
    }

    private func refresh() {
        working = true
        error = nil
        Task {
            do { _ = try await InsightsService.shared.refresh(settings: appState.settings, context: context) }
            catch { self.error = error.localizedDescription }
            working = false
        }
    }
}

struct ConceptCard: View {
    @Environment(\.modelContext) private var context
    let concept: Concept
    var openPage: (UUID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(concept.name).font(.headline)
                Spacer()
                Text(masteryLabel).font(.caption2).foregroundStyle(.secondary)
            }
            ProgressView(value: concept.mastery)
                .tint(concept.mastery < 0.4 ? .red : (concept.mastery < 0.7 ? .orange : .green))
            if !concept.summary.isEmpty {
                Text(concept.summary).font(.caption).foregroundStyle(.secondary).lineLimit(4)
            }
            if !concept.relatedConceptNames.isEmpty {
                Text("Related: " + concept.relatedConceptNames.prefix(4).joined(separator: ", "))
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(2)
            }
            if !concept.pageIDs.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(concept.pageIDs.prefix(8), id: \.self) { pid in
                            Button { openPage(pid) } label: {
                                Label(pageTitle(pid), systemImage: "doc.text").font(.caption2)
                                    .padding(.horizontal, 8).padding(.vertical, 4)
                                    .background(Color.accentColor.opacity(0.12), in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .padding(12)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    private var masteryLabel: String {
        let total = concept.correctCount + concept.incorrectCount + concept.tutorIssueCount
        if total == 0 { return "not assessed" }
        return "\(Int(concept.mastery * 100))% · \(total) signals"
    }

    private func pageTitle(_ id: UUID) -> String {
        var d = FetchDescriptor<Page>(predicate: #Predicate { $0.id == id })
        d.fetchLimit = 1
        if let p = try? context.fetch(d).first {
            return "\(p.notebook?.title ?? "") · \(p.title)"
        }
        return "Page"
    }
}
