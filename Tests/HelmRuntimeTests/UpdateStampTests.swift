import XCTest
@testable import HelmRuntime

/// The one stored number the update check reads back.
///
/// `lastUpdateCheck` is an `Int` in `UserDefaults`, and `checkOnLaunch` did
/// `now - last` with it — from `applicationDidFinishLaunching`. `Int.min`
/// there **overflows the subtraction** and traps, so
/// `defaults write com.helm.app lastUpdateCheck -int -9223372036854775808` is
/// an app that terminates at launch. The About page reads the same number to
/// say "checked 2 hours ago".
final class UpdateStampTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testAnOrdinaryStampComesBackAsItsDate() {
        let stamp = Int(now.timeIntervalSince1970) - 3600
        XCTAssertEqual(UpdateCheck.lastChecked(stored: stamp, now: now),
                       Date(timeIntervalSince1970: TimeInterval(stamp)))
    }

    /// The default, and what the About page already called "never checked".
    func testZeroIsNeverChecked() {
        XCTAssertNil(UpdateCheck.lastChecked(stored: 0, now: now))
    }

    /// The crash. A negative stamp is not a moment this app ever checked at,
    /// and the extreme one is the one that traps the subtraction it feeds.
    func testANegativeStampIsNeverChecked() {
        XCTAssertNil(UpdateCheck.lastChecked(stored: -1, now: now))
        XCTAssertNil(UpdateCheck.lastChecked(stored: Int.min, now: now))
    }

    /// The quieter half of the same field: a stamp in the future is not a
    /// check that happened, and taken at face value it holds "checked
    /// recently" true until the clock reaches it — with `Int.max` stored, for
    /// the life of the machine. No trap, no launch, and no update ever offered
    /// again.
    func testAStampInTheFutureIsNeverChecked() {
        XCTAssertNil(UpdateCheck.lastChecked(stored: Int(now.timeIntervalSince1970) + 1, now: now))
        XCTAssertNil(UpdateCheck.lastChecked(stored: Int.max, now: now))
    }

    /// The control: this instant is a check that happened, so the refusal
    /// above is a bound and not a blanket.
    func testAStampOfThisInstantIsKept() {
        XCTAssertEqual(UpdateCheck.lastChecked(stored: Int(now.timeIntervalSince1970), now: now),
                       now)
    }
}
