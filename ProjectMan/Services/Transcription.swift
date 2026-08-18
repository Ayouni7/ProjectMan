import Foundation
import Speech

enum TranscriptionService {
    static func transcribe(
        audioURL: URL,
        settings: AppSettings
    ) async throws -> (text: String, speakers: [ExtractedSpeaker]) {
        if settings.useDeepgramWhenAvailable, !settings.deepgramAPIKey.isEmpty {
            return try await DeepgramService.transcribe(audioURL: audioURL, apiKey: settings.deepgramAPIKey)
        }
        let text = try await AppleSpeech.transcribe(url: audioURL, preferOnDevice: settings.preferOnDeviceSpeech)
        return (text, [])
    }
}

enum AppleSpeech {
    static func transcribe(url: URL, preferOnDevice: Bool) async throws -> String {
        let locale = Locale.current
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
            throw TranscriptionError.unavailable
        }

        let status = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard status == .authorized else { throw TranscriptionError.notAuthorized }

        return try await withCheckedThrowingContinuation { continuation in
            let request = SFSpeechURLRecognitionRequest(url: url)
            request.shouldReportPartialResults = false
            if preferOnDevice, recognizer.supportsOnDeviceRecognition {
                request.requiresOnDeviceRecognition = true
            }

            var finished = false
            recognizer.recognitionTask(with: request) { result, error in
                if let error {
                    if !finished {
                        finished = true
                        continuation.resume(throwing: error)
                    }
                    return
                }
                guard let result, result.isFinal else { return }
                if !finished {
                    finished = true
                    continuation.resume(returning: result.bestTranscription.formattedString)
                }
            }
        }
    }
}

enum DeepgramService {
    static func transcribe(audioURL: URL, apiKey: String) async throws -> (text: String, speakers: [ExtractedSpeaker]) {
        var components = URLComponents(string: "https://api.deepgram.com/v1/listen")!
        components.queryItems = [
            URLQueryItem(name: "model", value: "nova-2"),
            URLQueryItem(name: "smart_format", value: "true"),
            URLQueryItem(name: "diarize", value: "true"),
            URLQueryItem(name: "punctuate", value: "true")
        ]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.setValue("Token \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("audio/mp4", forHTTPHeaderField: "Content-Type")
        request.httpBody = try Data(contentsOf: audioURL)
        request.timeoutInterval = 300

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw TranscriptionError.provider("Deepgram failed: \(body)")
        }

        let decoded = try JSONDecoder().decode(DeepgramResponse.self, from: data)
        let alt = decoded.results.channels.first?.alternatives.first
        let transcript = alt?.transcript ?? ""
        var labels: [Int: String] = [:]
        for word in alt?.words ?? [] {
            if let speaker = word.speaker {
                labels[speaker] = "Speaker \(speaker + 1)"
            }
        }
        let speakers = labels.keys.sorted().compactMap { labels[$0] }.map { ExtractedSpeaker(label: $0, suggestedName: nil) }

        var diarized = transcript
        if let words = alt?.words, words.contains(where: { $0.speaker != nil }) {
            var lines: [String] = []
            var currentSpeaker: Int?
            var buffer: [String] = []
            func flush() {
                guard let currentSpeaker, !buffer.isEmpty else { return }
                lines.append("Speaker \(currentSpeaker + 1): \(buffer.joined(separator: " "))")
                buffer = []
            }
            for word in words {
                if word.speaker != currentSpeaker {
                    flush()
                    currentSpeaker = word.speaker
                }
                buffer.append(word.punctuatedWord ?? word.word)
            }
            flush()
            if !lines.isEmpty { diarized = lines.joined(separator: "\n") }
        }

        return (diarized, speakers)
    }
}

private struct DeepgramResponse: Decodable {
    var results: Results
    struct Results: Decodable {
        var channels: [Channel]
    }
    struct Channel: Decodable {
        var alternatives: [Alternative]
    }
    struct Alternative: Decodable {
        var transcript: String?
        var words: [Word]?
    }
    struct Word: Decodable {
        var word: String
        var speaker: Int?
        var punctuatedWord: String?

        enum CodingKeys: String, CodingKey {
            case word, speaker
            case punctuatedWord = "punctuated_word"
        }
    }
}

enum TranscriptionError: LocalizedError {
    case unavailable
    case notAuthorized
    case provider(String)

    var errorDescription: String? {
        switch self {
        case .unavailable: "Speech recognition is not available on this device."
        case .notAuthorized: "Speech recognition permission was denied."
        case .provider(let message): message
        }
    }
}
