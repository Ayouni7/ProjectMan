import AVFoundation
import Foundation

@Observable
final class AudioRecorder {
    var isRecording = false
    var level: Float = 0
    var elapsed: TimeInterval = 0
    var lastError: String?

    private var recorder: AVAudioRecorder?
    private var meterTask: Task<Void, Never>?
    private var startedAt: Date?
    private var outputURL: URL?

    func start(captureID: UUID) throws {
        lastError = nil
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothHFP])
        try session.setActive(true)

        let url = AssetStore.folder(for: captureID).appendingPathComponent("audio.m4a")
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        let rec = try AVAudioRecorder(url: url, settings: settings)
        rec.isMeteringEnabled = true
        rec.prepareToRecord()
        guard rec.record() else {
            throw RecorderError.failedToStart
        }

        recorder = rec
        outputURL = url
        startedAt = .now
        isRecording = true
        elapsed = 0
        startMetering()
    }

    func stop() -> URL? {
        meterTask?.cancel()
        meterTask = nil
        recorder?.stop()
        recorder = nil
        isRecording = false
        level = 0
        let url = outputURL
        outputURL = nil
        startedAt = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        return url
    }

    private func startMetering() {
        meterTask?.cancel()
        meterTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(80))
                guard let self, let recorder = self.recorder, recorder.isRecording else { continue }
                recorder.updateMeters()
                let power = recorder.averagePower(forChannel: 0)
                let normalized = max(0, min(1, (power + 50) / 50))
                self.level = normalized
                if let startedAt = self.startedAt {
                    self.elapsed = Date.now.timeIntervalSince(startedAt)
                }
            }
        }
    }
}

enum RecorderError: LocalizedError {
    case failedToStart

    var errorDescription: String? {
        "Could not start recording. Check microphone permission."
    }
}

extension TimeInterval {
    var clockString: String {
        let total = Int(self)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
