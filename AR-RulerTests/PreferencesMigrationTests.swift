import XCTest

final class PreferencesMigrationTests: XCTestCase {
    private let oldSuite = "ARRulerTests.oldPreferences"
    private let newSuite = "ARRulerTests.newPreferences"
    private var old: UserDefaults!
    private var new: UserDefaults!

    override func setUp() {
        old = UserDefaults(suiteName: oldSuite)
        new = UserDefaults(suiteName: newSuite)
        old.removePersistentDomain(forName: oldSuite)
        new.removePersistentDomain(forName: newSuite)
    }

    override func tearDown() {
        old.removePersistentDomain(forName: oldSuite)
        new.removePersistentDomain(forName: newSuite)
    }

    func testCopiesSettingsAndCalibrations() {
        let calibrations = Data([1, 2, 3])
        old.set("Centimeters", forKey: "ARRuler_Unit")
        old.set("Option", forKey: "ARRuler_ModifierKey")
        old.set(calibrations, forKey: "ARRuler_DisplayCalibrations")
        old.set(true, forKey: "ARRuler_MigratedControlToControlOption")
        PreferencesMigration.run(from: old, to: new)
        XCTAssertEqual(new.string(forKey: "ARRuler_Unit"), "Centimeters")
        XCTAssertEqual(new.string(forKey: "ARRuler_ModifierKey"), "Option")
        XCTAssertEqual(new.data(forKey: "ARRuler_DisplayCalibrations"), calibrations)
        XCTAssertTrue(new.bool(forKey: "ARRuler_MigratedControlToControlOption"))
    }

    func testIgnoresOtherKeysAndLeavesTheOldValues() {
        old.set("760 407", forKey: "NSWindow Frame somewhere")
        old.set("Option", forKey: "ARRuler_ModifierKey")
        PreferencesMigration.run(from: old, to: new)
        XCTAssertNil(new.object(forKey: "NSWindow Frame somewhere"))
        XCTAssertEqual(old.string(forKey: "ARRuler_ModifierKey"), "Option")
    }

    func testDoesNotOverwriteWhatIsAlreadySet() {
        old.set("Option", forKey: "ARRuler_ModifierKey")
        new.set("Command", forKey: "ARRuler_ModifierKey")
        PreferencesMigration.run(from: old, to: new)
        XCTAssertEqual(new.string(forKey: "ARRuler_ModifierKey"), "Command")
    }

    func testRunsOnlyOnce() {
        old.set("Option", forKey: "ARRuler_ModifierKey")
        PreferencesMigration.run(from: old, to: new)
        new.removeObject(forKey: "ARRuler_ModifierKey")
        PreferencesMigration.run(from: old, to: new)
        XCTAssertNil(new.object(forKey: "ARRuler_ModifierKey"), "a later change isn't undone")
    }

    func testFreshInstallWithNothingToImport() {
        PreferencesMigration.run(from: old, to: new)
        XCTAssertTrue(new.bool(forKey: PreferencesMigration.doneDefaultsKey))
        PreferencesMigration.run(from: nil, to: new)
    }

    func testImportedControlStillMovesToControlOption() {
        old.set("Control", forKey: ModifierKeyMigration.modifierDefaultsKey)
        PreferencesMigration.run(from: old, to: new)
        ModifierKeyMigration.run(defaults: new)
        XCTAssertEqual(new.string(forKey: ModifierKeyMigration.modifierDefaultsKey), "Control + Option")
    }
}
