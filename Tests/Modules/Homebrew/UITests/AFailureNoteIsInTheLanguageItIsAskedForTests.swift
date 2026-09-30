import XCTest
import HelmContract
import HelmTestSupport
import HelmUI
@testable import Module_Homebrew_Engine
@testable import Module_Homebrew_UI

/// `HomebrewSettingsPage.failureNote(_:language:)` takes a language, and every
/// reason's note must answer in it — not only the ones whose words happen to be
/// built from an inline table. A note that answers in the process's language
/// whatever it is asked for makes any test that names the language check a
/// different one than it names, and passes it by luck.
@MainActor
final class AFailureNoteIsInTheLanguageItIsAskedForTests: XCTestCase {

    func testEveryReasonAnswersInTheLanguageNamed() {
        func failed(_ reason: OpFailureReason) -> OpState {
            OpState(phase: .failed, label: "install Homebrew", exitCode: 3, reason: reason)
        }
        var english: [OpFailureReason: String] = [:]
        AppLanguage.only(.en) {
            for reason in OpFailureReason.allCases {
                english[reason] = HomebrewSettingsPage.failureNote(failed(reason))
            }
        }
        XCTAssertEqual(english.count, OpFailureReason.allCases.count - 1,
                       "precondition: every reason but .stopped has an English note")

        // The process in another language, the note asked for in English.
        AppLanguage.only(.de) {
            for reason in OpFailureReason.allCases where english[reason] != nil {
                XCTAssertEqual(HomebrewSettingsPage.failureNote(failed(reason), language: .en), english[reason],
                               "\(reason.rawValue): asked for English, answered in the process's language")
            }
        }
    }
}
