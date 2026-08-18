import SwiftData
import SwiftUI

struct ReviewSheet: View {
    @Bindable var capture: CaptureItem
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<Project> { $0.statusRaw == "active" }, sort: \Project.updatedAt, order: .reverse)
    private var projects: [Project]
    @Query(sort: \KnownPerson.name) private var people: [KnownPerson]

    @State private var matches: [ProjectMatch] = []
    @State private var selected: ProjectMatch?
    @State private var customTitle = ""
    @State private var showChooser = false

    var body: some View {
        NavigationStack {
            Form {
                routingSection
                Section("Summary") {
                    TextField("Summary", text: $capture.summary, axis: .vertical)
                        .lineLimit(3...8)
                }
                Section("Decisions") {
                    if capture.decisions.isEmpty {
                        Text("No decisions extracted").foregroundStyle(.secondary)
                    }
                    ForEach(Array(capture.decisions.enumerated()), id: \.offset) { index, _ in
                        TextField("Decision", text: decisionBinding(index), axis: .vertical)
                    }
                    Button("Add decision") {
                        var items = capture.decisions
                        items.append("")
                        capture.decisions = items
                    }
                }
                Section("Action items") {
                    ForEach(capture.extractedTasks) { task in
                        ReviewTaskEditor(task: task)
                    }
                    .onDelete(perform: deleteTasks)
                    Button("Add task") {
                        let task = TaskItem(title: "")
                        task.sourceCapture = capture
                        capture.extractedTasks.append(task)
                    }
                }
                if !capture.speakers.isEmpty {
                    Section("Speakers") {
                        ForEach(capture.speakers) { speaker in
                            ReviewSpeakerEditor(speaker: speaker)
                        }
                    }
                }
                if !capture.transcript.isEmpty {
                    Section("Transcript") {
                        Text(capture.transcript)
                            .font(.footnote)
                            .textSelection(.enabled)
                    }
                }
                Section("Entities") {
                    labeled("People", capture.entities.people)
                    labeled("Dates", capture.entities.dates)
                    labeled("References", capture.entities.references)
                }
            }
            .navigationTitle("Review")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", action: dismiss.callAsFunction)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                        .disabled(capture.status == .filed || selected == nil)
                }
            }
            .onAppear { bootstrapMatches() }
        }
    }

    @ViewBuilder
    private var routingSection: some View {
        Section("File under") {
            if capture.status == .filed, let project = capture.project {
                Text("Filed in \(project.title)")
            } else if let selected, selected.score >= 0.75, !showChooser, !selected.isNew {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Add to \(selected.title)?")
                        .font(.headline)
                    Text(capture.suggestedRationale)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack {
                        Button("Confirm") { save() }
                            .buttonStyle(.borderedProminent)
                        Button("Choose different") { showChooser = true }
                        Button("New project") {
                            self.selected = ProjectMatch(id: UUID(), title: customTitle.isEmpty ? capture.suggestedProjectTitle : customTitle, score: 1, isNew: true)
                            showChooser = true
                        }
                    }
                    .font(.subheadline)
                }
            } else {
                Picker("Project", selection: selectedID) {
                    ForEach(matches) { match in
                        Text(match.isNew ? "Create “\(displayTitle(match))”" : "\(match.title)  \(Int(match.score * 100))%")
                            .tag(Optional(match.id))
                    }
                }
                if selected?.isNew == true {
                    TextField("New project title", text: $customTitle)
                }
            }
        }
    }

    private var selectedID: Binding<UUID?> {
        Binding(
            get: { selected?.id },
            set: { id in selected = matches.first { $0.id == id } }
        )
    }

    private func displayTitle(_ match: ProjectMatch) -> String {
        if match.isNew {
            return customTitle.isEmpty ? match.title : customTitle
        }
        return match.title
    }

    private func bootstrapMatches() {
        customTitle = capture.suggestedProjectTitle
        let reconstruction = ExtractionResult(
            summary: capture.summary,
            decisions: capture.decisions,
            actionItems: capture.extractedTasks.map {
                ExtractedActionItem(description: $0.title, owner: $0.owner, quote: $0.sourceQuote)
            },
            projectSuggestion: ProjectSuggestion(
                title: capture.suggestedProjectTitle,
                isNew: capture.suggestedProjectIsNew,
                matchedProjectTitle: capture.suggestedProjectIsNew ? nil : capture.suggestedProjectTitle,
                confidence: capture.suggestedConfidence,
                rationale: capture.suggestedRationale
            ),
            entities: capture.entities,
            speakers: capture.speakers.map { ExtractedSpeaker(label: $0.label, suggestedName: $0.resolvedName) }
        )
        matches = ProjectMatcher.matches(extraction: reconstruction, projects: projects)
        selected = matches.first
        showChooser = (selected?.score ?? 0) < 0.75
    }

    private func decisionBinding(_ index: Int) -> Binding<String> {
        Binding(
            get: { capture.decisions.indices.contains(index) ? capture.decisions[index] : "" },
            set: { value in
                var items = capture.decisions
                guard items.indices.contains(index) else { return }
                items[index] = value
                capture.decisions = items
            }
        )
    }

    private func deleteTasks(at offsets: IndexSet) {
        for index in offsets {
            let task = capture.extractedTasks[index]
            modelContext.delete(task)
        }
        capture.extractedTasks.remove(atOffsets: offsets)
    }

    private func labeled(_ title: String, _ values: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(values.isEmpty ? "—" : values.joined(separator: ", "))
        }
    }

    private func save() {
        guard var selected else { return }
        if selected.isNew {
            selected.title = customTitle.isEmpty ? selected.title : customTitle
        }
        capture.extractedTasks.removeAll { $0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        var items = capture.decisions
        items.removeAll { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        capture.decisions = items
        ProcessingPipeline.commit(
            capture: capture,
            selected: selected,
            existingProjects: projects,
            people: people,
            context: modelContext
        )
        dismiss()
    }
}

private struct ReviewTaskEditor: View {
    @Bindable var task: TaskItem

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Task", text: $task.title, axis: .vertical)
            TextField("Owner", text: $task.owner)
            DatePicker(
                "Due",
                selection: Binding(
                    get: { task.dueDate ?? Date() },
                    set: { task.dueDate = $0 }
                ),
                displayedComponents: .date
            )
            if !task.sourceQuote.isEmpty {
                Text("“\(task.sourceQuote)”")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct ReviewSpeakerEditor: View {
    @Bindable var speaker: Speaker

    var body: some View {
        HStack {
            Text(speaker.label)
                .foregroundStyle(.secondary)
            TextField("Name", text: $speaker.resolvedName)
        }
    }
}

