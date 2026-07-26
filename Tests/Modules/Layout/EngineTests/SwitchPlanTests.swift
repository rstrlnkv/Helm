import XCTest
@testable import Module_Layout_Engine

/// The plan is counted in keystrokes an app will receive. One backspace too few
/// leaves debris; one too many eats the word before it.
final class SwitchPlanTests: XCTestCase {
    func testOneBackspacePerTypedCharacter() {
        let plan = SwitchPlan.make(replacing: "ghbdtn", with: "привет")
        XCTAssertEqual(plan?.backspaces, 6)
        XCTAssertEqual(plan?.insert, "привет")
    }

    /// Counted as the app sees them, not in bytes: "ё" is one press of delete
    /// whatever it is encoded as.
    func testMultiByteCharactersCountAsOne() {
        XCTAssertEqual(SwitchPlan.make(replacing: "£€ё", with: "abc")?.backspaces, 3)
    }

    /// A composed character is one grapheme, and one backspace removes it.
    func testComposedCharactersCountAsOne() {
        XCTAssertEqual(SwitchPlan.make(replacing: "e\u{0301}", with: "x")?.backspaces, 1)
    }

    /// Nothing to replace is not a plan to send zero keystrokes; it is no plan.
    func testAnEmptyWordHasNoPlan() {
        XCTAssertNil(SwitchPlan.make(replacing: "", with: "x"))
        XCTAssertNil(SwitchPlan.make(replacing: "x", with: ""))
    }
}
