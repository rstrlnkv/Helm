import XCTest
import HelmTestSupport

/// **A badge that stopped hearing about switches.**
///
/// The menu-bar indicator redrew on `kTISNotifySelectedKeyboardInputSourceChanged`
/// and nothing else, registered with the block form of `addObserver`. That form
/// takes no suspension behaviour, so it gets the default one, which *coalesces*:
/// while a distributed-notification centre is suspended it keeps at most the
/// last notification and delivers it on resume. Helm is `LSUIElement` — never
/// the active application — so its centre is suspended nearly always, and a
/// layout switched with the person's own shortcut reached macOS while the badge
/// went on showing the previous layout until Helm was restarted.
///
/// It was misread twice as a stale *reading*. It never was: `InputSources.current()`
/// builds its list on the call, and the module's own menu — which reads the same
/// way — showed the right layout ticked while the badge beside it was wrong.
///
/// A source scan, because the defect is in an argument to a registration call.
/// An offscreen build registers nothing, and no fake can put a real centre into
/// the suspended state that produces this.
final class TheBadgeHearsSwitchesFromTheBackgroundTests: XCTestCase {

    private var indicator: String {
        get throws {
            SwiftSource.uncommented(try String(
                contentsOf: RepoSource.root.appendingPathComponent(
                    "Sources/Modules/Layout/UI/LanguageIndicator.swift"), encoding: .utf8))
        }
    }

    func testBothDistributedObserversAskForImmediateDelivery() throws {
        let text = try indicator
        let registrations = text.components(separatedBy: "addObserver(").count - 1
        XCTAssertEqual(registrations, 2,
                       "the scan found \(registrations) addObserver calls, not the two this "
                       + "guard was written against — read the file before trusting the rest")
        let immediate = text.components(separatedBy: "suspensionBehavior: .deliverImmediately").count - 1
        XCTAssertEqual(immediate, 2,
                       "\(immediate) of the 2 distributed observers ask for immediate delivery; "
                       + "the rest coalesce, and a suspended centre drops what it coalesces")
    }

    /// The block form is the regression: it compiles, it looks tidier, and it
    /// silently takes the coalescing default back.
    func testTheBlockFormIsNotUsedForTheDistributedCentre() throws {
        XCTAssertFalse(try indicator.contains("addObserver(\n            forName:"),
                       "a block observer is back — that form takes no suspension behaviour")
        XCTAssertFalse(try indicator.contains("addObserver(forName:"),
                       "a block observer is back — that form takes no suspension behaviour")
    }

    /// The premise, asserted rather than assumed. If Helm ever stops being an
    /// accessory app its centre is no longer suspended most of the time, and
    /// the reasoning above wants re-reading rather than inheriting.
    func testHelmIsStillAnAccessoryApp() throws {
        let plist = RepoSource.root.appendingPathComponent("Resources/HelmApp/Info.plist")
        let data = try Data(contentsOf: plist)
        let parsed = try PropertyListSerialization.propertyList(
            from: data, options: [], format: nil) as? [String: Any]
        XCTAssertEqual(parsed?["LSUIElement"] as? Bool, true,
                       "Helm is not LSUIElement any more — its notification centre is no longer "
                       + "suspended by default, so re-read why this guard exists")
    }

    /// The second channel: `FrontmostApp` is not the distributed centre, so a
    /// badge left behind by a shut door still comes right when the person
    /// changes application.
    func testTheBadgeAlsoFollowsTheFrontmostApplication() throws {
        let text = try indicator
        XCTAssertTrue(text.contains("FrontmostApp.shared.onChange"),
                      "the indicator has one channel again — the distributed centre alone")
        XCTAssertTrue(text.contains("FrontmostApp.shared.stopWatching"),
                      "the watch outlives the status item: FrontmostApp keeps its watchers for "
                      + "the life of the app and prunes none")
    }
}
