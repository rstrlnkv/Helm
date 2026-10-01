import AppKit
import HelmTestSupport
import HelmUI
import SwiftUI
import XCTest
import Module_Leftovers_Engine
@testable import Module_Leftovers_UI

/// **The tab switch in every shape a person meets it.**
///
/// The plainest is «Leftovers» and «All» flipped over a list that has rows on
/// both sides and nothing else moving (`testTheTabSwitchOverTwoListsIsACut`).
/// A person meets the switch in four more shapes, and each is a different view
/// tree:
///
/// - one tab empty and the other not — the page is an `if`/`else` between
///   `HelmEmptyState` and `List`, two views and not two states of one;
/// - the other switcher on the page, the kind menu, which narrows the same list;
/// - a scan or a removal landing — the page once kept
///   `.animation(HelmMotion.interface, value: lvm.items.count)` on its whole
///   `VStack`, so any change that shared a transaction with a count change was
///   carried on that curve, the tab included (the page has no such curve now;
///   these cases are what would catch it put back);
/// - the first scan, which swaps the invitation for the list, and a removal that
///   empties the tab, which swaps the list for the empty state.
///
/// Each case photographs the hosting view once per turn of the run loop with a
/// timestamp, in a named appearance, and counts the frames that are not the
/// settled one. `HELM_FRAMES_DIR` names a folder for the PNGs.
///
/// **The bound is zero unsettled frames after the first turn**, not «at most
/// two anywhere»: a curve short enough to fit in two frames is still a curve,
/// and a count cannot tell two slow frames at the start from two frames of
/// motion. What the table is allowed is its first turn to hear about its rows;
/// what it is not allowed is a frame after it that differs from the end.
///
/// **One turn, not two.** A swap between two views rebuilds the page, and a
/// rebuild takes a whole run-loop turn — how long is what each run prints as its
/// `[frames]` line (the timestamp after each `#`) — so a curve of 220 ms lands in
/// few frames, and two turns of grace would leave one frame between a real curve
/// and a pass. The recorder and the bound live in `FrameRecorder`
/// (`Tests/Support`), shared with `EveryTabSwitchIsACutTests`.
@MainActor
final class TheTabSwitchHoldsStillAtItsEdgesTests: XCTestCase {

    private var previous: AppLanguage?

    override func setUp() {
        super.setUp()
        previous = AppLanguage.override
    }

    override func tearDown() {
        AppLanguage.override = previous
        super.tearDown()
    }

    private static func item(_ name: String, kind: StaleKind = .launchAgent,
                             status: ItemStatus) -> StaleItem {
        StaleItem(path: "\(NSHomeDirectory())/Library/LaunchAgents/\(name).plist",
                  identifier: name, kind: kind, sizeBytes: 4_096, status: status)
    }

    /// Only software in use: «Leftovers» is the empty state, «All» is a list.
    private static var nothingLeftOver: [StaleItem] {
        [item("com.live.one", status: .inUse), item("com.live.two", status: .inUse),
         item("com.live.three", kind: .launchDaemon, status: .inUse),
         item("com.live.four", kind: .preference, status: .inUse)]
    }

    private static var mixed: [StaleItem] {
        [item("com.gone.one", status: .orphaned),
         item("com.gone.two", kind: .launchDaemon, status: .orphaned)] + nothingLeftOver
    }

    /// The change, then one frame per run-loop turn, timed from before the change.
    /// Split in two because `RunLoop.run` is unavailable from an async context and
    /// a scan is awaited: the async half makes the change without letting the run
    /// loop turn, the synchronous half photographs (`FrameRecorder`).
    private func frames(mount: MountedRender, turns: Int = 45,
                        after flip: () async -> Void) async throws -> [FrameRecorder.Frame] {
        let start = Date()
        await flip()
        return try FrameRecorder.photograph(mount.host, turns: turns, since: start)
    }

    private func write(_ frames: [FrameRecorder.Frame], mount: MountedRender, named: String) {
        FrameRecorder.write(frames, of: mount.host, named: named)
    }

    private func judge(_ shots: [FrameRecorder.Frame], before: Data, _ label: String,
                       file: StaticString = #filePath, line: UInt = #line) throws {
        try FrameRecorder.judge(shots, before: before, label, file: file, line: line)
    }

    /// One tab empty, the other a list: `HelmEmptyState` and `List` are two views,
    /// and the swap between them must be a cut in both directions.
    func testAnEmptyTabAndAFullOneSwapWithoutMotion() async throws {
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            let (mount, model) = await LeftoversPageRender.page(Self.nothingLeftOver, language: .en,
                                                                width: 700, appearance: appearance)
            defer { mount.drop() }
            XCTAssertNotNil(model.nothingToShow, "«Leftovers» must be the empty state for this case")
            for showAll in [true, false] {
                let before = try XCTUnwrap(mount.pixels())
                let shots = try await frames(mount: mount) { model.showAll = showAll }
                XCTAssertEqual(model.nothingToShow == nil, showAll)
                write(shots, mount: mount, named: "empty-\(appearance.rawValue)-showAll-\(showAll)")
                try judge(shots, before: before, "\(appearance.rawValue), empty tab, showAll \(showAll)")
            }
        }
    }

    /// The page's other switcher: the kind menu narrows the same `List`, and
    /// hiding the only kind left swaps it for the empty state.
    func testTheKindMenuNarrowsWithoutMotion() async throws {
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            let (mount, model) = await LeftoversPageRender.page(Self.mixed, language: .en,
                                                                width: 700, appearance: appearance)
            defer { mount.drop() }
            model.showAll = true
            mount.settle(30)
            for (name, change) in [("hide-daemons", { model.hiddenKinds.insert(.launchDaemon) }),
                                   ("hide-agents", { model.hiddenKinds.insert(.launchAgent) }),
                                   ("show-all-kinds", { model.hiddenKinds.removeAll() })]
                as [(String, () -> Void)] {
                let before = try XCTUnwrap(mount.pixels())
                let shots = try await frames(mount: mount) { change() }
                write(shots, mount: mount, named: "kinds-\(appearance.rawValue)-\(name)")
                try judge(shots, before: before, "\(appearance.rawValue), kind menu, \(name)")
            }
        }
    }

    /// A rescan lands with a different count and the tab is flipped before the
    /// page has drawn again — the flip would share the transaction a curve on
    /// the count animates, if the page had one.
    func testATabFlippedAsAScanLandsDoesNotRideItsCurve() async throws {
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            let wire = LeftoversWire(items: Self.mixed)
            let (mount, model) = await LeftoversPageRender.page(on: wire, language: .en,
                                                                width: 700, appearance: appearance)
            defer { mount.drop() }
            wire.setItems(Self.mixed + [Self.item("com.gone.three", status: .orphaned)])
            let before = try XCTUnwrap(mount.pixels())
            let shots = try await frames(mount: mount) {
                await model.scan()
                model.showAll = true
            }
            XCTAssertEqual(model.items.count, Self.mixed.count + 1, "the rescan did not land")
            write(shots, mount: mount, named: "scan-and-tab-\(appearance.rawValue)")
            try judge(shots, before: before, "\(appearance.rawValue), tab flipped as a scan lands")
        }
    }

    /// A rescan that finds one more row, without the tab: the page must re-lay
    /// out as a cut, the way the tab switch does now.
    func testARescanThatChangesTheCountDoesNotMorphThePage() async throws {
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            let wire = LeftoversWire(items: Self.mixed)
            let (mount, model) = await LeftoversPageRender.page(on: wire, language: .en,
                                                                width: 700, appearance: appearance)
            defer { mount.drop() }
            wire.setItems(Self.mixed + [Self.item("com.gone.three", status: .orphaned)])
            let before = try XCTUnwrap(mount.pixels())
            let shots = try await frames(mount: mount) { await model.scan() }
            XCTAssertEqual(model.items.count, Self.mixed.count + 1, "the rescan did not land")
            write(shots, mount: mount, named: "rescan-\(appearance.rawValue)")
            try judge(shots, before: before, "\(appearance.rawValue), rescan +1")
        }
    }

    /// «Leftovers» and «All» over two lists with rows on both sides — the
    /// plainest switch, held to the bound in the header: a page rebuild can take
    /// a turn the length of the `[frames]` line's timestamps, so a real curve
    /// lands one mid-flight frame in the sample, and a bound of «at most two
    /// unsettled anywhere» would let that through.
    func testTheTabSwitchOverTwoListsIsACut() async throws {
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            let (mount, model) = await LeftoversPageRender.page(Self.mixed, language: .en,
                                                                width: 700, appearance: appearance)
            defer { mount.drop() }
            XCTAssertNil(model.nothingToShow, "«Leftovers» must be a list for this case")
            for showAll in [true, false] {
                let before = try XCTUnwrap(mount.pixels())
                let shots = try await frames(mount: mount) { model.showAll = showAll }
                write(shots, mount: mount, named: "lists-\(appearance.rawValue)-showAll-\(showAll)")
                try judge(shots, before: before, "\(appearance.rawValue), two lists, showAll \(showAll)")
            }
        }
    }

    /// Move to Trash on one login item of two: the removal rescans, the count
    /// drops by one, a report appears under the list — and nothing slides.
    func testARemovalThatLeavesAListIsACut() async throws {
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            let gone = Self.item("com.gone.one", status: .orphaned)
            let wire = LeftoversWire(items: Self.mixed,
                                     removal: LeftoversRemoval(removed: [gone.path], refused: [],
                                                               freedBytes: 4_096))
            let (mount, model) = await LeftoversPageRender.page(on: wire, language: .en,
                                                                width: 700, appearance: appearance)
            defer { mount.drop() }
            XCTAssertEqual(model.visibleItems.count, 2, "«Leftovers» must hold two rows before")
            wire.setItems(Self.mixed.filter { $0.path != gone.path })
            let before = try XCTUnwrap(mount.pixels())
            let shots = try await frames(mount: mount) { await model.remove(gone) }
            XCTAssertEqual(wire.commands.suffix(2), [.trash, .scan], "the removal and its rescan did not happen")
            XCTAssertEqual(model.visibleItems.count, 1, "the rescan after the removal did not land")
            write(shots, mount: mount, named: "remove-one-\(appearance.rawValue)")
            try judge(shots, before: before, "\(appearance.rawValue), removal of one of two")
        }
    }

    /// Move to Trash on the last leftover: the list gives way to the empty
    /// state in the same act that changes the count.
    func testARemovalThatEmptiesTheTabIsACut() async throws {
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            let last = Self.item("com.gone.last", status: .orphaned)
            let wire = LeftoversWire(items: Self.nothingLeftOver + [last],
                                     removal: LeftoversRemoval(removed: [last.path], refused: [],
                                                               freedBytes: 4_096))
            let (mount, model) = await LeftoversPageRender.page(on: wire, language: .en,
                                                                width: 700, appearance: appearance)
            defer { mount.drop() }
            XCTAssertNil(model.nothingToShow, "«Leftovers» must be a list before the removal")
            wire.setItems(Self.nothingLeftOver)
            let before = try XCTUnwrap(mount.pixels())
            let shots = try await frames(mount: mount) { await model.remove(last) }
            XCTAssertEqual(wire.commands.suffix(2), [.trash, .scan], "the removal and its rescan did not happen")
            XCTAssertEqual(model.nothingToShow, .nothingFound, "the tab did not empty")
            write(shots, mount: mount, named: "remove-last-\(appearance.rawValue)")
            try judge(shots, before: before, "\(appearance.rawValue), removal of the last leftover")
        }
    }

    /// The first scan: the invitation gives way to the list, the toolbar gains
    /// its tabs and the review line appears — two views, not two states of one.
    func testTheFirstScanSwapsTheInvitationForTheListAsACut() async throws {
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            let wire = LeftoversWire(items: Self.mixed)
            let (mount, model) = await LeftoversPageRender.page(on: wire, language: .en,
                                                                width: 700, appearance: appearance,
                                                                scanned: false)
            defer { mount.drop() }
            XCTAssertEqual(model.nothingToShow, .notScanned, "the page must open on the invitation")
            let before = try XCTUnwrap(mount.pixels())
            let shots = try await frames(mount: mount) { await model.scan() }
            XCTAssertNil(model.nothingToShow, "the first scan did not put a list up")
            write(shots, mount: mount, named: "first-scan-\(appearance.rawValue)")
            try judge(shots, before: before, "\(appearance.rawValue), first scan")
        }
    }
}
