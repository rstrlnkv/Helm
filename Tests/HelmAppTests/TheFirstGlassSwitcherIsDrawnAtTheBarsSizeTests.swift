import AppKit
import HelmTestSupport
import ObjectiveC
import SwiftUI
import XCTest
@testable import HelmApp
@testable import HelmUI

/// **Every Liquid Glass switcher a process puts in the page bar is drawn at the bar's size** —
/// `HelmToolbarActionsCapsule.side` high, the control size `HelmToolbarSwitcher` pins (`.extraLarge`), and
/// no narrower than the width the actions zone reserved for it — whether it is the first the process draws
/// or a later one, in a bar that is key or not, with the tabs expanded or folded.
///
/// **Order is the subject, so the family never calls `TheGlassSwitcherWarmUp.run()`.** Filtered alone
/// (`bash Scripts/test.sh --filter TheFirstGlassSwitcherIsDrawnAtTheBarsSizeTests`) the family is the whole
/// process, and `testAllGlassSwitchersMountedInTurnAreDrawnAtTheBarsSize` sorts first among its rows: it
/// checks, as its first act, that none of this family's rows mounted a bar before it (the count of mounts
/// below). In a run that holds other families the count does not see their bars, and the first reading is
/// then not known to be the process's first. Each of the three measurement failures (height, control size,
/// width) prints the count; the two "no switcher in the zone" preconditions do not.
///
/// **A reading** is taken from the bar the fixture holds: each `NSSegmentedControl` under the tabs zone and
/// the actions zone, with its control size, its frame, the frame of the zone view it sits in, and for the
/// action the reserve the zone's model holds for it. The failure messages carry all of them.
///
/// **The key seam** is `AKeyWindowTheWindowServerDoesNotGive`, the one `TheBarDrawsNoAccentInAKeyWindowTests`
/// uses (the window's `isKeyWindow` and `isMainWindow` answered from a table, AppKit's own
/// `acquireMainAppearance` and `acquireKeyAppearance` called): the question here is only whether a key
/// window changes the size.
/// What an unshown window cannot say: how a real window server's activation orders the same calls.
@MainActor
final class TheFirstGlassSwitcherIsDrawnAtTheBarsSizeTests: XCTestCase {

    /// Bars mounted by this process's rows so far.
    private static var mounts = 0

    // MARK: - The bar

    private func tabs() -> [HelmToolbarTab] { AKeyWindowTheWindowServerDoesNotGive.tabs() }

    private func actions() -> [HelmToolbarAction] { [AKeyWindowTheWindowServerDoesNotGive.viewMode()] }

    private func standInForTheWindowServer() throws {
        try AKeyWindowTheWindowServerDoesNotGive.install(in: self)
    }

    private func makeKey(_ window: NSWindow) { AKeyWindowTheWindowServerDoesNotGive.setKey(true, window) }

    private var fixtures: [LivePageToolbarFixture] = []

    override func tearDown() {
        fixtures.forEach { $0.drop() }
        fixtures = []
        super.tearDown()
    }

    /// A bar of `width` under `look`, the tabs and the view-mode switcher declared and settled; made key when
    /// `key` is set. Dropped by teardown.
    private func mountBar(look: HelmBarAppearance, width: CGFloat = 1060, key: Bool = false,
                          style: ToolbarSwitcherStyle = .text) -> LivePageToolbarFixture {
        Self.mounts += 1
        let token = "test.firstGlass.\(Self.mounts)"
        AppSettings.barAppearance = look
        AppSettings.toolbarSwitcherStyle = style
        let fx = LivePageToolbarFixture(Color.clear, selection: .module(token), width: width, height: 700)
        fixtures.append(fx)
        fx.channel.declare(HelmPageToolbarContent(tabs: tabs(), selectedTab: .constant("first"), actions: actions()),
                           token: token, generation: fx.channel.nextGeneration())
        fx.settle(10)
        if key, let window = fx.mount.window { makeKey(window); fx.settle(5) }
        return fx
    }

    private struct Reading {
        let zone: String
        let controlSize: NSControl.ControlSize
        let frame: NSRect
        let zoneFrame: NSRect
        let reserve: CGFloat?
        let cell: String
        let object: UInt

        var description: String {
            "\(zone): controlSize \(controlSize.rawValue) (extraLarge is \(NSControl.ControlSize.extraLarge.rawValue)), " +
            "frame \(frame.width)x\(frame.height), zone view \(zoneFrame.width)x\(zoneFrame.height), " +
            "reserve \(reserve.map { "\($0)" } ?? "none"), cell \(cell), control #\(String(object, radix: 16))"
        }
    }

    private func readings(of fx: LivePageToolbarFixture) -> [Reading] {
        var found: [Reading] = []
        for (zone, name) in [(ShellPageBarView.Zone.tabs, "tabs"), (.actions, "actions")] {
            guard let view = fx.bar.view.view(for: zone) else { continue }
            let reserve: CGFloat? = {
                guard zone == .actions,
                      case .segmented(_, _, let reserve)? = fx.pageBar.actions.model.declared.first(where: { $0.id == "viewMode" })?.kind
                else { return nil }
                return reserve
            }()
            for control in view.everyView(ofType: NSSegmentedControl.self) {
                found.append(Reading(zone: name, controlSize: control.controlSize, frame: control.frame,
                                     zoneFrame: view.frame, reserve: reserve, cell: "\(type(of: control.cell as Any))",
                                     object: UInt(bitPattern: ObjectIdentifier(control).hashValue)))
            }
        }
        return found
    }

    /// The failure for every reading that is not at the bar's size; `what` names the state, and the
    /// measurement messages (height, control size, width) carry `mounts`, the number of bars this family had
    /// mounted when the reading was taken; the two "no switcher in the zone" preconditions carry `what` only.
    private func assertAtTheBarsSize(_ fx: LivePageToolbarFixture, _ what: String, tabsExpected: Bool = true,
                                     file: StaticString = #filePath, line: UInt = #line) {
        let all = readings(of: fx)
        let summary = all.map(\.description).joined(separator: "\n  ")
        print("[\(what)] mount #\(Self.mounts):\n  \(summary)")
        XCTAssertFalse(all.filter { $0.zone == "actions" }.isEmpty,
                       "\(what): precondition — no switcher in the actions zone", file: file, line: line)
        if tabsExpected {
            XCTAssertFalse(all.filter { $0.zone == "tabs" }.isEmpty,
                           "\(what): precondition — no switcher in the tabs zone", file: file, line: line)
        }
        for reading in all {
            XCTAssertEqual(reading.frame.height, HelmToolbarActionsCapsule.side, """
                \(what) (mount #\(Self.mounts) of this process): the \(reading.zone) switcher is \(reading.frame.height) pt high, \
                not the bar's \(HelmToolbarActionsCapsule.side). All readings:
                  \(summary)
                """, file: file, line: line)
            XCTAssertEqual(reading.controlSize, .extraLarge, """
                \(what) (mount #\(Self.mounts) of this process): the \(reading.zone) switcher has control size \
                \(reading.controlSize.rawValue), not extraLarge (\(NSControl.ControlSize.extraLarge.rawValue)). All readings:
                  \(summary)
                """, file: file, line: line)
            if let reserve = reading.reserve {
                XCTAssertGreaterThanOrEqual(reading.frame.width, reserve, """
                    \(what) (mount #\(Self.mounts) of this process): the action switcher is \(reading.frame.width) pt wide, \
                    narrower than the \(reserve) pt the zone reserved for it. All readings:
                      \(summary)
                    """, file: file, line: line)
            }
        }
    }

    // MARK: - The rows

    /// Three glass bars one after the other, nothing before them: the first is the process's first.
    func testAllGlassSwitchersMountedInTurnAreDrawnAtTheBarsSize() throws {
        PinnedBarSettings.pin(in: self)
        XCTAssertEqual(Self.mounts, 0, "precondition — a bar was mounted before this row: its first reading is not the process's first")
        let first = mountBar(look: .liquidGlass)
        assertAtTheBarsSize(first, "first glass bar")
        let second = mountBar(look: .liquidGlass)
        assertAtTheBarsSize(second, "second glass bar, first still mounted")
        first.drop()
        fixtures.removeAll { $0.mount === first.mount }
        let third = mountBar(look: .liquidGlass)
        assertAtTheBarsSize(third, "third glass bar, first dropped")
    }

    /// The same, in a key window.
    func testEveryGlassSwitcherInAKeyWindowIsDrawnAtTheBarsSize() throws {
        try standInForTheWindowServer()
        PinnedBarSettings.pin(in: self)
        assertAtTheBarsSize(mountBar(look: .liquidGlass, key: true), "glass bar made key")
        assertAtTheBarsSize(mountBar(look: .liquidGlass, key: true), "second glass bar made key")
    }

    /// The Flat look: the same cell, on the flat plate.
    func testFlatSwitchersAreDrawnAtTheBarsSize() throws {
        PinnedBarSettings.pin(in: self)
        assertAtTheBarsSize(mountBar(look: .flat), "flat bar")
        assertAtTheBarsSize(mountBar(look: .flat), "second flat bar")
    }

    /// The folded tabs (one segment and a menu arrow) are the same switcher.
    func testFoldedGlassTabsAreDrawnAtTheBarsSize() throws {
        PinnedBarSettings.pin(in: self)
        var folded: LivePageToolbarFixture?
        for width in [420, 340, 300, 260, 220, 180] as [CGFloat] {
            let fx = mountBar(look: .liquidGlass, width: width)
            if fx.pageBar.tabs.isFolded { folded = fx; break }
        }
        let fx = try XCTUnwrap(folded, "no candidate width folds the tabs")
        assertAtTheBarsSize(fx, "folded glass bar")
    }

    /// The tabs and the action with icons instead of words: the tabs zone is the only one the other rows
    /// draw in words.
    func testGlassSwitchersWithIconsAreDrawnAtTheBarsSize() throws {
        PinnedBarSettings.pin(in: self)
        assertAtTheBarsSize(mountBar(look: .liquidGlass, style: .icons), "glass bar, icons")
    }

    /// One bar read before it is made key, right after, and after the bar has settled.
    func testNoGlassBarShrinksWhenItsWindowBecomesKey() throws {
        try standInForTheWindowServer()
        PinnedBarSettings.pin(in: self)
        let fx = mountBar(look: .liquidGlass)
        assertAtTheBarsSize(fx, "glass bar, not key")
        if let window = fx.mount.window { makeKey(window) }
        assertAtTheBarsSize(fx, "same glass bar, key, nothing settled since")
        fx.settle(5)
        assertAtTheBarsSize(fx, "same glass bar, key, settled")
    }
}
