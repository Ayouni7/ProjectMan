import SwiftData
import SwiftUI

struct ProgressTabView: View {
    @Environment(AppSettings.self) private var settings
    @Query(sort: \Project.title) private var projects: [Project]
    @Query private var tasks: [TaskItem]

    @State private var window: TimeWindow = .week
    @State private var projectID: UUID?
    @State private var narrative = ""
    @State private var isWriting = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Picker("Window", selection: $window) {
                        ForEach(TimeWindow.allCases) { item in
                            Text(item.title).tag(item)
                        }
                    }
                    .pickerStyle(.menu)

                    Picker("Scope", selection: $projectID) {
                        Text("All projects").tag(Optional<UUID>.none)
                        ForEach(projects.filter { $0.status == .active }) { project in
                            Text(project.title).tag(Optional(project.id))
                        }
                    }

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        MetricCard(title: "Completed", value: "\(snapshot.completed)")
                        MetricCard(title: "Created", value: "\(snapshot.created)")
                        MetricCard(title: "Still open", value: "\(snapshot.stillOpen)")
                        MetricCard(title: "Blocked", value: "\(snapshot.newlyBlocked)", tint: Palette.coral)
                    }

                    MetricCard(
                        title: "Completion",
                        value: snapshot.completionRate.percentLabel,
                        subtitle: trendText,
                        tint: Palette.teal
                    )

                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Narrative")
                                .font(.headline)
                            Spacer()
                            Button(isWriting ? "Writing…" : "Generate") {
                                Task { await writeNarrative() }
                            }
                            .disabled(isWriting || !settings.hasAnthropicKey)
                        }
                        if let errorMessage {
                            Text(errorMessage)
                                .font(.caption)
                                .foregroundStyle(Palette.coral)
                        }
                        Text(narrative.isEmpty ? "Generate a short “what moved” summary for this window." : narrative)
                            .font(.body)
                            .foregroundStyle(narrative.isEmpty ? .secondary : .primary)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                    VStack(alignment: .leading, spacing: 12) {
                        Text("By project")
                            .font(.headline)
                        if snapshot.perProject.isEmpty {
                            Text("No project activity in this window.")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(snapshot.perProject) { row in
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Text(row.title).font(.subheadline.weight(.semibold))
                                        Spacer()
                                        Text(row.completionRate.percentLabel)
                                            .foregroundStyle(Palette.teal)
                                            .font(.subheadline.weight(.semibold))
                                    }
                                    Text("Completed \(row.completed) · created \(row.created) · open \(row.open)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    ProgressView(value: row.completionRate)
                                        .tint(Palette.teal)
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .padding(20)
            }
            .background(Palette.paper)
            .navigationTitle("Progress")
            .onChange(of: window) { _, _ in narrative = "" }
            .onChange(of: projectID) { _, _ in narrative = "" }
        }
    }

    private var snapshot: ProgressSnapshot {
        ProgressAggregator.snapshot(tasks: tasks, projects: projects, window: window, projectFilter: projectID)
    }

    private var trendText: String? {
        guard let previous = snapshot.previousCompletionRate, window != .all else { return nil }
        let delta = Int(((snapshot.completionRate - previous) * 100).rounded())
        if delta == 0 { return "Flat vs previous \(window.title.lowercased())" }
        return "\(delta > 0 ? "+" : "")\(delta) pp vs previous \(window.title.lowercased())"
    }

    private func writeNarrative() async {
        isWriting = true
        errorMessage = nil
        defer { isWriting = false }
        let highlights = tasks
            .filter { projectID == nil || $0.project?.id == projectID }
            .filter { $0.status == .done || $0.status == .blocked }
            .sorted { ($0.completedAt ?? $0.createdAt) > ($1.completedAt ?? $1.createdAt) }
            .prefix(8)
            .map { "• \($0.title) (\($0.status.title))" }
        do {
            narrative = try await ClaudeService.narrative(
                window: window,
                scopeTitle: projects.first(where: { $0.id == projectID })?.title ?? "all projects",
                snapshot: snapshot,
                highlights: Array(highlights),
                settings: settings
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
