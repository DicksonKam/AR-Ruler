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
                .help("Hold this key and click to add measurement points")
            }

            Section {
                Text("Tip: Press Esc to clear current measurement. Right-click to reset.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .frame(width: 400, height: 200)
    }
}
