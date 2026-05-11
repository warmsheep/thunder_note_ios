import XCTest

final class ThunderNoteUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func test_launches_andShowsBrandTitle() {
        let app = XCUIApplication()
        app.launch()
        let brandTitle = app.staticTexts["rootBrandTitle"]
        XCTAssertTrue(brandTitle.waitForExistence(timeout: 5))
        XCTAssertEqual(brandTitle.label, "闪记")
    }
}
