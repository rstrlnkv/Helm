import XCTest
import AppKit
import SwiftUI
import HelmContract
import HelmTestSupport
import HelmUI
@testable import Module_Homebrew_Engine
@testable import Module_Homebrew_UI

/// **The owner's second decision on the split gutter, read off the real page:
/// only the list's own side of it closes.**
///
/// `HomebrewSettingsPage`'s `HStack(spacing: HelmSpace.s5) { listArea…;
/// Divider(); detail… }` put an equal 12 pt gap on both sides of the
/// `Divider()` — the gap the owner was shown a screenshot of and asked which
/// side to close. The answer kept the inspector's side exactly where it draws
/// today and closed only the list's: `HStack(spacing: 0)`, with
/// `.padding(.leading, HelmSpace.s5)` added to `detail` *after* its own
/// `.frame(...)` — so the gap that used to sit between the divider and the
/// inspector now lives inside the inspector's own box instead of in the
/// stack, and `HomebrewSplit.masterWidth`'s `gutter` drops from
/// `HelmSpace.s5 * 2 + 1` to `HelmSpace.s5 + 1` to match, which hands the
/// master column the 12 pt the list-side gap used to waste.
///
/// **Measured against the unfixed page**, 850 pt pane — wide enough to show
/// the inspector and, checked against `HomebrewSplit` itself rather than
/// assumed, still 75 pt short of `HelmLayout.readingColumn`'s 444 pt ceiling,
/// so the 12 pt the fix hands the master column is a real move and not one
/// already spent against the ceiling: a probe mount (`ZZZProbeTests`, written
/// to take this reading and deleted once this file replaced it as the record)
/// found the `Divider()`'s own `CALayer` at x = 369, one point wide, 650 pt
/// tall; the master `List` stopped at x = 357, 12 pt short of it; and the
/// inspector's `ScrollView` began at x = 382, 12 pt past the divider's far
/// edge. `HomebrewSplit(availableWidth: 850).masterWidth` read 357 too, so
/// the list already filled everything the old formula gave it — the 12 pt
/// gap was the formula's own gutter, not the list falling short of its frame.
///
/// **The arithmetic behind the fix leaves the divider and the inspector
/// exactly where they were.** The new `gutter` hands the master column the
/// 12 pt the list-side gap used to spend, so `masterWidth` grows from 357 to
/// 369 at this pane — which is exactly where the divider already stood — and
/// the divider-to-inspector distance, moved from the stack's own spacing into
/// `detail`'s padding, is still 12 pt. Nothing on the inspector's side of the
/// divider has a reason to move; this file asserts that it does not,
/// alongside the one thing that does move: the list now runs all the way to
/// the divider it used to fall 12 pt short of.
///
/// **850 pt alone once proved less than it looked.** A first version of
/// `masterWidth` handed the master its 12 pt only where the *share* already
/// sat strictly between `HomebrewSplit`'s floor and its ceiling — roughly
/// 803 to 925 pt — and left the floor and the ceiling exactly as they were
/// everywhere else, which moves the divider (and the inspector past it) by
/// up to 12 pt at every other width, the 984 pt pane this page actually draws
/// included. 850 pt sits inside that one safe band, so a guard that only
/// mounted the page there stayed green through that defect. Fixed now by
/// adding the 12 pt *after* `masterWidth`'s own clamp rather than only to the
/// unclamped value, so it lands the same way at the floor and the ceiling as
/// in between; `testTheDividerDoesNotMoveAcrossThePane` below mounts the page
/// at widths on both sides of that band, including 646 (this window's own
/// minimum, sidebar subtracted) and 984, to check the general claim this
/// header makes rather than the one width that could not tell it apart from
/// the narrower one.
@MainActor
final class TheGapBesideTheListClosesOnlyThereTests: XCTestCase {

    /// Two installed formulae — enough to draw the master list and, with one
    /// selected, the inspector beside it.
    private final class TwoPackages: EngineTransport, @unchecked Sendable {
        private let stream = AsyncStream<EngineEvent>.makeStream()
        var events: AsyncStream<EngineEvent> { stream.stream }
        static let wget = BrewPackage(name: "wget", version: "1.25.0", isCask: false)
        static let openssl = BrewPackage(name: "openssl@3", version: "3.6.4", isCask: false)

        func send(_ command: EngineCommand) async throws -> Data {
            switch HomebrewCommand(rawValue: command.name) {
            case .status:
                return try JSONEncoder().encode(
                    BrewStatus(installed: true, brewPath: "/opt/fixture/bin/brew"))
            case .listInstalled:
                return try JSONEncoder().encode([Self.wget, Self.openssl])
            case .descriptions:
                return try JSONEncoder().encode([String: String]())
            default:
                return Data()
            }
        }
    }

    private struct Reading {
        let listMaxX: CGFloat
        let dividerFrame: CGRect
        let paneMinX: CGFloat
    }

    /// 850 pt — see this file's own header for why this width is the one that
    /// actually exercises the fix rather than one already pinned at a floor
    /// or a ceiling.
    private static let width: CGFloat = 850

    /// The three things the owner's two decisions are about, read off one
    /// mount: the master list's own trailing edge, the `Divider()`'s
    /// `CALayer` — found by shape rather than by name, since a plain
    /// `Divider()` mounts no `NSView` of its own to match the way
    /// `_FocusRingView` and `ListCoreScrollView` do — and the inspector's
    /// `ScrollView`.
    private func read(at width: CGFloat,
                      file: StaticString = #filePath, line: UInt = #line) async -> Reading? {
        let transport = TwoPackages()
        let mvm = ModuleViewModel(transport: transport)
        let hb = HomebrewViewModel.shared(vm: mvm)
        await hb.loadIfNeeded()
        hb.select(TwoPackages.wget.id)
        let mount = MountedRender(HomebrewSettingsPage(vm: mvm),
                                  width: width, height: 700, appearance: .aqua)
        mount.settle(30)
        defer { mount.drop(); withExtendedLifetime(transport) {} }

        guard let list = mount.host.everyView
            .filter({ $0.appKitClassName.contains("ListCoreScrollView") })
            .map({ $0.convert($0.bounds, to: mount.host) }).first else {
            XCTFail("no master list drew at \(width) pt", file: file, line: line)
            return nil
        }

        // The inspector is the one `ScrollView` the package view mounts —
        // `TheInspectorsColumnSitsInTheMiddleTests`' own reason for reading
        // this class rather than `NSScrollView` directly.
        guard let pane = mount.host.everyView
            .filter({ $0.appKitClassName.contains("HostingScrollView") })
            .map({ $0.convert($0.bounds, to: mount.host) }).first else {
            XCTFail("no inspector scroll view drew at \(width) pt", file: file, line: line)
            return nil
        }

        guard let root = mount.host.layer else {
            XCTFail("the host has no layer to read", file: file, line: line)
            return nil
        }
        // A `Divider()` draws no `NSView`; it is a plain `CALayer` with a
        // background fill, one point wide and as tall as the row it stands
        // in — found the way `TheInspectorsColumnSitsInTheMiddleTests` finds
        // the facts' card, by the shape the search is for rather than by a
        // class name SwiftUI does not export for it.
        var dividers: [CGRect] = []
        func walk(_ layer: CALayer) {
            let frame = layer.convert(layer.bounds, to: root)
            if frame.width > 0, frame.width <= 2, frame.height > 100 { dividers.append(frame) }
            layer.sublayers?.forEach(walk)
        }
        walk(root)
        guard dividers.count == 1, let divider = dividers.first else {
            XCTFail("""
                found \(dividers.count) hairline-and-tall layer(s) at \(width) pt where the \
                Divider() between the two columns is exactly one — \(dividers)
                """, file: file, line: line)
            return nil
        }

        return Reading(listMaxX: list.maxX, dividerFrame: divider, paneMinX: pane.minX)
    }

    /// **The list now runs all the way to the divider it used to fall 12 pt
    /// short of.** The failing half of the two decisions: before the fix this
    /// read 357 against 369, 12 pt short — after it, both read 369.
    func testTheListMeetsTheDivider() async {
        guard let reading = await read(at: Self.width) else { return }
        XCTAssertEqual(reading.listMaxX, reading.dividerFrame.minX, accuracy: 0.5, """
            the master list ends at x = \(reading.listMaxX) and the divider begins at \
            x = \(reading.dividerFrame.minX) — \
            \(reading.dividerFrame.minX - reading.listMaxX) pt of gap on the list's own side, \
            which is the half of the gutter the owner asked to close
            """)
    }

    /// **Neither the divider nor the inspector moved.** Measured against the
    /// unfixed page at this pane, in this file's own header: the divider sat
    /// at x = 369 and the inspector's content began at x = 382, 12 pt past
    /// its far edge — both hardcoded here as the position the fix must land
    /// on exactly, not merely approach, since "the inspector's column stays
    /// where it is today" was the owner's own second half of the decision,
    /// and a change that closed the list's side while also nudging the
    /// inspector would still be the wrong fix.
    func testNeitherTheDividerNorTheInspectorMoved() async {
        guard let reading = await read(at: Self.width) else { return }
        XCTAssertEqual(reading.dividerFrame.minX, 369, accuracy: 0.5, """
            the divider now sits at x = \(reading.dividerFrame.minX), not the 369 the unfixed page \
            already drew it at — the fix has moved the divider itself rather than only closing the \
            gap in front of it
            """)
        XCTAssertEqual(reading.paneMinX, reading.dividerFrame.maxX + HelmSpace.s5, accuracy: 0.5, """
            the inspector's content begins at x = \(reading.paneMinX), \
            \(reading.paneMinX - reading.dividerFrame.maxX) pt past the divider's far edge at \
            x = \(reading.dividerFrame.maxX) — the owner's own second decision was to leave this \
            distance exactly as it was
            """)
        XCTAssertEqual(reading.paneMinX, 382, accuracy: 0.5, """
            the inspector's content begins at x = \(reading.paneMinX), not the 382 the unfixed page \
            already drew it at — "the inspector's column stays where it is today" is the owner's \
            own second decision and this is the number it was measured against
            """)
    }

    /// **The claim this file's header makes — checked at widths the 850 pt
    /// case above cannot tell apart from a formula that only holds in the
    /// one band between `HomebrewSplit`'s floor and its ceiling.**
    ///
    /// `referenceDivider(at:)` below is `HomebrewSplit.masterWidth`'s own
    /// formula *before* the owner's gap decision, kept here — not read off
    /// the type, which is exactly what changed — as the position the fix
    /// owes the divider at each width: `min(max(310, W - 25 - inspector),
    /// 444) + 12`, the pre-fix `HStack(spacing: 12)` gutter (25 = two 12 pt
    /// gaps plus the divider's own point) added back to the pre-fix master.
    ///
    /// The widths swept are the ones a reviewer's standalone probe of the
    /// formula (not this page) reported the first version of the fix moving
    /// the divider at: 646, the reviewer's reading of this window's own
    /// minimum width with the sidebar subtracted; 700 and 1049, either side
    /// of the safe band; and 984, the pane the app itself draws, where that
    /// probe read the divider moving from 456 to 444 — 12 pt, the whole
    /// width of the gap this fix was meant to spend on the list alone.
    func testTheDividerDoesNotMoveAcrossThePane() async {
        func referenceDivider(at width: CGFloat) -> CGFloat {
            let preFixGutter: CGFloat = HelmSpace.s5 * 2 + 1
            let inspector = HelmLayout.readingColumn + HelmSpace.s5 * 2
            let preFixMaster = min(max(310, width - preFixGutter - inspector),
                                   HelmLayout.readingColumn)
            return preFixMaster + HelmSpace.s5
        }

        for width: CGFloat in [646, 700, 850, 984, 1049] {
            guard let reading = await read(at: width) else { continue }
            let expected = referenceDivider(at: width)
            XCTAssertEqual(reading.dividerFrame.minX, expected, accuracy: 0.5, """
                at \(width) pt the divider sits at x = \(reading.dividerFrame.minX), not the \
                \(expected) it stood at before the list-side gap closed — the fix has moved the \
                divider itself at this width rather than only closing the gap in front of the list
                """)
            XCTAssertEqual(reading.listMaxX, reading.dividerFrame.minX, accuracy: 0.5, """
                at \(width) pt the master list ends at x = \(reading.listMaxX) and the divider \
                begins at x = \(reading.dividerFrame.minX) — a gap on the list's own side that \
                should be closed at every width the split shows, not only at \(Self.width)
                """)
            XCTAssertEqual(reading.paneMinX, reading.dividerFrame.maxX + HelmSpace.s5, accuracy: 0.5, """
                at \(width) pt the inspector's content begins at x = \(reading.paneMinX), \
                \(reading.paneMinX - reading.dividerFrame.maxX) pt past the divider's far edge — \
                the owner's second decision was to leave this distance exactly as it was
                """)
        }
    }
}
