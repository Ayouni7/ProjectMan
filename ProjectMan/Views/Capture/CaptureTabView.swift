import AVFoundation
import PhotosUI
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct CaptureTabView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppSettings.self) private var settings
    @Environment(ProcessingPipeline.self) private var pipeline
    @Query(sort: \CaptureItem.createdAt, order: .reverse) private var captures: [CaptureItem]

    @State private var recorder = AudioRecorder()
    @State private var draftID = UUID()
    @State private var draftPaths: [String] = []
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var showCamera = false
    @State private var showImporter = false
    @State private var showConsent = false
    @State private var reviewCapture: CaptureItem?
    @State private var errorMessage: String?
    @State private var didConsentThisSession = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    header
                    recordingCard
                    attachRow
                    if !draftPaths.isEmpty { draftStrip }
                    processButton
                    if !settings.hasAnthropicKey { apiBanner }
                    queueSection
                }
                .padding(20)
            }
            .background(Palette.paper)
            .navigationTitle("Capture")
            .sheet(item: $reviewCapture) { capture in
                ReviewSheet(capture: capture)
            }
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: importTypes,
                allowsMultipleSelection: true
            ) { result in
                handleImport(result)
            }
            .fullScreenCover(isPresented: $showCamera) {
                CameraPicker { image in
                    addImage(image)
                }
                .ignoresSafeArea()
            }
            .alert("Recording consent", isPresented: $showConsent) {
                Button("Start recording") {
                    didConsentThisSession = true
                    beginRecording()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Make sure everyone in the meeting knows you are recording. Local consent laws still apply.")
            }
            .alert("Capture", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
            .onChange(of: photoItems) { _, items in
                Task { await ingestPhotos(items) }
            }
            .onChange(of: pipeline.pendingReviewID) { _, id in
                if let id, let capture = captures.first(where: { $0.id == id && $0.status == .review }) {
                    reviewCapture = capture
                    pipeline.pendingReviewID = nil
                }
            }
        }
    }

    private var header: some View {
        VStack(spacing: 6) {
            Text(recorder.isRecording ? recorder.elapsed.clockString : "Ready")
                .font(.system(size: 44, weight: .semibold, design: .rounded))
                .monospacedDigit()
            Text(recorder.isRecording ? "Recording — lock the screen if you need to" : "Voice, notes, or a document")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }

    private var recordingCard: some View {
        VStack(spacing: 22) {
            LevelMeter(level: recorder.level)
            RecordButton(isRecording: recorder.isRecording) {
                toggleRecording()
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .background(.white, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private var attachRow: some View {
        HStack(spacing: 12) {
            attachButton("Camera", systemImage: "camera") { showCamera = true }
            attachButton("Files", systemImage: "folder") { showImporter = true }
            PhotosPicker(selection: $photoItems, maxSelectionCount: 6, matching: .images) {
                attachLabel("Photos", systemImage: "photo")
            }
            .buttonStyle(.plain)
        }
    }

    private func attachButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            attachLabel(title, systemImage: systemImage)
        }
        .buttonStyle(.plain)
    }

    private func attachLabel(_ title: String, systemImage: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.title3)
            Text(title)
                .font(.caption.weight(.medium))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .foregroundStyle(Palette.ink)
        .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var draftStrip: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("This capture")
                .font(.headline)
            ForEach(draftPaths, id: \.self) { path in
                HStack {
                    Image(systemName: icon(for: path))
                    Text(URL(fileURLWithPath: path).lastPathComponent)
                        .lineLimit(1)
                    Spacer()
                    Button {
                        draftPaths.removeAll { $0 == path }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.subheadline)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var processButton: some View {
        Button(action: submitDraft) {
            Text(draftPaths.isEmpty ? "Add something to process" : "Process capture")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
        }
        .buttonStyle(.borderedProminent)
        .tint(Palette.ink)
        .disabled(draftPaths.isEmpty || recorder.isRecording)
    }

    private var apiBanner: some View {
        Text("Add an Anthropic API key in Settings to extract tasks. You can still record and attach files offline.")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.sand, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var queueSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Queue")
                .font(.headline)
            if captures.isEmpty {
                Text("Captures land here while they transcribe, extract, and wait for your review.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(captures) { capture in
                    CaptureQueueRow(capture: capture) {
                        if capture.status == .review || capture.status == .filed {
                            reviewCapture = capture
                        }
                    } retry: {
                        pipeline.retry(capture, context: modelContext, settings: settings)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var importTypes: [UTType] {
        var types: [UTType] = [.pdf, .image, .audio, .mpeg4Audio]
        if let docx = UTType(filenameExtension: "docx") {
            types.append(docx)
        }
        return types
    }

    private func toggleRecording() {
        if recorder.isRecording {
            if let url = recorder.stop() {
                draftPaths.append(url.path)
            }
        } else if didConsentThisSession {
            beginRecording()
        } else {
            showConsent = true
        }
    }

    private func beginRecording() {
        Task {
            let granted = await withCheckedContinuation { continuation in
                AVAudioApplication.requestRecordPermission { allowed in
                    continuation.resume(returning: allowed)
                }
            }
            guard granted else {
                errorMessage = "Microphone access is required to record meetings."
                return
            }
            do {
                try recorder.start(captureID: draftID)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func addImage(_ image: UIImage) {
        guard let data = ImagePrep.jpegData(from: image) else { return }
        do {
            let name = "photo-\(draftPaths.count + 1).jpg"
            let path = try AssetStore.write(data, into: draftID, named: name)
            draftPaths.append(path)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func ingestPhotos(_ items: [PhotosPickerItem]) async {
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                addImage(image)
            }
        }
        photoItems = []
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            errorMessage = error.localizedDescription
        case .success(let urls):
            for url in urls {
                do {
                    let name = url.lastPathComponent
                    let path = try AssetStore.copy(url, into: draftID, named: uniqueName(name))
                    draftPaths.append(path)
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func uniqueName(_ name: String) -> String {
        let existing = Set(draftPaths.map { URL(fileURLWithPath: $0).lastPathComponent })
        if !existing.contains(name) { return name }
        let base = URL(fileURLWithPath: name).deletingPathExtension().lastPathComponent
        let ext = URL(fileURLWithPath: name).pathExtension
        return "\(base)-\(draftPaths.count).\(ext)"
    }

    private func submitDraft() {
        guard !draftPaths.isEmpty else { return }
        let kinds = Set(draftPaths.map { FileKind.captureKind(for: URL(fileURLWithPath: $0)) })
        let kind: CaptureKind = kinds.count == 1 ? kinds.first! : .mixed
        let capture = CaptureItem(
            id: draftID,
            kind: kind,
            rawAssetPath: draftPaths.first,
            extraAssetPaths: Array(draftPaths.dropFirst())
        )
        modelContext.insert(capture)
        try? modelContext.save()
        pipeline.process(capture, context: modelContext, settings: settings)
        draftID = UUID()
        draftPaths = []
    }

    private func icon(for path: String) -> String {
        FileKind.captureKind(for: URL(fileURLWithPath: path)).systemImage
    }
}

struct CaptureQueueRow: View {
    var capture: CaptureItem
    var open: () -> Void
    var retry: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(spacing: 12) {
                Image(systemName: capture.kind.systemImage)
                    .frame(width: 36, height: 36)
                    .background(Palette.sand, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text(capture.summary.isEmpty ? capture.kind.title : capture.summary)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    Text(capture.createdAt.shortStamp)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if capture.status == .failed, !capture.errorMessage.isEmpty {
                        Text(capture.errorMessage)
                            .font(.caption)
                            .foregroundStyle(Palette.coral)
                            .lineLimit(2)
                    }
                }
                Spacer()
                if capture.status == .failed {
                    Button("Retry", action: retry)
                        .font(.caption.weight(.semibold))
                }
                CaptureStatusBadge(status: capture.status)
            }
            .padding(12)
            .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(capture.status == .queued || capture.status == .processing)
    }
}
