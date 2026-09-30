import XCTest

final class PickerDemoUITests: XCTestCase {
    func testPickerSearchPaginationSelectionRetryAndTheme() throws {
        let app = XCUIApplication(); app.launchArguments = ["--fixtures"]; app.launch()
        let first = app.buttons["gifsnap.item.-1-0"]
        XCTAssertTrue(first.waitForExistence(timeout: 10))
        first.tap(); XCTAssertTrue(app.staticTexts["demo.selection"].waitForExistence(timeout: 2))
        app.buttons["gifsnap.loadMore"].tap()
        XCTAssertTrue(app.buttons["gifsnap.item.-2-0"].waitForExistence(timeout: 5))
        app.buttons["demo.theme"].tap()
        let dark = XCTAttachment(screenshot: app.screenshot()); dark.name = "Picker dark"; dark.lifetime = .keepAlways; add(dark)
        app.buttons["demo.theme"].tap()
        let light = XCTAttachment(screenshot: app.screenshot()); light.name = "Picker light"; light.lifetime = .keepAlways; add(light)
        let search = app.textFields["gifsnap.search"]
        search.tap(); search.typeText("retry")
        XCTAssertTrue(app.buttons["gifsnap.retry"].waitForExistence(timeout: 5))
        app.buttons["gifsnap.retry"].tap()
        XCTAssertTrue(app.buttons["gifsnap.item.retry-1-0"].waitForExistence(timeout: 5))
        app.buttons["Clear search"].tap()
        search.tap(); search.typeText("empty")
        XCTAssertTrue(app.staticTexts["No results. Try another search."].waitForExistence(timeout: 5))
    }
}
