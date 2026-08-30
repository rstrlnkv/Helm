import XCTest
import HelmTestSupport
@testable import Module_Layout_Engine

/// **The row said «1 app» and the window it opened held eight.**
///
/// The lists window draws the person's own rules *plus* the built-in refusals
/// this Mac has — terminals and password managers, shown as ordinary rows so
/// the refusal is visible and can be overruled. The page counted the rules
/// table alone, so the row read «No apps» over a list of seven, and gained one
/// each time a rule was added while the list gained one too from a different
/// starting number.
///
/// The page's own doc comment states the rule that broke: «Each row carries its
/// own count, which is the one thing a list behind a button owes.»
///
/// One expression now answers both, and this holds it. The second test is the
/// part that matters: not that the arithmetic is right, but that the two
/// screens are reading the same function.
final class TheCountOnTheRowIsTheCountInTheWindowTests: XCTestCase {

    private let builtIn = ["com.apple.Terminal", "com.googlecode.iterm2"]

    func testTheBuiltInRefusalsAreCountedBecauseTheyAreDrawn() {
        XCTAssertEqual(AppScope.listed(rules: [:], builtIn: builtIn).count, 2)
    }

    func testARuleOnABuiltInAppIsOneRowNotTwo() {
        let listed = AppScope.listed(rules: ["com.apple.Terminal": true], builtIn: builtIn)
        XCTAssertEqual(listed.count, 2)
        XCTAssertTrue(listed.contains("com.apple.Terminal"))
    }

    func testARuleOnSomethingElseAddsARow() {
        XCTAssertEqual(AppScope.listed(rules: ["com.tinyspeck.slackmacgap": false],
                                       builtIn: builtIn).count, 3)
    }

    /// Only what this Mac has: `builtIn` arrives already filtered by the caller,
    /// because a row for software nobody installed is a list of somebody else's
    /// machine.
    func testNothingIsInventedFromTheDefaultList() {
        XCTAssertEqual(AppScope.listed(rules: [:], builtIn: []).count, 0)
    }

    /// **Both screens ask the one function.** A count and a list that agree by
    /// arithmetic today can disagree tomorrow; they cannot if they are the same
    /// call. Read from source because the page's count is a `@State` seeded in
    /// an `init` no test can reach.
    func testThePageAndTheWindowBothCallIt() throws {
        for file in ["Sources/Modules/Layout/UI/LayoutSettingsPage.swift",
                     "Sources/Modules/Layout/UI/LayoutLists.swift"] {
            let text = SwiftSource.uncommented(
                try String(contentsOf: RepoSource.root.appendingPathComponent(file),
                           encoding: .utf8))
            XCTAssertTrue(text.contains("AppScope.listed("),
                          "\(file) no longer asks `AppScope.listed` — the row's count and the "
                          + "window's rows are two expressions again")
            XCTAssertFalse(text.contains(".union(builtInBlocked)"),
                           "\(file) has grown its own copy of the union back")
        }
    }
}
