import Foundation
import SwiftData

enum ProjectMatcher {
    static func matches(
        extraction: ExtractionResult,
        projects: [Project]
    ) -> [ProjectMatch] {
        let active = projects.filter { $0.status == .active }
        let suggestion = extraction.projectSuggestion
        var scored: [ProjectMatch] = active.map { project in
            var score = tokenSimilarity(
                haystack: searchBlob(project),
                needle: extraction.summary + " " + suggestion.title
            )
            if titlesMatch(project.title, suggestion.matchedProjectTitle) || titlesMatch(project.title, suggestion.title) {
                score = max(score, suggestion.confidence)
                score = min(1, score + 0.15 + (0.02 * Double(project.routingConfirmations)))
            }
            if suggestion.alternateTitles.contains(where: { titlesMatch(project.title, $0) }) {
                score = max(score, 0.55)
            }
            return ProjectMatch(id: project.id, title: project.title, score: min(score, 1), isNew: false)
        }
        .filter { $0.score > 0.12 }
        .sorted { $0.score > $1.score }

        let newTitle = suggestion.title.isEmpty ? "New project" : suggestion.title
        let newMatch = ProjectMatch(id: UUID(), title: newTitle, score: suggestion.isNew ? max(suggestion.confidence, 0.4) : 0.25, isNew: true)

        if scored.isEmpty {
            return [newMatch]
        }
        if suggestion.isNew {
            scored.insert(newMatch, at: min(1, scored.count))
        } else {
            scored.append(newMatch)
        }
        return Array(scored.prefix(4))
    }

    private static func searchBlob(_ project: Project) -> String {
        let captures = project.captures
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(5)
            .map { $0.summary + " " + $0.transcript.prefix(400) }
            .joined(separator: " ")
        return "\(project.title) \(project.details) \(captures)"
    }

    private static func titlesMatch(_ a: String, _ b: String?) -> Bool {
        guard let b, !b.isEmpty else { return false }
        return a.trimmingCharacters(in: .whitespacesAndNewlines).localizedCaseInsensitiveCompare(b.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame
    }

    private static func tokenSimilarity(haystack: String, needle: String) -> Double {
        let stop: Set<String> = ["the", "and", "for", "with", "that", "this", "from", "have", "were", "been", "will", "into", "about"]
        func tokens(_ text: String) -> Set<String> {
            Set(
                text.lowercased()
                    .split { !$0.isLetter && !$0.isNumber }
                    .map(String.init)
                    .filter { $0.count > 2 && !stop.contains($0) }
            )
        }
        let a = tokens(haystack)
        let b = tokens(needle)
        guard !a.isEmpty, !b.isEmpty else { return 0 }
        let overlap = a.intersection(b).count
        return Double(overlap) / Double(b.count)
    }
}

enum ProgressAggregator {
    static func snapshot(
        tasks: [TaskItem],
        projects: [Project],
        window: TimeWindow,
        projectFilter: UUID?
    ) -> ProgressSnapshot {
        let interval = window.interval()
        let previous = window.previousInterval()
        let scoped = tasks.filter { task in
            projectFilter == nil || task.project?.id == projectFilter
        }

        let completed = scoped.filter { task in
            task.statusChanges.contains { $0.toStatus == .done && interval.contains($0.changedAt) }
            || (task.status == .done && interval.contains(task.completedAt ?? task.createdAt) && task.statusChanges.isEmpty)
        }.count

        let created = scoped.filter { interval.contains($0.createdAt) }.count

        let stillOpen = scoped.filter { task in
            status(of: task, at: interval.end).map { $0 == .todo || $0 == .inProgress || $0 == .blocked } ?? false
        }.count

        let newlyBlocked = scoped.filter { task in
            task.statusChanges.contains { $0.toStatus == .blocked && interval.contains($0.changedAt) }
        }.count

        let currentRate = rate(completed: completed, created: created, open: stillOpen)
        let previousCompleted = scoped.filter { task in
            task.statusChanges.contains { $0.toStatus == .done && previous.contains($0.changedAt) }
        }.count
        let previousCreated = scoped.filter { previous.contains($0.createdAt) }.count
        let previousOpen = scoped.filter { task in
            status(of: task, at: previous.end).map { $0 == .todo || $0 == .inProgress || $0 == .blocked } ?? false
        }.count
        let previousRate = window == .all ? nil : rate(completed: previousCompleted, created: previousCreated, open: previousOpen)

        let rows: [ProjectProgressRow] = projects
            .filter { projectFilter == nil || $0.id == projectFilter }
            .filter { $0.status == .active }
            .map { project in
                let pt = scoped.filter { $0.project?.id == project.id }
                let c = pt.filter { task in
                    task.statusChanges.contains { $0.toStatus == .done && interval.contains($0.changedAt) }
                    || (task.status == .done && interval.contains(task.completedAt ?? .distantPast) && task.statusChanges.isEmpty)
                }.count
                let n = pt.filter { interval.contains($0.createdAt) }.count
                let o = pt.filter { $0.status == .todo || $0.status == .inProgress || $0.status == .blocked }.count
                return ProjectProgressRow(
                    id: project.id,
                    title: project.title,
                    completed: c,
                    created: n,
                    open: o,
                    completionRate: project.percentComplete
                )
            }
            .sorted { $0.completed > $1.completed }

        return ProgressSnapshot(
            completed: completed,
            created: created,
            stillOpen: stillOpen,
            newlyBlocked: newlyBlocked,
            completionRate: currentRate,
            previousCompletionRate: previousRate,
            perProject: rows
        )
    }

    private static func rate(completed: Int, created: Int, open: Int) -> Double {
        let denom = completed + open
        guard denom > 0 else { return created == 0 ? 0 : 0 }
        return Double(completed) / Double(denom)
    }

    private static func status(of task: TaskItem, at date: Date) -> TaskStatus? {
        if task.createdAt > date { return nil }
        let changes = task.statusChanges
            .filter { $0.changedAt <= date }
            .sorted { $0.changedAt < $1.changedAt }
        return changes.last?.toStatus ?? task.status
    }
}
