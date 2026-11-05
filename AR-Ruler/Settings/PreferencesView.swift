import SwiftUI

struct PreferencesView: View {
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        Form {
            Section("Measurement") {
                Picker("Unit", selection: $settings.unit) {
                    ForEach(MeasurementUnit.allCases, id: \.self) { unit in
                        Text(unit.rawValue).tag(unit)
                    }
                }
            }

            Section("Interaction") {
                Picker("Hold to measure", selection: $settings.modifierKey) {
                    ForEach(ModifierKey.allCases, id: \.self) { key in
                        Text(key.rawValue).tag(key)
                    }
                }
                .help("Hold this key and click to lay the ruler, pin readings and add angle points")
            }

            Section {
                Text("Tip: Press Esc to clear the measurement, or hold the key above and right-click.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Can't see the ruler icon in the menu bar? Open AR Ruler again from Applications or Spotlight to get back here.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420, height: 330)
    }
}
