import SwiftData
import SwiftUI

struct ProjectsTabView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<Project> { $0.statusRaw == "active" }, sort: \Project.updatedAt, order: .reverse)
    private var projects: [Project]
    @State private var showNew = false
    @State private var newTitle = ""

    var body: some View {
        NavigationStack {
            Group {
                if projects.isEmpty {
                    EmptyStateView(
                        systemImage: "square.stack.3d.up",
                        title: "No projects yet",
                        message: "Review a capture to file the first one, or create a project by hand."
                    )
                } else {
                    List(projects) { project in
                        NavigationLink {
                            ProjectDetailView(project: project)
                        } label: {
                            ProjectRow(project: project)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .background(Palette.paper)
            .navigationTitle("Projects")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("New project", systemImage: "plus") { showNew = true }
                }
            }
            .alert("New project", isPresented: $showNew) {
                TextField("Title", text: $newTitle)
                Button("Create") {
                    let title = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !title.isEmpty else { return }
                    modelContext.insert(Project(title: title))
                    try? modelContext.save()
                    newTitle = ""
                }
                Button("Cancel", role: .cancel) { newTitle = "" }
            }
        }
    }
}

struct ProjectRow: View {
    var project: Project

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(project.title)
                    .font(.headline)
                Spacer()
                Text(project.percentComplete.percentLabel)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.teal)
            }
            ProgressView(value: project.percentComplete)
                .tint(Palette.teal)
            Text("\(project.openTasks.count) open · \(project.completedTasks.count) done")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
    }
}

struct ProjectDetailView: View {
    @Bindable var project: Project
    @Environment(\.modelContext) private var modelContext
    @State private var showNewTask = false
    @State private var newTaskTitle = ""

    var body: some View {
        List {
            Section {
                TextField("Title", text: $project.title)
                TextField("Description", text: $project.details, axis: .vertical)
                HStack {
                    Text("Complete")
                    Spacer()
                    Text(project.percentComplete.percentLabel)
                        .foregroundStyle(Palette.teal)
                        .fontWeight(.semibold)
                }
                ProgressView(value: project.percentComplete)
                    .tint(Palette.teal)
            }

            ForEach(groupedStatuses, id: \.self) { status in
                let items = project.tasks
                    .filter { $0.status == status }
                    .sorted { $0.createdAt > $1.createdAt }
                if !items.isEmpty {
                    Section(status.title) {
                        ForEach(items) { task in
                            NavigationLink {
                                TaskDetailView(task: task)
                            } label: {
                                TaskRow(task: task)
                            }
                        }
                    }
                }
            }

            Section("Recent captures") {
                if project.captures.isEmpty {
                    Text("No captures filed here yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(project.captures.sorted { $0.createdAt > $1.createdAt }.prefix(8)) { capture in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(capture.summary.isEmpty ? capture.kind.title : capture.summary)
                                .lineLimit(2)
                            Text(capture.createdAt.shortStamp)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle(project.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Add task", systemImage: "plus") { showNewTask = true }
            }
        }
        .alert("Add task", isPresented: $showNewTask) {
            TextField("What needs to happen?", text: $newTaskTitle)
            Button("Add") {
                let title = newTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !title.isEmpty else { return }
                let task = TaskItem(title: title)
                task.project = project
                let change = StatusChange(from: nil, to: .todo)
                change.task = task
                task.statusChanges.append(change)
                project.tasks.append(task)
                project.updatedAt = .now
                try? modelContext.save()
                newTaskTitle = ""
            }
            Button("Cancel", role: .cancel) { newTaskTitle = "" }
        }
    }

    private var groupedStatuses: [TaskStatus] {
        TaskStatus.allCases.sorted { $0.sortOrder < $1.sortOrder }
    }
}

struct TaskRow: View {
    var task: TaskItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(task.title)
                .font(.subheadline.weight(.medium))
            HStack(spacing: 8) {
                StatusBadge(status: task.status)
                if !task.owner.isEmpty {
                    Text(task.owner)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let due = task.dueDate {
                    Text(due, style: .date)
                        .font(.caption)
                        .foregroundStyle(due < .now && task.status != .done ? Palette.coral : .secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct TaskDetailView: View {
    @Bindable var task: TaskItem

    var body: some View {
        Form {
            Section("Task") {
                TextField("Description", text: $task.title, axis: .vertical)
                TextField("Owner", text: $task.owner)
                Picker("Status", selection: statusBinding) {
                    ForEach(TaskStatus.allCases) { status in
                        Text(status.title).tag(status)
                    }
                }
                Toggle("Has due date", isOn: Binding(
                    get: { task.dueDate != nil },
                    set: { task.dueDate = $0 ? (task.dueDate ?? .now) : nil }
                ))
                if task.dueDate != nil {
                    DatePicker("Due", selection: Binding(
                        get: { task.dueDate ?? .now },
                        set: { task.dueDate = $0 }
                    ), displayedComponents: .date)
                }
            }

            if let capture = task.sourceCapture {
                Section("Source") {
                    Text(capture.summary)
                    if !task.sourceQuote.isEmpty {
                        Text("“\(task.sourceQuote)”")
                            .italic()
                    }
                    Text(capture.createdAt.shortStamp)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if !capture.transcript.isEmpty {
                        DisclosureGroup("Transcript") {
                            Text(capture.transcript)
                                .font(.footnote)
                        }
                    }
                }
            }

            Section("History") {
                ForEach(task.statusChanges.sorted { $0.changedAt > $1.changedAt }) { change in
                    HStack {
                        Text(historyLabel(change))
                        Spacer()
                        Text(change.changedAt.shortStamp)
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                }
            }
        }
        .navigationTitle("Task")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var statusBinding: Binding<TaskStatus> {
        Binding(
            get: { task.status },
            set: { newValue in
                task.applyStatus(newValue)
            }
        )
    }

    private func historyLabel(_ change: StatusChange) -> String {
        let from = change.fromStatus?.title ?? "Created"
        return "\(from) → \(change.toStatus.title)"
    }
}
