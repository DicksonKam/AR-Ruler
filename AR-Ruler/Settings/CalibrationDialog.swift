import AppKit

/// The dialogs behind the menu's calibration items.
enum CalibrationDialog {
    /// Asks for the true length of what the ruler spans. Returns true if a calibration was saved.
    static func run(for screen: NSScreen, rulerLengthPoints: CGFloat?) -> Bool {
        NSApp.activate(ignoringOtherApps: true)
        guard let rulerLengthPoints else {
            showInstructions()
            return false
        }

        let manager = CalibrationManager.shared
        let unit: RulerUnit = AppSettings.shared.unit == .inch ? .inch : .cm
        let scale = RulerScale(unit: unit, pointsPerCm: manager.pointsPerCm(for: screen))

        let field = NSTextField(frame: NSRect(x: 0, y: 2, width: 110, height: 24))
        field.placeholderString = "True length"
        let popup = NSPopUpButton(frame: NSRect(x: 118, y: 0, width: 110, height: 28))
        popup.addItems(withTitles: RulerUnit.allCases.map(\.symbol))
        popup.selectItem(withTitle: unit.symbol)
        let accessory = NSView(frame: NSRect(x: 0, y: 0, width: 230, height: 28))
        accessory.addSubview(field)
        accessory.addSubview(popup)

        let alert = NSAlert()
        alert.messageText = "Calibrate \(screen.localizedName)"
        alert.informativeText = """
            The ruler's two end points are \(ReadingFormat.reading(rulerLengthPoints, scale: scale)) apart at the current scale. \
            If they mark the two ends of a real object held against the screen, enter that object's true length.
            """
        alert.accessoryView = accessory
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field

        guard alert.runModal() == .alertFirstButtonReturn else { return false }

        let chosenUnit = RulerUnit.allCases[popup.indexOfSelectedItem]
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        let entered = formatter.number(from: field.stringValue)?.doubleValue ?? Double(field.stringValue) ?? 0
        let saved = manager.calibrate(
            screen,
            rulerLengthPoints: rulerLengthPoints,
            trueLengthCm: CGFloat(entered) * chosenUnit.cmPerUnit
        )
        if !saved {
            let problem = NSAlert()
            problem.messageText = "That length doesn't look right"
            problem.informativeText = "It would imply a scale no display has, so the calibration wasn't changed. Check the number and its unit, then try again."
            problem.runModal()
        }
        return saved
    }

    private static func showInstructions() {
        let alert = NSAlert()
        alert.messageText = "Measure something first"
        let key = AppSettings.shared.modifierKey.rawValue
        alert.informativeText = """
            Hold a real object of known length against the screen, such as a bank card (8.56 cm wide). \
            Hold \(key) and click its two ends to lay the ruler across it, then choose Calibrate again.
            """
        alert.runModal()
    }
}
