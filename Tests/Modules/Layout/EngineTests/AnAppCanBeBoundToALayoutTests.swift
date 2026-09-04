import XCTest
@testable import Module_Layout_Engine

/// **Which layout an application is typed in, when the person has said so.**
///
/// The module does not learn this. An earlier design watched which layout you
/// left each application on and acted after two agreeing departures; it was
/// dropped because the module already owns a per-application table a person
/// fills in themselves, and a binding cannot mis-learn — it can only go out of
/// date, and then it is changed where it was set.
///
/// So the only real logic here is the third case: a layout that was bound and
/// is no longer installed. Doing nothing is right; selecting some other layout
/// because one was asked for is not.
final class AnAppCanBeBoundToALayoutTests: XCTestCase {

    private let installed = ["com.apple.keylayout.US", "com.apple.keylayout.Russian"]

    func testABoundAppAnswersItsLayout() {
        XCTAssertEqual(
            AppLayouts.layout(for: "ru.keepcoder.Telegram",
                              bindings: ["ru.keepcoder.Telegram": "com.apple.keylayout.Russian"],
                              installed: installed),
            "com.apple.keylayout.Russian")
    }

    func testAnUnboundAppAnswersNothing() {
        XCTAssertNil(AppLayouts.layout(for: "com.apple.Safari",
                                       bindings: ["ru.keepcoder.Telegram": "com.apple.keylayout.Russian"],
                                       installed: installed))
    }

    /// The case this unit exists for: bound to a layout that has since been
    /// removed in System Settings.
    func testALayoutThatIsGoneAnswersNothing() {
        XCTAssertNil(AppLayouts.layout(for: "ru.keepcoder.Telegram",
                                       bindings: ["ru.keepcoder.Telegram": "com.apple.keylayout.Ukrainian"],
                                       installed: installed))
    }

    /// Nowhere to type is not somewhere safe to type — the boundary
    /// `AppScope.allows` already draws.
    func testAnEmptyBundleIdAnswersNothing() {
        XCTAssertNil(AppLayouts.layout(for: "",
                                       bindings: ["": "com.apple.keylayout.Russian"],
                                       installed: installed))
    }

    func testNoBindingsAtAllAnswersNothing() {
        XCTAssertNil(AppLayouts.layout(for: "ru.keepcoder.Telegram",
                                       bindings: [:], installed: installed))
    }

    /// No installed layouts at all is a Mac this cannot act on, and the empty
    /// list must not be read as «anything goes».
    func testNothingInstalledAnswersNothing() {
        XCTAssertNil(AppLayouts.layout(for: "ru.keepcoder.Telegram",
                                       bindings: ["ru.keepcoder.Telegram": "com.apple.keylayout.Russian"],
                                       installed: []))
    }
}
