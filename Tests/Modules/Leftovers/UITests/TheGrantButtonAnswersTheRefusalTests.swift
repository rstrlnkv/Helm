import AppKit
import HelmContract
import HelmRuntime
import HelmTestSupport
import HelmUI
import XCTest
import Module_Leftovers_Engine
@testable import Module_Leftovers_UI

/// **The Grant button was keyed to the page's own probe, not to the refusal
/// under it.**
///
/// `PermissionCheck.reason` names Full Disk Access for `/Library/Containers/`
/// and `/Library/Group Containers/` paths only, and none of this scanner's
/// sources can reach one — so on a Mac without the grant every refusal this
/// module can actually produce came with a button offering a setting that fixes
/// none of them. A launch daemon refuses with `noPermission`, and the answer to
/// that is an administrator password.
@MainActor
final class TheGrantButtonAnswersTheRefusalTests: XCTestCase {

    private var previous: AppLanguage?

    override func setUp() {
        super.setUp()
        previous = AppLanguage.override
    }

    override func tearDown() {
        AppLanguage.override = previous
        super.tearDown()
    }

    private static let denied = HelmGrants(accessibility: .granted, fullDisk: .denied)

    private func agent(_ name: String) -> StaleItem {
        StaleItem(path: "\(NSHomeDirectory())/Library/LaunchAgents/\(name).plist",
                  identifier: name, kind: .launchAgent, sizeBytes: 4_096, status: .orphaned)
    }

    /// A page that has just been refused — with the disk grant **denied**, which
    /// is the whole point: keyed to that probe the button was drawn whatever the
    /// refusal said.
    ///
    /// Counted off the render rather than read off the view: `removalOutcome` is
    /// built inside a `body`, and how many controls the report put on the screen
    /// is the only answer that is about what a person sees. A refusal's own
    /// «show in Finder» button is `.borderless` and draws no focus ring, so the
    /// count moves by exactly one when the Grant button is there and by nothing
    /// when the refusal is merely named.
    private func refusalRound(_ reason: TrashFailure.Reason?)
    async -> (controls: Int, failures: Int) {
        let item = agent("com.vendor.updater")
        let refused = reason.map { [HelmTrash.Refusal(path: item.path, reason: $0)] } ?? []
        let wire = LeftoversWire(items: [item],
                                 removal: LeftoversRemoval(removed: reason == nil ? [item.path] : [],
                                                           refused: refused,
                                                           freedBytes: reason == nil ? 4_096 : 0))
        let (mount, model) = await LeftoversPageRender.page(on: wire, language: .en, width: 720,
                                                            appearance: .darkAqua,
                                                            grants: Self.denied)
        defer { mount.drop() }
        model.selected = [item.path]
        await model.removeSelected()
        mount.settle(30)
        return (LeftoversPageRender.controls(in: mount).count, model.failures.count)
    }

    /// The refusal this module can actually produce, on the Mac where it is most
    /// likely: `noPermission` over a launch daemon, with Full Disk Access denied.
    /// The answer to it is an administrator password, and the page offered a
    /// setting instead.
    func testARefusalThatIsNotAboutTheDiskGrantOffersNoGrantButton() async {
        let plain = await refusalRound(nil)
        let refused = await refusalRound(.noPermission)

        XCTAssertEqual(refused.failures, 1, "precondition: the removal really was refused")
        XCTAssertEqual(plain.failures, 0, "precondition: and the round it is measured against was not")
        XCTAssertEqual(refused.controls, plain.controls, """
            a Grant button stands beside a refusal Full Disk Access cannot fix — it was drawn \
            off the page's own probe, so on a Mac without the grant every refusal this module \
            can reach came with the wrong next step.
            """)
    }

    /// And the reading is not blind: handed the one reason the grant *does*
    /// answer, the same count moves by one. Nothing in this module's seven scan
    /// sources produces it — `PermissionCheck.reason` reserves it for container
    /// paths — so this is the component's state, reached to prove the measurement
    /// above can see a button at all.
    func testTheSameCountSeesTheButtonWhenTheRefusalIsTheGrant() async {
        let plain = await refusalRound(nil)
        let fullDisk = await refusalRound(.needsFullDiskAccess)

        XCTAssertEqual(fullDisk.failures, 1, "precondition: the removal really was refused")
        XCTAssertEqual(fullDisk.controls, plain.controls + 1, """
            the refusal Full Disk Access does answer draws no button either, so the check above \
            is measuring nothing.
            """)
    }
}
