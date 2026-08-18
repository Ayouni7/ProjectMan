import SwiftData
import SwiftUI

struct RootView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \CaptureItem.createdAt, order: .reverse) private var captures: [CaptureItem]
    @Environment(ProcessingPipeline.self) private var pipeline

    var body: some View {
        TabView {
            CaptureTabView()
                .tabItem { Label("Capture", systemImage: "mic.circle.fill") }
            ProjectsTabView()
                .tabItem { Label("Projects", systemImage: "square.stack.3d.up.fill") }
            ProgressTabView()
                .tabItem { Label("Progress", systemImage: "chart.line.uptrend.xyaxis") }
            SettingsTabView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .tint(Palette.teal)
        .sheet(isPresented: onboardingBinding) {
            OnboardingView()
                .interactiveDismissDisabled()
        }
        .task {
            resumeQueuedWork()
        }
    }

    private var onboardingBinding: Binding<Bool> {
        Binding(
            get: { !settings.hasCompletedOnboarding },
            set: { if !$0 { settings.hasCompletedOnboarding = true } }
        )
    }

    private func resumeQueuedWork() {
        for capture in captures where capture.status == .queued || capture.status == .processing {
            pipeline.process(capture, context: modelContext, settings: settings)
        }
    }
}

struct OnboardingView: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("Talk, photograph, or upload. Capture turns it into a tracked project.")
                        .font(.title2.weight(.semibold))
                        .padding(.top, 8)

                    privacyCard(
                        title: "What stays on this iPhone",
                        body: "Recordings, photos, documents, and your project database are stored locally first. Nothing is auto-filed into a project until you review it."
                    )
                    privacyCard(
                        title: "What leaves the device",
                        body: "Audio is transcribed with Apple Speech (on-device when possible) or Deepgram if you add that key. Photos, PDFs, and transcripts are sent to Anthropic (Claude) to extract summaries, decisions, and tasks."
                    )
                    privacyCard(
                        title: "Recording consent",
                        body: "You are responsible for following local recording-consent laws. Tell people when a meeting is being recorded."
                    )
                    privacyCard(
                        title: "API keys",
                        body: "Keys are stored in the iOS Keychain on this device. They are never baked into the app binary. Add your Anthropic key in Settings to process captures."
                    )
                }
                .padding(20)
            }
            .background(Palette.paper)
            .navigationTitle("Welcome to Capture")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Continue") {
                        settings.hasCompletedOnboarding = true
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    private func privacyCard(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            Text(body)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
