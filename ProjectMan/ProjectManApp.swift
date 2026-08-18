import SwiftData
import SwiftUI

@main
struct ProjectManApp: App {
    @State private var settings = AppSettings()
    @State private var pipeline = ProcessingPipeline()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(settings)
                .environment(pipeline)
        }
        .modelContainer(for: [
            Project.self,
            CaptureItem.self,
            TaskItem.self,
            StatusChange.self,
            Speaker.self,
            KnownPerson.self
        ])
    }
}
