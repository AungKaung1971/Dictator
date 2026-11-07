import AppKit
import SwiftUI
import Security
import DictatorCore

final class Settings: ObservableObject {
    @Published var shortcut: Shortcut { didSet { save(shortcut.rawValue, "shortcut") } }
    @Published var microphone: String { didSet { save(microphone, "microphone") } }
    @Published var cleanup: Bool { didSet { save(cleanup, "cleanup") } }
    @Published var britishEnglish: Bool { didSet { save(britishEnglish, "britishEnglish") } }
    @Published var vocabulary: String { didSet { save(vocabulary, "vocabulary") } }
    @Published var correctionModel: String { didSet { save(correctionModel, "correctionModel") } }
    private let defaults = UserDefaults.standard
    init() {
        defaults.register(defaults: ["cleanup": true, "britishEnglish": true])
        shortcut = Shortcut(rawValue: defaults.string(forKey: "shortcut") ?? "") ?? .fn
        microphone = defaults.string(forKey: "microphone") ?? ""
        cleanup = defaults.bool(forKey: "cleanup")
        britishEnglish = defaults.bool(forKey: "britishEnglish")
        vocabulary = defaults.string(forKey: "vocabulary") ?? ""
        correctionModel = defaults.string(forKey: "correctionModel") ?? "gpt-4.1-mini"
    }
    private func save(_ value: Any, _ key: String) { defaults.set(value, forKey: key) }
    var ai: AIOptions {
        var options = AIOptions()
        options.cleanup = cleanup; options.britishEnglish = britishEnglish
        options.vocabulary = vocabulary; options.correctionModel = correctionModel
        return options
    }
}

enum Keychain {
    private static let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "local.dictator.api",
        kSecAttrAccount as String: "openai"
    ]
    static func read() throws -> String? {
        var q = query
        q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else { throw DictationError.message("Cannot read the API key from Keychain (\(status)).") }
        return String(data: data, encoding: .utf8)
    }
    static func save(_ key: String) throws {
        let attributes: [String: Any] = [kSecValueData as String: Data(key.utf8), kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw DictationError.message("Cannot save the API key in Keychain (\(status)).") }
    }
    static func delete() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw DictationError.message("Cannot remove the API key (\(status)).") }
    }
}
