import AppKit
import SwiftUI

enum MeasurementUnit: String, CaseIterable {
    case cm = "Centimeters"
    case inch = "Inches"
}

enum ModifierKey: String, CaseIterable {
    case option = "Option"
    case control = "Control"
    case command = "Command"
}

class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @AppStorage("ARRuler_Unit") var unit: MeasurementUnit = .cm
    @AppStorage("ARRuler_ModifierKey") var modifierKey: ModifierKey = .option

    var modifierFlags: NSEvent.ModifierFlags {
        switch modifierKey {
        case .option: return .option
        case .control: return .control
        case .command: return .command
        }
    }
}
