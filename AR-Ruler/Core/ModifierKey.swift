import AppKit

/// The key or keys held to measure. Raw values are what's stored in preferences and shown in Preferences.
enum ModifierKey: String, CaseIterable {
    case controlOption = "Control + Option"
    case option = "Option"
    case control = "Control"
    case command = "Command"

    static let defaultKey = ModifierKey.controlOption

    var flags: NSEvent.ModifierFlags {
        switch self {
        case .controlOption: return [.control, .option]
        case .option: return .option
        case .control: return .control
        case .command: return .command
        }
    }

    /// True only when every key in the set is down. Other keys, such as Shift for snapping, may be down too.
    func isHeld(in modifierFlags: NSEvent.ModifierFlags) -> Bool {
        modifierFlags.intersection(.deviceIndependentFlagsMask).isSuperset(of: flags)
    }
}

/// Moves a stored Control setting to Control + Option, once. Control-click is the Mac's right-click, so holding
/// Control alone made the overlay swallow context-menu clicks.
enum ModifierKeyMigration {
    static let modifierDefaultsKey = "ARRuler_ModifierKey"
    static let doneDefaultsKey = "ARRuler_MigratedControlToControlOption"

    static func run(defaults: UserDefaults = .standard) {
        // The marker is what lets a later deliberate choice of Control stay.
        guard !defaults.bool(forKey: doneDefaultsKey) else { return }
        if defaults.string(forKey: modifierDefaultsKey) == ModifierKey.control.rawValue {
            defaults.set(ModifierKey.controlOption.rawValue, forKey: modifierDefaultsKey)
        }
        defaults.set(true, forKey: doneDefaultsKey)
    }
}
