import HelmTestSupport
import XCTest

/// **A switch on the KeepAwake page that does not save is a setting the person
/// changed and the module did not.**
///
/// Every toggle there is `savingSwitch`, so the one place a change reaches its
/// `save` closure is the `onChange` inside it. Empty that, and the page draws,
/// the switch moves, and nothing is written or told. The write happens in a
/// view's change handler, which a unit test cannot drive, so the text is read.
final class ASavingSwitchSavesTests: XCTestCase {

    func testTheSwitchCallsItsSaveWhenTheValueChanges() throws {
        let file = "Sources/Modules/KeepAwake/UI/KeepAwakeSettingsPage.swift"
        let text = SwiftSource.uncommented(try RepoSource.text(of: file))
        let bodies = SwiftSource.bodiesNamed("savingSwitch", in: text)
        XCTAssertFalse(bodies.isEmpty, "\(file) has no `savingSwitch` — the scan is reading the wrong shape")
        for body in bodies {
            XCTAssertTrue(body.contains(".onChange(of: on.wrappedValue)"), "\(file): `savingSwitch` no longer watches the value")
            XCTAssertTrue(body.contains("save(v)"), "\(file): `savingSwitch` never calls `save`")
        }
    }
}
