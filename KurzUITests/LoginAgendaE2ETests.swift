import XCTest

final class LoginE2ETests: XCTestCase {
    static let email = "dev.kurz@gmail.com"

    @MainActor func launch(fresh: Bool = true) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["KURZ_API_URL"] = ProcessInfo.processInfo.environment["KURZ_API_URL"] ?? "http://localhost:3000"
        if fresh { app.launchEnvironment["KURZ_FRESH_INSTALL"] = "1" }
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

    @MainActor func testSignInShowsTheSignedInScreenAndSignOutReturns() {
        let app = launch()
        signIn(app)
        XCTAssertTrue(app.staticTexts["signed-in-label"].waitForExistence(timeout: 10))
        app.buttons["sign-out-button"].tap()
        XCTAssertTrue(app.textFields["email-field"].waitForExistence(timeout: 10))
    }

    @MainActor func testWrongCodeShowsAnErrorAndStaysOnTheCodeStep() {
        let app = launch()
        signIn(app, code: "1111111")
        XCTAssertTrue(app.staticTexts["login-error"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.textFields["code-field"].exists)
    }
}
