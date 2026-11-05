import AppKit
import SwiftUI

enum MeasurementUnit: String, CaseIterable {
    case cm = "Centimeters"
    case inch = "Inches"
}

class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @AppStorage("ARRuler_Unit") var unit: MeasurementUnit = .cm
    @AppStorage(ModifierKeyMigration.modifierDefaultsKey) var modifierKey: ModifierKey = ModifierKey.defaultKey

    init() {
        PreferencesMigration.run()
        ModifierKeyMigration.run()
    }
}
