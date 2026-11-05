import Foundation

/// Brings settings and calibrations across, once, from when the app had a different bundle identifier.
/// The old preferences are left in place, and nothing already set under the new identifier is overwritten.
enum PreferencesMigration {
    static let oldDomain = "com.arruler.app"
    static let doneDefaultsKey = "ARRuler_ImportedFromOldBundleID"
    private static let ownKeyPrefix = "ARRuler_"

    static func run(from old: UserDefaults? = UserDefaults(suiteName: oldDomain), to defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: doneDefaultsKey) else { return }
        // Only the app's own keys, because a suite's dictionary also includes system-wide values.
        for (key, value) in old?.dictionaryRepresentation() ?? [:]
        where key.hasPrefix(ownKeyPrefix) && defaults.object(forKey: key) == nil {
            defaults.set(value, forKey: key)
        }
        defaults.set(true, forKey: doneDefaultsKey)
    }
}
