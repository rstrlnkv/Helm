import XCTest
@testable import Module_Layout_Engine

final class ScopeTests: XCTestCase {
    func testExceptionsAreCaseInsensitiveAndTrimmed() {
        let list = Exceptions(words: ["  Ghbdtn ", "тест"])
        XCTAssertTrue(list.contains("ghbdtn"))
        XCTAssertTrue(list.contains("GHBDTN"))
        XCTAssertTrue(list.contains("Тест"))
        XCTAssertFalse(list.contains("other"))
    }

    /// An empty entry would match the empty word and disable everything quietly.
    func testBlankEntriesAreDropped() {
        let list = Exceptions(words: ["", "   ", "word"])
        XCTAssertEqual(list.words.count, 1)
        XCTAssertFalse(list.contains(""))
    }

    /// Terminals and password managers are refused before any rule is read.
    func testTheDefaultBlocklistIsRefusedOutright() {
        let scope = AppScope(rules: [:])
        for bundle in ["com.apple.Terminal", "com.googlecode.iterm2",
                       "com.agilebits.onepassword7", "com.1password.1password"] {
            XCTAssertFalse(scope.allows(bundle), bundle)
        }
    }

    func testAnythingElseIsAllowedByDefault() {
        XCTAssertTrue(AppScope(rules: [:]).allows("com.apple.Notes"))
    }

    func testAnExplicitRuleWins() {
        let scope = AppScope(rules: ["com.apple.Notes": false, "com.apple.Terminal": true])
        XCTAssertFalse(scope.allows("com.apple.Notes"))
        XCTAssertTrue(scope.allows("com.apple.Terminal"), "the user said so")
    }

    /// No frontmost app means no idea where the text would land.
    func testAnUnknownAppIsRefused() {
        XCTAssertFalse(AppScope(rules: [:]).allows(""))
    }
}
