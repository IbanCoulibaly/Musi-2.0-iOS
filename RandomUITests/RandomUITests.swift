//
//  RandomUITests.swift
//  RandomUITests
//
//  Created by IBAN COULIBALY on 2/8/25.
//

import XCTest

final class RandomUITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func testExample() throws {
        // UI tests must launch the application that they test.
        let app = XCUIApplication()
        app.launch()

        // Use XCTAssert and related functions to verify your tests produce the correct results.
    }

    @MainActor
    func testSearchTabReturnsToLibraryAndFocusesSearchField() throws {
        let app = XCUIApplication()
        app.launch()

        let youtubeTab = app.tabBars.buttons["YouTube"]
        XCTAssertTrue(youtubeTab.waitForExistence(timeout: 5))
        youtubeTab.tap()

        let searchTab = app.tabBars.buttons["Search"]
        XCTAssertTrue(searchTab.waitForExistence(timeout: 2))
        searchTab.tap()

        XCTAssertTrue(app.navigationBars["Library"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.textFields["librarySearchField"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
    }

    @MainActor
    func testLibrarySearchFieldFocusesWhenTappedDirectly() throws {
        let app = XCUIApplication()
        app.launch()

        let librarySearchField = app.textFields["librarySearchField"]
        XCTAssertTrue(librarySearchField.waitForExistence(timeout: 5))
        librarySearchField.tap()

        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
    }

    @MainActor
    func testLibrarySearchIconFocusesFieldAndOpensKeyboard() throws {
        let app = XCUIApplication()
        app.launch()

        let searchIcon = app.buttons["Focus Library Search"]
        XCTAssertTrue(searchIcon.waitForExistence(timeout: 5))
        searchIcon.tap()

        XCTAssertTrue(app.textFields["librarySearchField"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
    }

    @MainActor
    func testLaunchPerformance() throws {
        if #available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 7.0, *) {
            // This measures how long it takes to launch your application.
            measure(metrics: [XCTApplicationLaunchMetric()]) {
                XCUIApplication().launch()
            }
        }
    }
}
