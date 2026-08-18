import Foundation
import UIKit

enum ClaudeService {
    static func extract(
        capture: CaptureItem,
        projects: [Project],
        people: [String],
        settings: AppSettings
    ) async throws -> ExtractionResult {
        let key = settings.anthropicAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw ClaudeError.missingKey }

        let catalog = projects
            .filter { $0.status == .active }
            .map { project in
                let recent = project.captures
                    .sorted { $0.createdAt > $1.createdAt }
                    .prefix(3)
                    .map(\.summary)
                    .filter { !$0.isEmpty }
                    .joined(separator: " | ")
                return "- \(project.title): \(project.details) \(recent)"
            }
            .joined(separator: "\n")

        let peopleLine = people.isEmpty ? "None yet." : people.joined(separator: ", ")
        let userBlocks = try contentBlocks(for: capture)

        let prompt = """
        You extract structured project data from a capture (meeting, notes photo, or document).

        Existing projects:
        \(catalog.isEmpty ? "None yet." : catalog)

        Known people (reuse these names when you recognize them):
        \(peopleLine)

        Return JSON only, no markdown, matching this schema:
        {
          "summary": "2-4 sentences",
          "decisions": ["explicit choices made"],
          "action_items": [
            {
              "description": "concrete next action",
              "owner": "name or null",
              "due_date": "YYYY-MM-DD or null",
              "quote": "short source phrase"
            }
          ],
          "project_suggestion": {
            "title": "best project title",
            "is_new": true,
            "matched_project_title": "exact existing title or null",
            "confidence": 0.0,
            "rationale": "why",
            "alternate_titles": ["other plausible existing titles"]
          },
          "entities": {
            "people": [],
            "dates": [],
            "references": []
          },
          "speakers": [
            { "label": "Speaker 1", "suggested_name": null }
          ]
        }

        Rules:
        - Prefer matching an existing project when evidence is reasonably strong.
        - Confidence is 0-1. Use >= 0.75 only when the match is clear.
        - Action items must be specific and trackable. Skip vague notes.
        - If a due date is not stated, use null.
        - If this is a transcript with Speaker N labels, keep those labels and suggest real names when obvious.
        """

        var content: [[String: Any]] = [["type": "text", "text": prompt]]
        content.append(contentsOf: userBlocks)

        let body: [String: Any] = [
            "model": settings.claudeModel,
            "max_tokens": 4096,
            "messages": [
                ["role": "user", "content": content]
            ]
        ]

        let data = try await post(body: body, apiKey: key)
        let text = try messageText(from: data)
        return try decodeExtraction(text)
    }

    static func narrative(
        window: TimeWindow,
        scopeTitle: String,
        snapshot: ProgressSnapshot,
        highlights: [String],
        settings: AppSettings
    ) async throws -> String {
        let key = settings.anthropicAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw ClaudeError.missingKey }

        let trend: String
        if let previous = snapshot.previousCompletionRate {
            let delta = snapshot.completionRate - previous
            trend = "Completion rate \(snapshot.completionRate.percentLabel) vs previous \(previous.percentLabel) (delta \(Int((delta * 100).rounded())) pp)."
        } else {
            trend = "Completion rate \(snapshot.completionRate.percentLabel)."
        }

        let projectLines = snapshot.perProject.map {
            "- \($0.title): completed \($0.completed), created \($0.created), still open \($0.open) (\($0.completionRate.percentLabel))"
        }.joined(separator: "\n")

        let prompt = """
        Write a concise progress narrative for \(scopeTitle) over this \(window.title.lowercased()).
        Use only the facts given. 2-4 sentences. No markdown, no greeting.

        Metrics: completed \(snapshot.completed), created \(snapshot.created), still open \(snapshot.stillOpen), newly blocked \(snapshot.newlyBlocked).
        \(trend)
        Per project:
        \(projectLines.isEmpty ? "None." : projectLines)

        Notable items:
        \(highlights.isEmpty ? "None listed." : highlights.joined(separator: "\n"))
        """

        let body: [String: Any] = [
            "model": settings.claudeModel,
            "max_tokens": 400,
            "messages": [
                ["role": "user", "content": [["type": "text", "text": prompt]]]
            ]
        ]
        let data = try await post(body: body, apiKey: key)
        return try messageText(from: data)
    }

    static func testConnection(apiKey: String, model: String) async throws {
        let body: [String: Any] = [
            "model": model,
            "max_tokens": 32,
            "messages": [
                ["role": "user", "content": "Reply with the single word ok."]
            ]
        ]
        _ = try await post(body: body, apiKey: apiKey)
    }

    private static func contentBlocks(for capture: CaptureItem) throws -> [[String: Any]] {
        var blocks: [[String: Any]] = []
        if !capture.transcript.isEmpty {
            blocks.append(["type": "text", "text": "Transcript:\n\(capture.transcript)"])
        }

        for path in capture.allAssetPaths {
            let url = AssetStore.fileURL(path)
            let ext = url.pathExtension.lowercased()
            if ext == "pdf" {
                let data = try Data(contentsOf: url)
                if data.count > 20_000_000 {
                    throw ClaudeError.tooLarge
                }
                blocks.append([
                    "type": "document",
                    "source": [
                        "type": "base64",
                        "media_type": "application/pdf",
                        "data": data.base64EncodedString()
                    ]
                ])
            } else if FileKind.isImage(url) {
                let data = try jpegData(from: url)
                blocks.append([
                    "type": "image",
                    "source": [
                        "type": "base64",
                        "media_type": "image/jpeg",
                        "data": data.base64EncodedString()
                    ]
                ])
            } else if ext == "docx" {
                let text = try DocumentTextExtractor.extractText(from: url)
                blocks.append(["type": "text", "text": "Word document text:\n\(text)"])
            }
        }

        if blocks.isEmpty {
            blocks.append(["type": "text", "text": "No extractable content was attached."])
        }
        return blocks
    }

    private static func jpegData(from url: URL) throws -> Data {
        let original = try Data(contentsOf: url)
        if let image = UIImage(data: original) {
            let resized = image.resized(maxDimension: 1600)
            if let jpeg = resized.jpegData(compressionQuality: 0.72) {
                return jpeg
            }
        }
        return original
    }

    private static func post(body: [String: Any], apiKey: String) async throws -> Data {
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 180
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ClaudeError.network }
        guard (200..<300).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw ClaudeError.api(message)
        }
        return data
    }

    private static func messageText(from data: Data) throws -> String {
        let decoded = try JSONDecoder().decode(AnthropicMessage.self, from: data)
        let text = decoded.content.compactMap { $0.text }.joined(separator: "\n")
        guard !text.isEmpty else { throw ClaudeError.empty }
        return text
    }

    private static func decodeExtraction(_ raw: String) throws -> ExtractionResult {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let json: String
        if let start = trimmed.firstIndex(of: "{"), let end = trimmed.lastIndex(of: "}") {
            json = String(trimmed[start...end])
        } else {
            json = trimmed
        }
        let decoder = JSONDecoder()
        do {
            return try decoder.decode(ExtractionResult.self, from: Data(json.utf8))
        } catch {
            throw ClaudeError.parse(json)
        }
    }
}

private struct AnthropicMessage: Decodable {
    var content: [Block]
    struct Block: Decodable {
        var type: String?
        var text: String?
    }
}

enum ClaudeError: LocalizedError {
    case missingKey
    case network
    case empty
    case tooLarge
    case api(String)
    case parse(String)

    var errorDescription: String? {
        switch self {
        case .missingKey:
            "Add your Anthropic API key in Settings before processing."
        case .network:
            "Could not reach Claude."
        case .empty:
            "Claude returned an empty response."
        case .tooLarge:
            "That PDF is too large to send. Try a smaller file."
        case .api(let message):
            "Claude error: \(message)"
        case .parse:
            "Could not parse Claude's extraction. Try processing again."
        }
    }
}

private extension UIImage {
    func resized(maxDimension: CGFloat) -> UIImage {
        let longest = max(size.width, size.height)
        guard longest > maxDimension else { return self }
        let scale = maxDimension / longest
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
