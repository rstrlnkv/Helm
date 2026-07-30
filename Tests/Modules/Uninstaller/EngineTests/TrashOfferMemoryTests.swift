import XCTest
@testable import Module_Uninstaller_Engine

/// Cancel has to mean no, and no has to stick.
///
/// The offer is unprompted — the person dragged an app to the Trash and a window
/// appeared. A window that appears again at the next launch, and the one after
/// that, for an app they already declined to clean up after, is the difference
/// between a helpful app and one people switch off.
///
/// And it has to stop sticking eventually, or declining once means never being
/// asked about that app again for the life of the installation.
final class TrashOfferMemoryTests: XCTestCase {

    private func app(_ id: String, _ name: String = "App") -> TrashedApp {
        TrashedApp(bundleID: id, name: name, path: "/Users/ann/.Trash/\(name).app")
    }

    // MARK: - What to offer

    func testEverythingIsOfferedWhenNothingWasDeclined() {
        let found = [app("com.a"), app("com.b")]
        XCTAssertEqual(TrashOfferMemory.toOffer(found: found, dismissed: []).map(\.bundleID),
                       ["com.a", "com.b"])
    }

    func testADeclinedAppIsNotOfferedAgain() {
        let found = [app("com.a"), app("com.b")]
        XCTAssertEqual(TrashOfferMemory.toOffer(found: found, dismissed: ["com.a"]).map(\.bundleID),
                       ["com.b"])
    }

    /// One window for everything in the Trash, so declining one app must not
    /// silence the others — the person said no to that app, not to the feature.
    func testDecliningOneDoesNotSilenceTheRest() {
        let found = [app("com.a"), app("com.b"), app("com.c")]
        XCTAssertEqual(TrashOfferMemory.toOffer(found: found, dismissed: ["com.b"]).map(\.bundleID),
                       ["com.a", "com.c"])
    }

    /// Nothing to offer is a real answer and the caller must be able to tell it
    /// from "everything" — it is what decides whether a window opens at all.
    func testEverythingDeclinedOffersNothing() {
        let found = [app("com.a")]
        XCTAssertTrue(TrashOfferMemory.toOffer(found: found, dismissed: ["com.a"]).isEmpty)
    }

    /// The order is the order found, which the caller sets to the order the apps
    /// arrived. Filtering must not reshuffle the groups in the window.
    func testTheOrderFoundIsTheOrderOffered() {
        let found = [app("com.c"), app("com.a"), app("com.b")]
        XCTAssertEqual(TrashOfferMemory.toOffer(found: found, dismissed: []).map(\.bundleID),
                       ["com.c", "com.a", "com.b"])
    }

    // MARK: - When to forget

    /// The app left the Trash — restored, or the Trash was emptied. Either way the
    /// decision was about a state that no longer exists, so a later removal of the
    /// same app is a new question.
    func testAnAppThatLeftTheTrashIsForgotten() {
        XCTAssertEqual(TrashOfferMemory.stillDismissed(["com.a", "com.b"],
                                                       found: [app("com.b")]),
                       ["com.b"])
    }

    func testAnEmptyTrashForgetsEverything() {
        XCTAssertTrue(TrashOfferMemory.stillDismissed(["com.a", "com.b"], found: []).isEmpty)
    }

    /// An app still sitting there keeps its no. This is the case that makes the
    /// record worth having at all.
    func testAnAppStillInTheTrashKeepsItsNo() {
        XCTAssertEqual(TrashOfferMemory.stillDismissed(["com.a"], found: [app("com.a")]),
                       ["com.a"])
    }

    /// Finding an app that was never declined does not add it to the record —
    /// forgetting is the only thing this function does.
    func testFindingAnAppDoesNotDeclineIt() {
        XCTAssertTrue(TrashOfferMemory.stillDismissed([], found: [app("com.a")]).isEmpty)
    }

    /// The pair, in the sequence they actually run in: decline, restore, delete
    /// again — and the second removal asks.
    func testDecliningThenRestoringThenRemovingAgainAsksAgain() {
        let one = app("com.a")
        var dismissed: Set<String> = []

        // Offered, declined.
        XCTAssertEqual(TrashOfferMemory.toOffer(found: [one], dismissed: dismissed).count, 1)
        dismissed.insert(one.bundleID)
        XCTAssertTrue(TrashOfferMemory.toOffer(found: [one], dismissed: dismissed).isEmpty)

        // Restored from the Trash: the record is swept on the next look.
        dismissed = TrashOfferMemory.stillDismissed(dismissed, found: [])
        XCTAssertTrue(dismissed.isEmpty)

        // Dragged to the Trash a second time.
        XCTAssertEqual(TrashOfferMemory.toOffer(found: [one], dismissed: dismissed).count, 1,
                       "a second removal of the same app was never asked about")
    }
}
