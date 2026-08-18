import Foundation
import Security

enum KeychainStore {
    private static let service = "com.Ayouni.ProjectMan"

    enum Key: String {
        case anthropic = "anthropicAPIKey"
        case deepgram = "deepgramAPIKey"
    }

    static func set(_ value: String, for key: Key) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue
        ]
        SecItemDelete(query as CFDictionary)
        guard !value.isEmpty else { return }
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
    }

    static func get(_ key: Key) -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }
}

@Observable
final class AppSettings {
    var anthropicAPIKey: String {
        didSet { KeychainStore.set(anthropicAPIKey, for: .anthropic) }
    }

    var deepgramAPIKey: String {
        didSet { KeychainStore.set(deepgramAPIKey, for: .deepgram) }
    }

    var hasCompletedOnboarding: Bool {
        didSet { UserDefaults.standard.set(hasCompletedOnboarding, forKey: "hasCompletedOnboarding") }
    }

    var claudeModel: String {
        didSet { UserDefaults.standard.set(claudeModel, forKey: "claudeModel") }
    }

    var preferOnDeviceSpeech: Bool {
        didSet { UserDefaults.standard.set(preferOnDeviceSpeech, forKey: "preferOnDeviceSpeech") }
    }

    var useDeepgramWhenAvailable: Bool {
        didSet { UserDefaults.standard.set(useDeepgramWhenAvailable, forKey: "useDeepgramWhenAvailable") }
    }

    init() {
        anthropicAPIKey = KeychainStore.get(.anthropic)
        deepgramAPIKey = KeychainStore.get(.deepgram)
        hasCompletedOnboarding = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
        claudeModel = UserDefaults.standard.string(forKey: "claudeModel") ?? "claude-sonnet-4-5"
        preferOnDeviceSpeech = UserDefaults.standard.object(forKey: "preferOnDeviceSpeech") as? Bool ?? true
        useDeepgramWhenAvailable = UserDefaults.standard.object(forKey: "useDeepgramWhenAvailable") as? Bool ?? true
    }

    var hasAnthropicKey: Bool { !anthropicAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}

enum AssetStore {
    static var capturesRoot: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url = docs.appendingPathComponent("Captures", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func folder(for captureID: UUID) -> URL {
        let url = capturesRoot.appendingPathComponent(captureID.uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func copy(_ source: URL, into captureID: UUID, named name: String) throws -> String {
        let dest = folder(for: captureID).appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: dest.path) {
            try FileManager.default.removeItem(at: dest)
        }
        let accessed = source.startAccessingSecurityScopedResource()
        defer { if accessed { source.stopAccessingSecurityScopedResource() } }
        try FileManager.default.copyItem(at: source, to: dest)
        return dest.path
    }

    static func write(_ data: Data, into captureID: UUID, named name: String) throws -> String {
        let dest = folder(for: captureID).appendingPathComponent(name)
        try data.write(to: dest, options: .atomic)
        return dest.path
    }

    static func fileURL(_ path: String) -> URL {
        URL(fileURLWithPath: path)
    }
}
