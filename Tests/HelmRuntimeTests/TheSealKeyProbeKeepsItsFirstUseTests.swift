import XCTest
import HelmTestSupport

/// A test of the fake and no defect class the table keeps: the kept classes that
/// build over `SealKeyProbe` go red first if it ever answers otherwise.
final class TheSealKeyProbeKeepsItsFirstUseTests: XCTestCase {

    /// The probe's fixed `firstUse` is answered on every ask, later ones too:
    /// a guard built fresh over a store that is the run that made the item must
    /// not see the door shut by the second read.
    func testAFixedFirstUseIsAnsweredOnEveryAsk() {
        let probe = SealKeyProbe(firstUse: true)
        XCTAssertEqual(probe.key()?.firstUse, true)
        XCTAssertEqual(probe.key()?.firstUse, true)
        XCTAssertEqual(SealKeyProbe().key()?.firstUse, true)
    }
}
