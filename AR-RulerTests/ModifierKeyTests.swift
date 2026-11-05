import AppKit
import XCTest

final class ModifierKeyTests: XCTestCase {
    func testControlOptionNeedsBothKeys() {
        let key = ModifierKey.controlOption
        XCTAssertTrue(key.isHeld(in: [.control, .option]))
        XCTAssertFalse(key.isHeld(in: .control), "Control-click has to stay right-click")
        XCTAssertFalse(key.isHeld(in: .option))
        XCTAssertFalse(key.isHeld(in: []))
        XCTAssertFalse(key.isHeld(in: [.control, .shift]))
        XCTAssertFalse(key.isHeld(in: [.option, .shift]))
    }

    func testShiftForSnappingWorksOnTop() {
        XCTAssertTrue(ModifierKey.controlOption.isHeld(in: [.control, .option, .shift]))
        XCTAssertTrue(ModifierKey.option.isHeld(in: [.option, .shift]))
    }

    func testBitsOutsideTheModifierKeysDoNotMatter() {
        XCTAssertTrue(ModifierKey.controlOption.isHeld(in: [.control, .option, .capsLock, .numericPad]))
        var flags = NSEvent.ModifierFlags(rawValue: 0x100) // a device-dependent bit, as real events carry
        XCTAssertFalse(ModifierKey.controlOption.isHeld(in: flags))
        flags.formUnion([.control, .option])
        XCTAssertTrue(ModifierKey.controlOption.isHeld(in: flags))
    }

    func testSingleKeysStillWork() {
        XCTAssertTrue(ModifierKey.option.isHeld(in: .option))
        XCTAssertTrue(ModifierKey.control.isHeld(in: .control))
        XCTAssertTrue(ModifierKey.command.isHeld(in: .command))
        XCTAssertFalse(ModifierKey.command.isHeld(in: .option))
    }

    func testDefaultAndChoices() {
        XCTAssertEqual(ModifierKey.defaultKey, .controlOption)
        XCTAssertEqual(ModifierKey.allCases.map(\.rawValue), ["Control + Option", "Option", "Control", "Command"])
    }
}

final class ModifierKeyMigrationTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suite = "ARRulerTests.modifierMigration"
    private var stored: String? { defaults.string(forKey: ModifierKeyMigration.modifierDefaultsKey) }

    override func setUp() {
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
    }

    private func store(_ key: ModifierKey) {
        defaults.set(key.rawValue, forKey: ModifierKeyMigration.modifierDefaultsKey)
    }

    func testStoredControlMoves() {
        store(.control)
        ModifierKeyMigration.run(defaults: defaults)
        XCTAssertEqual(stored, "Control + Option")
    }

    func testLaterDeliberateControlStays() {
        store(.control)
        ModifierKeyMigration.run(defaults: defaults)
        store(.control)
        ModifierKeyMigration.run(defaults: defaults)
        XCTAssertEqual(stored, "Control")
    }

    func testOtherChoicesAreLeftAlone() {
        for key in [ModifierKey.option, .command, .controlOption] {
            defaults.removePersistentDomain(forName: suite)
            store(key)
            ModifierKeyMigration.run(defaults: defaults)
            XCTAssertEqual(stored, key.rawValue)
        }
    }

    func testControlChosenAfterMigratingFromOptionStays() {
        store(.option)
        ModifierKeyMigration.run(defaults: defaults)
        store(.control)
        ModifierKeyMigration.run(defaults: defaults)
        XCTAssertEqual(stored, "Control")
    }

    func testFreshInstallStoresNothingAndGetsTheDefault() {
        ModifierKeyMigration.run(defaults: defaults)
        XCTAssertNil(stored)
        store(.control)
        ModifierKeyMigration.run(defaults: defaults)
        XCTAssertEqual(stored, "Control", "a fresh install choosing Control later keeps it")
    }
}
