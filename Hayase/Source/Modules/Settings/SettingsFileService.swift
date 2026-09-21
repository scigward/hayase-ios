// Mirrors: src/routes/app/settings/app/+page.svelte (settings import/export)
import Foundation

enum SettingsFileService {
    static func exportData() throws -> Data {
        let values = savedPreferences()
        return try JSONSerialization.data(withJSONObject: values, options: [.prettyPrinted, .sortedKeys])
    }

    static func importData(_ data: Data) throws {
        guard let values = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              values.keys.allSatisfy(isSettingsKey),
              values.values.allSatisfy({ $0 is String || $0 is NSNumber }) else {
            throw ImportError.invalidFormat
        }
        savedPreferences().keys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
        values.forEach { Settings.write($0.value, forKey: $0.key) }
    }

    static func resetPreferences() {
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        UserDefaults.standard.removePersistentDomain(forName: bundleID)
        UserDefaults.standard.synchronize()
    }

    static func savedPreferences() -> [String: Any] {
        guard let bundleID = Bundle.main.bundleIdentifier else { return [:] }
        let domain = UserDefaults.standard.persistentDomain(forName: bundleID) ?? [:]
        return domain.filter { isSettingsKey($0.key) }
    }

    private static func isSettingsKey(_ key: String) -> Bool {
        key.hasPrefix("pref_") || key.hasPrefix("tracker_sync_")
    }

    enum ImportError: LocalizedError {
        case invalidFormat
        var errorDescription: String? { "The selected file is not a valid Hayase settings file." }
    }
}
