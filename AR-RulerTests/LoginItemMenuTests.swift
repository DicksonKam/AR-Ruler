import XCTest

final class LoginItemMenuTests: XCTestCase {
    func testOffUntilTurnedOn() {
        let menu = LoginItemMenu(status: .notRegistered)
        XCTAssertEqual(menu.check, .off)
        XCTAssertEqual(menu.action, .register)
        XCTAssertEqual(menu.title, "Launch at Login")
    }

    func testOnTurnsOff() {
        let menu = LoginItemMenu(status: .enabled)
        XCTAssertEqual(menu.check, .on)
        XCTAssertEqual(menu.action, .unregister)
    }

    func testTurnedOffInSystemSettingsSendsYouThere() {
        let menu = LoginItemMenu(status: .requiresApproval)
        XCTAssertEqual(menu.check, .pending)
        XCTAssertEqual(menu.action, .openLoginItemsSettings)
        XCTAssertTrue(menu.title.contains("Settings"))
    }

    func testNotFoundStillTriesSoTheFailureIsVisible() {
        let menu = LoginItemMenu(status: .notFound)
        XCTAssertEqual(menu.check, .off)
        XCTAssertEqual(menu.action, .register)
    }
}
