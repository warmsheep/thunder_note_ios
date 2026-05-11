import XCTest

final class ThunderNoteUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// 启动后应进入登录页（无登录态时），验证用户名输入框存在。
    @MainActor
    func test_launches_andShowsLoginScreen() {
        let app = XCUIApplication()
        app.launchArguments.append("-tn.uitests.cleanState")
        app.launch()
        let usernameField = app.textFields.matching(identifier: "loginUsernameField").firstMatch
        XCTAssertTrue(usernameField.waitForExistence(timeout: 5), "登录页用户名输入框应可见")
    }

    /// 服务器切换入口在登录页可见，且能进入服务器配置面板。
    @MainActor
    func test_login_showsServerSwitchEntry() {
        let app = XCUIApplication()
        app.launchArguments.append("-tn.uitests.cleanState")
        app.launch()
        let switchButton = app.buttons["loginSwitchServerButton"]
        XCTAssertTrue(switchButton.waitForExistence(timeout: 5))
        switchButton.tap()
        let currentLabel = app.staticTexts["serverConfigCurrentLabel"]
        XCTAssertTrue(currentLabel.waitForExistence(timeout: 3))
    }
}
