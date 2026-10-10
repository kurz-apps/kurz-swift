import XCTest

final class LoginE2ETests: XCTestCase {
    static let email = "dev.kurz@gmail.com"

    @MainActor func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["KURZ_API_URL"] = ProcessInfo.processInfo.environment["KURZ_API_URL"] ?? "http://localhost:3000"
        app.launchEnvironment["KURZ_FRESH_INSTALL"] = "1"
        app.launch()
        return app
    }

    @MainActor func signIn(_ app: XCUIApplication, code: String = "0000000") {
        let email = app.textFields["email-field"]
        XCTAssertTrue(email.waitForExistence(timeout: 10))
        email.tap()
        email.typeText(Self.email)
        app.buttons["send-code-button"].tap()
        let field = app.textFields["code-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.typeText(code)
    }

    @MainActor func testSignInShowsTheAgendaAndSignOutReturns() {
        let app = launch()
        signIn(app)
        XCTAssertTrue(app.navigationBars["Agenda"].waitForExistence(timeout: 10))
        app.buttons["account-menu"].tap()
        app.buttons["sign-out-button"].tap()
        XCTAssertTrue(app.textFields["email-field"].waitForExistence(timeout: 10))
    }

    @MainActor func testPasswordSignInShowsTheAgenda() {
        let app = launch()
        let email = app.textFields["email-field"]
        XCTAssertTrue(email.waitForExistence(timeout: 10))
        email.tap()
        email.typeText(Self.email)
        let password = app.secureTextFields["password-field"]
        password.tap()
        password.typeText("e2e-Password-123")
        app.buttons["login-button"].tap()
        XCTAssertTrue(app.navigationBars["Agenda"].waitForExistence(timeout: 10))
    }

    @MainActor func testWrongPasswordShowsAnError() {
        let app = launch()
        let email = app.textFields["email-field"]
        XCTAssertTrue(email.waitForExistence(timeout: 10))
        email.tap()
        email.typeText(Self.email)
        let password = app.secureTextFields["password-field"]
        password.tap()
        password.typeText("wrong-password")
        app.buttons["login-button"].tap()
        XCTAssertTrue(app.staticTexts["login-error"].waitForExistence(timeout: 10))
    }

    @MainActor func testWrongCodeShowsAnErrorAndStaysOnTheCodeStep() {
        let app = launch()
        signIn(app, code: "1111111")
        XCTAssertTrue(app.staticTexts["login-error"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.textFields["code-field"].exists)
    }

    @MainActor func testAgendaListsTheSeededBookings() {
        let app = launch()
        signIn(app)
        XCTAssertTrue(app.staticTexts["Tomorrow"].waitForExistence(timeout: 15) || app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Tomorrow'")).firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Ana Silva'")).firstMatch.exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Bruno Costa'")).firstMatch.exists)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.lifetime = .keepAlways
        add(shot)
    }
}
