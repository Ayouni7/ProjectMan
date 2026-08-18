import SwiftData
import SwiftUI

struct SettingsTabView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \KnownPerson.name) private var people: [KnownPerson]
    @Query private var projects: [Project]
    @Query private var tasks: [TaskItem]
    @Query private var captures: [CaptureItem]

    @State private var newPerson = ""
    @State private var testMessage: String?
    @State private var isTesting = false

    var body: some View {
        @Bindable var settings = settings
        NavigationStack {
            Form {
                Section {
                    Text("Meetings and notes leave this device only when you process a capture. Keys stay in the Keychain.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Section("Claude") {
                    SecureField("Anthropic API key", text: $settings.anthropicAPIKey)
                        .textContentType(.password)
                        .autocorrectionDisabled()
                    TextField("Model", text: $settings.claudeModel)
                        .textInputAutocapitalization(.never)
                    Button(isTesting ? "Testing…" : "Test connection") {
                        Task { await testClaude() }
                    }
                    .disabled(!settings.hasAnthropicKey || isTesting)
                    if let testMessage {
                        Text(testMessage).font(.caption)
                    }
                }

                Section("Transcription") {
                    Toggle("Prefer on-device Apple Speech", isOn: $settings.preferOnDeviceSpeech)
                    Toggle("Use Deepgram when a key is present", isOn: $settings.useDeepgramWhenAvailable)
                    SecureField("Deepgram API key (optional)", text: $settings.deepgramAPIKey)
                        .textContentType(.password)
                    Text("Deepgram adds speaker diarization (Speaker 1, 2, 3). Apple Speech transcribes without speaker labels.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("People") {
                    ForEach(people) { person in
                        Text(person.name)
                    }
                    .onDelete { offsets in
                        for index in offsets {
                            modelContext.delete(people[index])
                        }
                    }
                    HStack {
                        TextField("Add a name", text: $newPerson)
                        Button("Add") {
                            let name = newPerson.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !name.isEmpty else { return }
                            modelContext.insert(KnownPerson(name: name))
                            newPerson = ""
                        }
                    }
                }

                Section("Data") {
                    Button("Export JSON") { export() }
                    ShareLink(item: exportFile) {
                        Label("Share latest export", systemImage: "square.and.arrow.up")
                    }
                    .disabled(!FileManager.default.fileExists(atPath: exportFile.path))
                }

                Section("Privacy") {
                    LabeledContent("Captures", value: "\(captures.count)")
                    LabeledContent("Projects", value: "\(projects.count)")
                    LabeledContent("Tasks", value: "\(tasks.count)")
                    Text("Raw audio, photos, and documents live in the app’s Documents folder. Delete the app to remove local files.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
        }
    }

    private var exportFile: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("capture-export.json")
    }

    private func testClaude() async {
        isTesting = true
        defer { isTesting = false }
        do {
            try await ClaudeService.testConnection(apiKey: settings.anthropicAPIKey, model: settings.claudeModel)
            testMessage = "Connected."
        } catch {
            testMessage = error.localizedDescription
        }
    }

    private func export() {
        let payload: [String: Any] = [
            "exportedAt": ISO8601DateFormatter().string(from: .now),
            "projects": projects.map { project in
                [
                    "id": project.id.uuidString,
                    "title": project.title,
                    "details": project.details,
                    "percentComplete": project.percentComplete,
                    "tasks": project.tasks.map { task in
                        [
                            "title": task.title,
                            "owner": task.owner,
                            "status": task.status.rawValue,
                            "dueDate": task.dueDate.map { ISO8601DateFormatter().string(from: $0) } ?? "",
                            "sourceQuote": task.sourceQuote
                        ]
                    }
                ]
            }
        ]
        if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: exportFile, options: .atomic)
        }
    }
}
