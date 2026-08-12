import XCTest
import HelmContract
import HelmRuntime
import HelmUI
@testable import Module_KeepAwake_Engine
@testable import Module_KeepAwake_UI

/// The system notification the battery veto posts, and the two ways it could be
/// dead without anything saying so.
///
/// The first is **a second wording**: the engine cannot reach `L()`, so the
/// sentence is handed in from here, and a notification that composed its own
/// would be one fact spelled twice — the defect
/// `TheBoundaryIsSpelledOnceTests` exists for, arriving by a route that test
/// cannot see because the notification never touches the screen it reads.
///
/// The second is **an engine with no port**. Every test of the posting itself
/// builds the engine with a fake, so forgetting to hand the real one over in
/// `makeEngine` leaves the whole feature switched off in the app with a green
/// suite behind it.
final class TheNoticeSaysWhatTheBannerSaysTests: XCTestCase {

    private static let floor = 20

    private var previous: AppLanguage?

    override func setUp() {
        super.setUp()
        previous = AppLanguage.override
    }

    override func tearDown() {
        AppLanguage.override = previous
        super.tearDown()
    }

    /// The body is the banner's own sentence, in all eight. English is the key,
    /// so English alone cannot show a table that stopped composing.
    func testTheNoticeCarriesTheBannersSentenceInEveryLanguage() {
        for language in AppLanguage.allCases {
            AppLanguage.override = language
            XCTAssertEqual(KAStr.batteryVetoNotice(Self.floor).body,
                           KAStr.stoppedByBattery(Self.floor),
                           "\(language.rawValue): the notification says the veto in its own "
                           + "words, so the page and the banner on the lock screen are two "
                           + "wordings of one fact")
        }
    }

    /// And it is titled with the module's name, because a notification with no
    /// title is drawn as the app's name and a body — which for an app of nine
    /// modules says nothing about which of them is speaking.
    func testTheNoticeIsTitledWithTheModule() {
        for language in AppLanguage.allCases {
            AppLanguage.override = language
            XCTAssertEqual(KAStr.batteryVetoNotice(Self.floor).title, KAStr.moduleName,
                           "\(language.rawValue): the notice's title is not the module's name")
        }
    }

    /// The way out reaches the notification too — the whole reason the long form
    /// exists. Asserted against the panel's short form rather than by looking for
    /// a word: the short one states the boundary and stops.
    func testTheNoticeIsTheLongFormAndNotThePanels() {
        for language in AppLanguage.allCases {
            AppLanguage.override = language
            XCTAssertNotEqual(KAStr.batteryVetoNotice(Self.floor).body,
                              KAStr.stoppedByBatteryShort(Self.floor),
                              "\(language.rawValue): a person who is not at the Mac was sent "
                              + "the row's fragment, which names no way out of the veto")
        }
    }

    /// The engine the app actually runs can reach macOS, and has the words.
    ///
    /// `reachesBanners` is both halves: a port with no sentence to post is as
    /// silent as a sentence with no port.
    @MainActor func testTheDescriptorGivesItsEngineAWayToReachMacOS() {
        let store = NamespacedStore(namespace: KeepAwakeEngine.moduleID,
                                    backing: InMemoryKeyValueStore())
        let engine = KeepAwakeDescriptor().makeEngine(store: store)
        defer { engine.deactivate() }
        let keepAwake = try? XCTUnwrap(engine as? KeepAwakeEngine)
        XCTAssertEqual(keepAwake?.reachesBanners, true,
                       "the module's own engine cannot post the one notification this app "
                       + "sends, so the battery veto is silent everywhere the person is not")
    }
}
