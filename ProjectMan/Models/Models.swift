import Foundation
import SwiftData

enum CaptureKind: String, Codable, CaseIterable, Identifiable {
    case audio, photo, pdf, docx, mixed
    var id: String { rawValue }

    var title: String {
        switch self {
        case .audio: "Voice"
        case .photo: "Photo"
        case .pdf: "PDF"
        case .docx: "Word"
        case .mixed: "Mixed"
        }
    }

    var systemImage: String {
        switch self {
        case .audio: "waveform"
        case .photo: "photo"
        case .pdf: "doc.richtext"
        case .docx: "doc.text"
        case .mixed: "square.stack.3d.up"
        }
    }
}

enum CaptureStatus: String, Codable, CaseIterable {
    case queued, processing, review, filed, failed

    var title: String {
        switch self {
        case .queued: "Queued"
        case .processing: "Processing"
        case .review: "Ready to review"
        case .filed: "Filed"
        case .failed: "Failed"
        }
    }
}

enum TaskStatus: String, Codable, CaseIterable, Identifiable {
    case todo, inProgress, done, blocked, dropped
    var id: String { rawValue }

    var title: String {
        switch self {
        case .todo: "To do"
        case .inProgress: "In progress"
        case .done: "Done"
        case .blocked: "Blocked"
        case .dropped: "Dropped"
        }
    }

    var systemImage: String {
        switch self {
        case .todo: "circle"
        case .inProgress: "circle.lefthalf.filled"
        case .done: "checkmark.circle.fill"
        case .blocked: "exclamationmark.octagon.fill"
        case .dropped: "minus.circle"
        }
    }

    var sortOrder: Int {
        switch self {
        case .inProgress: 0
        case .todo: 1
        case .blocked: 2
        case .done: 3
        case .dropped: 4
        }
    }
}

enum ProjectStatus: String, Codable, CaseIterable {
    case active, archived
}

enum TimeWindow: String, CaseIterable, Identifiable {
    case week, month, quarter, year, multiYear, all
    var id: String { rawValue }

    var title: String {
        switch self {
        case .week: "Week"
        case .month: "Month"
        case .quarter: "Quarter"
        case .year: "Year"
        case .multiYear: "Multi-year"
        case .all: "All time"
        }
    }

    func interval(endingAt date: Date = .now, calendar: Calendar = .current) -> DateInterval {
        switch self {
        case .week:
            let start = calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? date
            return DateInterval(start: start, end: date)
        case .month:
            let start = calendar.dateInterval(of: .month, for: date)?.start ?? date
            return DateInterval(start: start, end: date)
        case .quarter:
            let start = calendar.dateInterval(of: .quarter, for: date)?.start ?? date
            return DateInterval(start: start, end: date)
        case .year:
            let start = calendar.dateInterval(of: .year, for: date)?.start ?? date
            return DateInterval(start: start, end: date)
        case .multiYear:
            let start = calendar.date(byAdding: .year, value: -3, to: date) ?? date
            return DateInterval(start: start, end: date)
        case .all:
            return DateInterval(start: .distantPast, end: date)
        }
    }

    func previousInterval(endingAt date: Date = .now, calendar: Calendar = .current) -> DateInterval {
        let current = interval(endingAt: date, calendar: calendar)
        switch self {
        case .week:
            let end = calendar.date(byAdding: .day, value: -1, to: current.start) ?? current.start
            return TimeWindow.week.interval(endingAt: end, calendar: calendar)
        case .month:
            let end = calendar.date(byAdding: .day, value: -1, to: current.start) ?? current.start
            return TimeWindow.month.interval(endingAt: end, calendar: calendar)
        case .quarter:
            let end = calendar.date(byAdding: .day, value: -1, to: current.start) ?? current.start
            return TimeWindow.quarter.interval(endingAt: end, calendar: calendar)
        case .year:
            let end = calendar.date(byAdding: .day, value: -1, to: current.start) ?? current.start
            return TimeWindow.year.interval(endingAt: end, calendar: calendar)
        case .multiYear:
            let end = calendar.date(byAdding: .day, value: -1, to: current.start) ?? current.start
            return DateInterval(start: calendar.date(byAdding: .year, value: -3, to: end) ?? end, end: end)
        case .all:
            return DateInterval(start: .distantPast, end: .distantPast)
        }
    }
}

@Model
final class Project {
    var id: UUID
    var title: String
    var details: String
    var statusRaw: String
    var createdAt: Date
    var updatedAt: Date
    var routingConfirmations: Int

    @Relationship(deleteRule: .cascade, inverse: \CaptureItem.project)
    var captures: [CaptureItem]

    @Relationship(deleteRule: .cascade, inverse: \TaskItem.project)
    var tasks: [TaskItem]

    var status: ProjectStatus {
        get { ProjectStatus(rawValue: statusRaw) ?? .active }
        set { statusRaw = newValue.rawValue }
    }

    var openTasks: [TaskItem] {
        tasks.filter { $0.status == .todo || $0.status == .inProgress || $0.status == .blocked }
    }

    var completedTasks: [TaskItem] {
        tasks.filter { $0.status == .done }
    }

    var percentComplete: Double {
        let countable = tasks.filter { $0.status != .dropped }
        guard !countable.isEmpty else { return 0 }
        return Double(countable.filter { $0.status == .done }.count) / Double(countable.count)
    }

    init(
        id: UUID = UUID(),
        title: String,
        details: String = "",
        status: ProjectStatus = .active,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.details = details
        self.statusRaw = status.rawValue
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.routingConfirmations = 0
        self.captures = []
        self.tasks = []
    }
}

@Model
final class CaptureItem {
    var id: UUID
    var typeRaw: String
    var rawAssetPath: String?
    var extraAssetPaths: [String]
    var transcript: String
    var summary: String
    var decisionsJSON: String
    var entitiesJSON: String
    var suggestedProjectTitle: String
    var suggestedProjectIsNew: Bool
    var suggestedConfidence: Double
    var suggestedRationale: String
    var statusRaw: String
    var errorMessage: String
    var createdAt: Date
    var processedAt: Date?

    var project: Project?

    @Relationship(deleteRule: .cascade, inverse: \TaskItem.sourceCapture)
    var extractedTasks: [TaskItem]

    @Relationship(deleteRule: .cascade, inverse: \Speaker.capture)
    var speakers: [Speaker]

    var kind: CaptureKind {
        get { CaptureKind(rawValue: typeRaw) ?? .mixed }
        set { typeRaw = newValue.rawValue }
    }

    var status: CaptureStatus {
        get { CaptureStatus(rawValue: statusRaw) ?? .queued }
        set { statusRaw = newValue.rawValue }
    }

    var decisions: [String] {
        get { (try? JSONDecoder().decode([String].self, from: Data(decisionsJSON.utf8))) ?? [] }
        set { decisionsJSON = (try? String(data: JSONEncoder().encode(newValue), encoding: .utf8)) ?? "[]" }
    }

    var entities: ExtractedEntities {
        get { (try? JSONDecoder().decode(ExtractedEntities.self, from: Data(entitiesJSON.utf8))) ?? .empty }
        set { entitiesJSON = (try? String(data: JSONEncoder().encode(newValue), encoding: .utf8)) ?? "{}" }
    }

    var allAssetPaths: [String] {
        ([rawAssetPath].compactMap { $0 } + extraAssetPaths).filter { !$0.isEmpty }
    }

    init(
        id: UUID = UUID(),
        kind: CaptureKind,
        rawAssetPath: String? = nil,
        extraAssetPaths: [String] = [],
        createdAt: Date = .now
    ) {
        self.id = id
        self.typeRaw = kind.rawValue
        self.rawAssetPath = rawAssetPath
        self.extraAssetPaths = extraAssetPaths
        self.transcript = ""
        self.summary = ""
        self.decisionsJSON = "[]"
        self.entitiesJSON = "{}"
        self.suggestedProjectTitle = ""
        self.suggestedProjectIsNew = true
        self.suggestedConfidence = 0
        self.suggestedRationale = ""
        self.statusRaw = CaptureStatus.queued.rawValue
        self.errorMessage = ""
        self.createdAt = createdAt
        self.extractedTasks = []
        self.speakers = []
    }
}

@Model
final class TaskItem {
    var id: UUID
    var title: String
    var owner: String
    var statusRaw: String
    var dueDate: Date?
    var createdAt: Date
    var completedAt: Date?
    var sourceQuote: String

    var project: Project?
    var sourceCapture: CaptureItem?

    @Relationship(deleteRule: .cascade, inverse: \StatusChange.task)
    var statusChanges: [StatusChange]

    var status: TaskStatus {
        get { TaskStatus(rawValue: statusRaw) ?? .todo }
        set { statusRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        title: String,
        owner: String = "",
        status: TaskStatus = .todo,
        dueDate: Date? = nil,
        createdAt: Date = .now,
        sourceQuote: String = ""
    ) {
        self.id = id
        self.title = title
        self.owner = owner
        self.statusRaw = status.rawValue
        self.dueDate = dueDate
        self.createdAt = createdAt
        self.sourceQuote = sourceQuote
        self.statusChanges = []
    }

    func applyStatus(_ newStatus: TaskStatus, at date: Date = .now) {
        let old = status
        guard old != newStatus else { return }
        let change = StatusChange(from: old, to: newStatus, at: date)
        change.task = self
        statusChanges.append(change)
        status = newStatus
        completedAt = newStatus == .done ? date : nil
        project?.updatedAt = date
    }
}

@Model
final class StatusChange {
    var id: UUID
    var fromStatusRaw: String
    var toStatusRaw: String
    var changedAt: Date
    var task: TaskItem?

    var fromStatus: TaskStatus? { TaskStatus(rawValue: fromStatusRaw) }
    var toStatus: TaskStatus { TaskStatus(rawValue: toStatusRaw) ?? .todo }

    init(from: TaskStatus?, to: TaskStatus, at: Date = .now) {
        self.id = UUID()
        self.fromStatusRaw = from?.rawValue ?? ""
        self.toStatusRaw = to.rawValue
        self.changedAt = at
    }
}

@Model
final class Speaker {
    var id: UUID
    var label: String
    var resolvedName: String
    var capture: CaptureItem?

    var displayName: String {
        resolvedName.isEmpty ? label : resolvedName
    }

    init(label: String, resolvedName: String = "") {
        self.id = UUID()
        self.label = label
        self.resolvedName = resolvedName
    }
}

@Model
final class KnownPerson {
    var id: UUID
    var name: String
    var createdAt: Date

    init(name: String) {
        self.id = UUID()
        self.name = name
        self.createdAt = .now
    }
}

struct ExtractedEntities: Codable, Hashable {
    var people: [String]
    var dates: [String]
    var references: [String]

    static let empty = ExtractedEntities(people: [], dates: [], references: [])
}

struct ExtractionResult: Codable {
    var summary: String
    var decisions: [String]
    var actionItems: [ExtractedActionItem]
    var projectSuggestion: ProjectSuggestion
    var entities: ExtractedEntities
    var speakers: [ExtractedSpeaker]

    enum CodingKeys: String, CodingKey {
        case summary, decisions, entities, speakers
        case actionItems = "action_items"
        case projectSuggestion = "project_suggestion"
    }
}

struct ExtractedActionItem: Codable, Identifiable, Hashable {
    var id: UUID
    var description: String
    var owner: String?
    var dueDate: String?
    var quote: String?

    enum CodingKeys: String, CodingKey {
        case description, owner, quote
        case dueDate = "due_date"
    }

    init(description: String, owner: String? = nil, dueDate: String? = nil, quote: String? = nil) {
        self.id = UUID()
        self.description = description
        self.owner = owner
        self.dueDate = dueDate
        self.quote = quote
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = UUID()
        description = try container.decodeIfPresent(String.self, forKey: .description) ?? ""
        owner = try container.decodeIfPresent(String.self, forKey: .owner)
        dueDate = try container.decodeIfPresent(String.self, forKey: .dueDate)
        quote = try container.decodeIfPresent(String.self, forKey: .quote)
    }
}

struct ProjectSuggestion: Codable, Hashable {
    var title: String
    var isNew: Bool
    var matchedProjectTitle: String?
    var confidence: Double
    var rationale: String
    var alternateTitles: [String]

    enum CodingKeys: String, CodingKey {
        case title, confidence, rationale
        case isNew = "is_new"
        case matchedProjectTitle = "matched_project_title"
        case alternateTitles = "alternate_titles"
    }

    init(
        title: String,
        isNew: Bool,
        matchedProjectTitle: String? = nil,
        confidence: Double,
        rationale: String,
        alternateTitles: [String] = []
    ) {
        self.title = title
        self.isNew = isNew
        self.matchedProjectTitle = matchedProjectTitle
        self.confidence = confidence
        self.rationale = rationale
        self.alternateTitles = alternateTitles
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? "Untitled project"
        isNew = try container.decodeIfPresent(Bool.self, forKey: .isNew) ?? true
        matchedProjectTitle = try container.decodeIfPresent(String.self, forKey: .matchedProjectTitle)
        confidence = try container.decodeIfPresent(Double.self, forKey: .confidence) ?? 0
        rationale = try container.decodeIfPresent(String.self, forKey: .rationale) ?? ""
        alternateTitles = try container.decodeIfPresent([String].self, forKey: .alternateTitles) ?? []
    }
}

struct ExtractedSpeaker: Codable, Hashable {
    var label: String
    var suggestedName: String?

    enum CodingKeys: String, CodingKey {
        case label
        case suggestedName = "suggested_name"
    }
}

struct ProjectMatch: Identifiable, Hashable {
    var id: UUID
    var title: String
    var score: Double
    var isNew: Bool
}

struct ProgressSnapshot {
    var completed: Int
    var created: Int
    var stillOpen: Int
    var newlyBlocked: Int
    var completionRate: Double
    var previousCompletionRate: Double?
    var perProject: [ProjectProgressRow]
}

struct ProjectProgressRow: Identifiable {
    var id: UUID
    var title: String
    var completed: Int
    var created: Int
    var open: Int
    var completionRate: Double
}
