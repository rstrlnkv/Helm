import HelmTestSupport
import XCTest
@testable import HelmApp

/// The About page's update card, and the state it could not draw.
///
/// `downloadAndInstall` handles «the release published no digest» by opening the
/// release page and writing a note about it — under a comment saying that a
/// browser opening on its own «reads as the button having done nothing. Say why
/// before the window goes away». It did not clear `available`, and the card asks
/// about a release **before** it asks about the note, so the sentence written
/// for that case was unreachable: the card went on saying «Update ready» with
/// «Update & Relaunch» under it while a browser opened by itself.
///
/// It shipped because nothing could draw it. `installState`, `available` and
/// `lastMessage` were `private(set)` on a `@MainActor` singleton, so four of the
/// card's states were unreachable from any harness — which is the seam this file
/// is written against, not only the branch.
@MainActor
final class TheCardCanDrawWhatTheUpdaterWritesTests: XCTestCase {

    private let release = UpdateService.Release(
        version: "9.9.9",
        pageURL: URL(string: "https://example.invalid/releases/9.9.9")!,
        zipURL: URL(string: "https://example.invalid/Helm.zip")!,
        downloadURL: nil,
        notes: "no digest line here")

    /// First, that the arm exists at all: a claim that something is unreachable
    /// is worth nothing until the route to it has been drawn once.
    func testTheSentenceHasAnArmOfItsOwn() {
        XCTAssertEqual(UpdateCard.drawn(installState: .idle, checking: false,
                                        hasRelease: false, hasAhead: false,
                                        note: .manualInstall),
                       .manualInstall)
    }

    /// And the finding: the state the updater itself writes for a release with
    /// no published digest has to reach that arm.
    func testTheStateTheUpdaterWritesForAReleaseWithNoDigestDrawsIt() {
        let updater = UpdateService(available: release)
        XCTAssertNotNil(updater.available, "precondition: there is an offer on the card")

        updater.noteManualInstall()

        XCTAssertEqual(UpdateCard.drawn(installState: updater.installState,
                                        checking: updater.checking,
                                        hasRelease: updater.available != nil,
                                        hasAhead: updater.aheadOfChannel != nil,
                                        note: updater.note),
                       .manualInstall,
                       "the card still offers to install a release Helm has just refused to "
                       + "install, while a browser opens by itself")
    }

    /// The four states that could not be rendered before the seam, each drawn
    /// from a service standing in that state.
    func testTheFourStatesAfterIdleEachDrawTheirOwnArm() {
        let states: [(UpdateService.InstallState, UpdateCard)] = [
            (.downloading, .downloading), (.installing, .installing),
            (.digestMismatch, .digestMismatch), (.failed, .failed),
        ]
        for (state, card) in states {
            let updater = UpdateService(available: release, installState: state)
            XCTAssertEqual(UpdateCard.drawn(installState: updater.installState,
                                            checking: updater.checking,
                                            hasRelease: updater.available != nil,
                                            hasAhead: false, note: nil),
                           card, "\(state) draws the wrong arm, or none")
        }
    }

    /// The order the card reads its facts in, which is where the defect lived.
    /// An offer outranks the notes below it — that is right, and it is why the
    /// offer has to be taken away rather than argued around.
    func testAnOfferOutranksTheNotesUnderIt() {
        XCTAssertEqual(UpdateCard.drawn(installState: .idle, checking: false,
                                        hasRelease: true, hasAhead: false,
                                        note: .upToDate),
                       .ready)
        XCTAssertEqual(UpdateCard.drawn(installState: .idle, checking: true,
                                        hasRelease: true, hasAhead: false, note: nil),
                       .checking,
                       "a check in flight is the newer fact than the offer it may replace")
    }

    /// And the picture the survey could not take: the card, drawn in both
    /// states, from a service standing in each of them.
    ///
    /// The offer is a full-width prominent button and a version figure; the
    /// refusal is one line and an icon. If withdrawing the offer changed
    /// nothing on screen, these two renders would be the same size — which is
    /// exactly what the defect was.
    func testTheCardOnScreenChangesWhenTheOfferIsWithdrawn() {
        let offered = ModulePageRender.drawn(AboutHelmView(updater: UpdateService(available: release)),
                                             in: .aqua, width: 645)
        let refused = UpdateService(available: release)
        refused.noteManualInstall()
        let drawn = ModulePageRender.drawn(AboutHelmView(updater: refused), in: .aqua, width: 645)

        XCTAssertGreaterThan(offered.layers.count, 20, "the offer state drew nothing at all")
        XCTAssertGreaterThan(drawn.layers.count, 20, "the manual-install state drew nothing at all")
        XCTAssertGreaterThan(offered.layers.count, drawn.layers.count,
                             "the card draws the same thing either way, so «Update & Relaunch» "
                             + "is still on screen for a release Helm refused to install")
    }

    func testWithNothingToSayTheCardReportsWhenItLastLooked() {
        XCTAssertEqual(UpdateCard.drawn(installState: .idle, checking: false,
                                        hasRelease: false, hasAhead: false, note: nil),
                       .lastChecked)
        XCTAssertEqual(UpdateCard.drawn(installState: .idle, checking: false,
                                        hasRelease: false, hasAhead: true, note: nil),
                       .ahead,
                       "a build ahead of its channel is the more specific answer of the two")
    }
}
