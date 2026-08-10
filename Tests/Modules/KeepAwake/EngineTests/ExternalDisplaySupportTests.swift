import XCTest
@testable import Module_KeepAwake_Engine

final class ExternalDisplaySupportTests: XCTestCase {
    func test_empty_flags_no_external() {
        XCTAssertFalse(ExternalDisplaySupport.hasExternal(builtInFlags: []))
    }
    func test_only_builtin_no_external() {
        XCTAssertFalse(ExternalDisplaySupport.hasExternal(builtInFlags: [true]))
    }
    func test_builtin_and_external_has_external() {
        XCTAssertTrue(ExternalDisplaySupport.hasExternal(builtInFlags: [true, false]))
    }
    func test_only_external_has_external() {
        XCTAssertTrue(ExternalDisplaySupport.hasExternal(builtInFlags: [false]))
    }

    /// The ambiguity, pinned so the next reviewer does not "fix" it twice.
    ///
    /// `[false]` is what a **desktop** reports, where this rule is then always
    /// true and means «never sleep» — and it is what a **laptop with the lid
    /// shut** reports, where it is exactly right and is the reason the rule
    /// exists. Requiring a built-in among the flags cures the first and kills
    /// the second. Whichever way it is decided, it cannot be decided from
    /// these flags alone: the missing fact is whether this Mac *has* a
    /// built-in panel, and an offline one looks the same as none.
    func testOnlyAnExternalIsReadAsDockedRatherThanAsADesktop() {
        XCTAssertTrue(ExternalDisplaySupport.hasExternal(builtInFlags: [false]),
                      "a laptop in clamshell reports exactly this, and the rule that is "
                      + "supposed to keep it awake at the dock would go quiet")
    }
}
