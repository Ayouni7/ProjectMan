import Foundation
import SwiftData
import UIKit

@Observable
final class ProcessingPipeline {
    var activeIDs: Set<UUID> = []
    var pendingReviewID: UUID?

    func process(_ capture: CaptureItem, context: ModelContext, settings: AppSettings) {
        guard !activeIDs.contains(capture.id) else { return }
        Task { await run(capture, context: context, settings: settings) }
    }

    func retry(_ capture: CaptureItem, context: ModelContext, settings: AppSettings) {
        capture.errorMessage = ""
        capture.status = .queued
        process(capture, context: context, settings: settings)
    }

    private func run(_ capture: CaptureItem, context: ModelContext, settings: AppSettings) async {
        activeIDs.insert(capture.id)
        capture.status = .processing
        capture.errorMessage = ""
        persist(context)

        do {
            try await preprocess(capture, settings: settings)
            persist(context)

            let projects = (try? context.fetch(FetchDescriptor<Project>())) ?? []
            let people = ((try? context.fetch(FetchDescriptor<KnownPerson>())) ?? []).map(\.name)

            let extraction = try await ClaudeService.extract(
                capture: capture,
                projects: projects,
                people: people,
                settings: settings
            )
            apply(extraction, to: capture)
            capture.status = .review
            capture.processedAt = .now
            pendingReviewID = capture.id
            persist(context)
        } catch {
            capture.status = .failed
            capture.errorMessage = error.localizedDescription
            persist(context)
        }

        activeIDs.remove(capture.id)
    }

    private func preprocess(_ capture: CaptureItem, settings: AppSettings) async throws {
        let paths = capture.allAssetPaths
        for path in paths {
            let url = AssetStore.fileURL(path)
            let ext = url.pathExtension.lowercased()
            if ["m4a", "wav", "mp3", "caf", "aac"].contains(ext), capture.transcript.isEmpty {
                let result = try await TranscriptionService.transcribe(audioURL: url, settings: settings)
                capture.transcript = result.text
                if capture.speakers.isEmpty {
                    for speaker in result.speakers {
                        let model = Speaker(label: speaker.label, resolvedName: speaker.suggestedName ?? "")
                        model.capture = capture
                        capture.speakers.append(model)
                    }
                }
            }
            if ext == "docx", capture.transcript.isEmpty {
                let text = try DocumentTextExtractor.extractText(from: url)
                if !text.isEmpty {
                    capture.transcript = text
                }
            }
        }
    }

    private func apply(_ extraction: ExtractionResult, to capture: CaptureItem) {
        capture.summary = extraction.summary
        capture.decisions = extraction.decisions
        capture.entities = extraction.entities
        capture.suggestedProjectTitle = extraction.projectSuggestion.title
        capture.suggestedProjectIsNew = extraction.projectSuggestion.isNew
        capture.suggestedConfidence = extraction.projectSuggestion.confidence
        capture.suggestedRationale = extraction.projectSuggestion.rationale

        if capture.speakers.isEmpty {
            for speaker in extraction.speakers {
                let model = Speaker(label: speaker.label, resolvedName: speaker.suggestedName ?? "")
                model.capture = capture
                capture.speakers.append(model)
            }
        } else {
            for extracted in extraction.speakers {
                if let existing = capture.speakers.first(where: { $0.label == extracted.label }),
                   existing.resolvedName.isEmpty,
                   let name = extracted.suggestedName {
                    existing.resolvedName = name
                }
            }
        }

        capture.extractedTasks.removeAll()
        let formatter = DateFormatter()
        formatter.calendar = Calendar.current
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"

        for item in extraction.actionItems where !item.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let due = item.dueDate.flatMap { formatter.date(from: $0) }
            let task = TaskItem(
                title: item.description,
                owner: item.owner ?? "",
                dueDate: due,
                sourceQuote: item.quote ?? ""
            )
            task.sourceCapture = capture
            capture.extractedTasks.append(task)
        }
    }

    static func commit(
        capture: CaptureItem,
        selected: ProjectMatch,
        existingProjects: [Project],
        people: [KnownPerson],
        context: ModelContext
    ) {
        let project: Project
        if selected.isNew {
            project = Project(title: selected.title.isEmpty ? "Untitled project" : selected.title, details: capture.summary)
            context.insert(project)
        } else if let found = existingProjects.first(where: { $0.id == selected.id }) {
            project = found
            if project.details.isEmpty, !capture.summary.isEmpty {
                project.details = capture.summary
            }
        } else {
            project = Project(title: selected.title, details: capture.summary)
            context.insert(project)
        }

        project.updatedAt = .now
        project.routingConfirmations += 1
        capture.project = project
        if !project.captures.contains(where: { $0.id == capture.id }) {
            project.captures.append(capture)
        }

        for task in capture.extractedTasks {
            task.project = project
            if task.statusChanges.isEmpty {
                let change = StatusChange(from: nil, to: task.status)
                change.task = task
                task.statusChanges.append(change)
            }
            if !project.tasks.contains(where: { $0.id == task.id }) {
                project.tasks.append(task)
            }
        }

        for speaker in capture.speakers where !speaker.resolvedName.isEmpty {
            let name = speaker.resolvedName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !people.contains(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
                context.insert(KnownPerson(name: name))
            }
        }

        capture.status = .filed
        try? context.save()
    }

    private func persist(_ context: ModelContext) {
        try? context.save()
    }
}

enum ImagePrep {
    static func jpegData(from image: UIImage) -> Data? {
        image.resized(maxDimension: 2000).jpegData(compressionQuality: 0.82)
    }
}

private extension UIImage {
    func resized(maxDimension: CGFloat) -> UIImage {
        let longest = max(size.width, size.height)
        guard longest > maxDimension else { return self }
        let scale = maxDimension / longest
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in draw(in: CGRect(origin: .zero, size: newSize)) }
    }
}
