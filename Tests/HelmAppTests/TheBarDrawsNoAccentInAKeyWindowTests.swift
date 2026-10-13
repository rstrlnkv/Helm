import AppKit
import HelmTestSupport
import ObjectiveC
import SwiftUI
import XCTest
@testable import HelmApp
@testable import HelmUI

/// **In a key window, under Liquid Glass, no segmented control in the page bar draws the system's accent
/// colour as its selection** — not the centre tabs, not the folded tabs, not a segmented action such as the
/// view-mode switcher. The stock `NSSegmentedControl` selection is the accent when its window is key and grey
/// when it is not; the bar's Flat cell draws its own neutral pill whatever the window is.
///
/// **The reading is ink, not frames.** Each control is photographed through `cacheDisplay` and its pixels are
/// counted: a pixel is *saturated* when it is more than half opaque, its HSB saturation is above 0.45 and its
/// brightness above 0.2 (in these rows' fixture the text, the glyphs and the neutral pill are grey-scale;
/// a tab's attention dot, `HelmSignal.warning`, would count as saturated, and no row declares one). The
/// reading is the share of saturated pixels among the pixels more than half opaque, and a control draws "no
/// accent" when that share is under `accentShare`. Every row reads Dark and Light, and each reading twice.
///
/// **What stands in for the window server.** No window of a `swift test` process is shown or key. A window
/// is made key by `AKeyWindowTheWindowServerDoesNotGive`, which makes one the way
/// `TheCapsuleDrawsWhatAppKitsPlatterDrawsTests` does (its header says why this is the faithful stand-in):
/// `isKeyWindow` and `isMainWindow` answer for the registered window, AppKit's own
/// private `acquireMainAppearance` and `acquireKeyAppearance` move the appearance the controls follow, and
/// the notification reaches the window's observers. The getters are put back by the test's teardown.
///
/// **The seam is held by its own row.** `testTheKeySeamMakesAStockControlDrawTheAccent` photographs a bare
/// stock segmented control with a selected segment, not key and then key: grey, then saturated. If that row
/// is red the other rows prove nothing, because a key window that draws no accent here would pass them for
/// the wrong reason. It reads the system's accent too: on a Mac whose accent colour is graphite the stock
/// selection is grey in a key window as well, the seam row goes red with "the accent colour is not
/// saturated", and so would every other row go green with nothing proven.
///
/// **Folded tabs** are the same `HelmToolbarSwitcher` with `compact: true`, one segment and a menu arrow; the
/// row finds the control under the tabs zone after asserting the zone folded, and fails when the folded zone
/// holds no `NSSegmentedControl` at all.
///
/// **What this file cannot see.** A glass control composited in a real window (the lens, the rim, the shape
/// of the selection against the capsule): `cacheDisplay` of an unshown window holds the control's own
/// drawing and no glass. The rows hold the colour the control draws, in a window made key by the stand-in.
@MainActor
final class TheBarDrawsNoAccentInAKeyWindowTests: XCTestCase {

    /// A control draws no accent while fewer than this share of its opaque pixels are saturated.
    private static let accentShare = 0.05

    // MARK: - The reading

    private struct Ink: CustomStringConvertible {
        var opaque = 0
        var saturated = 0
        /// The most saturated opaque pixel: hue in degrees, saturation, brightness.
        var sample: (hue: CGFloat, saturation: CGFloat, brightness: CGFloat)?

        var share: Double { opaque == 0 ? 0 : Double(saturated) / Double(opaque) }

        var description: String {
            let sample = sample.map {
                String(format: "most saturated pixel hue %.0f sat %.2f bri %.2f", $0.hue * 360, $0.saturation, $0.brightness)
            } ?? "no opaque pixel"
            return String(format: "%d of %d opaque pixels saturated (share %.3f), %@", saturated, opaque, share, sample)
        }
    }

    /// What `control` draws, as the share of saturated ink. Nil when it cannot be photographed.
    private static func ink(of control: NSView) -> Ink? {
        guard control.bounds.width > 0, control.bounds.height > 0,
              let rep = control.bitmapImageRepForCachingDisplay(in: control.bounds) else { return nil }
        control.cacheDisplay(in: control.bounds, to: rep)
        var found = Ink()
        for y in 0..<rep.pixelsHigh {
            for x in 0..<rep.pixelsWide {
                guard let color = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB), color.alphaComponent > 0.5 else { continue }
                found.opaque += 1
                var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
                color.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
                guard saturation > 0.45, brightness > 0.2 else { continue }
                found.saturated += 1
                if saturation > (found.sample?.saturation ?? 0) { found.sample = (hue, saturation, brightness) }
            }
        }
        return found
    }

    /// Two photographs of the same control: the second must agree with the first within one pixel in a
    /// hundred of the opaque ink, or the reading moved on its own and means nothing.
    private func read(_ control: NSView, _ what: String, file: StaticString = #filePath, line: UInt = #line) -> Ink? {
        guard let first = Self.ink(of: control), let second = Self.ink(of: control) else {
            XCTFail("\(what): the control cannot be photographed", file: file, line: line)
            return nil
        }
        XCTAssertGreaterThan(first.opaque, 0, "\(what): the control drew nothing", file: file, line: line)
        XCTAssertEqual(first.share, second.share, accuracy: 0.01,
                       "\(what): two photographs of one control disagree", file: file, line: line)
        return first
    }

    // MARK: - The seam, held by its own row

    /// A stock segmented control with a selected segment, alone in a window of this file's own.
    private func stockControl(appearance: NSAppearance.Name) -> (NSWindow, NSSegmentedControl) {
        let control = NSSegmentedControl(images: [NSImage(systemSymbolName: "tablecells", accessibilityDescription: nil)!,
                                                  NSImage(systemSymbolName: "text.alignleft", accessibilityDescription: nil)!],
                                         trackingMode: .selectOne, target: nil, action: nil)
        control.selectedSegment = 0
        control.controlSize = .extraLarge
        control.frame = NSRect(origin: NSPoint(x: 10, y: 10), size: control.fittingSize)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: control.frame.width + 20, height: control.frame.height + 20),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: appearance)
        window.contentView?.addSubview(control)
        return (window, control)
    }

    func testTheKeySeamMakesAStockControlDrawTheAccent() throws {
        try standInForTheWindowServer()
        for (name, appearance) in [("Dark", NSAppearance.Name.darkAqua), ("Light", .aqua)] {
            let (window, control) = stockControl(appearance: appearance)
            defer { window.orderOut(nil) }
            setKey(false, window)
            guard let resting = read(control, "\(name), not key") else { continue }
            setKey(true, window)
            guard let key = read(control, "\(name), key") else { continue }
            print("seam \(name): not key: \(resting); key: \(key)")
            XCTAssertLessThan(resting.share, Self.accentShare,
                              "\(name): a stock control in a window that is not key already draws saturated ink: \(resting)")
            XCTAssertGreaterThan(key.share, Self.accentShare, """
                \(name): the key seam does not make a stock segmented control draw the accent colour — either the seam \
                does not reach the control's drawing or the accent colour is not saturated on this Mac (graphite): \
                not key: \(resting); key: \(key). Every other row of this file proves nothing until this one is green.
                """)
        }
    }

    // MARK: - The bar

    private func tabs() -> [HelmToolbarTab] { AKeyWindowTheWindowServerDoesNotGive.tabs() }

    private func viewMode() -> HelmToolbarAction { AKeyWindowTheWindowServerDoesNotGive.viewMode() }

    private func setKey(_ on: Bool, _ window: NSWindow, file: StaticString = #filePath, line: UInt = #line) {
        AKeyWindowTheWindowServerDoesNotGive.setKey(on, window, file: file, line: line)
    }

    private func standInForTheWindowServer() throws {
        try AKeyWindowTheWindowServerDoesNotGive.install(in: self)
    }

    /// A bar of `width` in `appearance` under `look`, with the tabs and the view-mode switcher declared,
    /// settled and made key. The caller drops it.
    private func keyBar(look: HelmBarAppearance, appearance: NSAppearance.Name, width: CGFloat,
                        token: String) -> LivePageToolbarFixture {
        AppSettings.barAppearance = look
        let fx = LivePageToolbarFixture(Color.clear, selection: .module(token), width: width, height: 700,
                                        appearance: appearance)
        fx.channel.declare(HelmPageToolbarContent(tabs: tabs(), selectedTab: .constant("first"), actions: [viewMode()]),
                           token: token, generation: fx.channel.nextGeneration())
        fx.settle(10)
        if let window = fx.mount.window { setKey(true, window) }
        fx.settle(5)
        return fx
    }

    /// The segmented controls under one zone of the bar, and a failure when there is none.
    private func controls(_ zone: ShellPageBarView.Zone, of fx: LivePageToolbarFixture, _ what: String,
                          file: StaticString = #filePath, line: UInt = #line) -> [NSSegmentedControl] {
        guard let view = fx.bar.view.view(for: zone) else {
            XCTFail("\(what): the bar holds no \(zone) zone", file: file, line: line)
            return []
        }
        let found = view.everyView(ofType: NSSegmentedControl.self)
        if found.isEmpty {
            XCTFail("\(what): the \(zone) zone holds no NSSegmentedControl (views: \(view.everyView.map(\.appKitClassName)))",
                    file: file, line: line)
        }
        return found
    }

    /// Reads every control of `zone` in a key window and fails for each that draws the accent.
    private func assertNoAccent(look: HelmBarAppearance, width: CGFloat, zone: ShellPageBarView.Zone,
                                token: String, folded: Bool? = nil,
                                file: StaticString = #filePath, line: UInt = #line) throws {
        try standInForTheWindowServer()
        PinnedBarSettings.pin(in: self)
        for (name, appearance) in [("Dark", NSAppearance.Name.darkAqua), ("Light", .aqua)] {
            let what = "\(look) \(zone), \(name), key"
            let fx = keyBar(look: look, appearance: appearance, width: width, token: token + name)
            defer { fx.drop() }
            if let folded {
                XCTAssertEqual(fx.pageBar.tabs.isFolded, folded,
                               "\(what): precondition — the tabs are \(folded ? "not folded" : "folded") at width \(width)",
                               file: file, line: line)
            }
            XCTAssertEqual(fx.mount.window?.isKeyWindow, true, "\(what): precondition — the window is not key",
                           file: file, line: line)
            for control in controls(zone, of: fx, what, file: file, line: line) {
                guard let ink = read(control, what, file: file, line: line) else { continue }
                XCTAssertLessThan(ink.share, Self.accentShare, """
                    \(what): the segmented control (cell \(type(of: control.cell as Any)), \
                    \(control.segmentCount) segment(s), frame \(control.frame), subviews \
                    \(control.subviews.map(\.appKitClassName))) draws the accent colour: \(ink)
                    """, file: file, line: line)
            }
        }
    }

    func testGlassTabsDrawNoAccentInAKeyWindow() throws {
        try assertNoAccent(look: .liquidGlass, width: 1060, zone: .tabs, token: "test.accent.tabs", folded: false)
    }

    func testGlassFoldedTabsDrawNoAccentInAKeyWindow() throws {
        // The width that folds two short tabs beside the name is not known in advance: the narrowest
        // candidates are tried until the zone folds, and a width that never folds fails the row.
        try standInForTheWindowServer()
        PinnedBarSettings.pin(in: self)
        var foldingWidth: CGFloat?
        for width in [420, 340, 300, 260, 220, 180] as [CGFloat] {
            let probe = keyBar(look: .liquidGlass, appearance: .darkAqua, width: width, token: "test.accent.fold.probe")
            let folds = probe.pageBar.tabs.isFolded
            probe.drop()
            if folds { foldingWidth = width; break }
        }
        print("folded tabs: first folding width \(String(describing: foldingWidth))")
        let width = try XCTUnwrap(foldingWidth, "no candidate width folds the tabs: the folded zone was never read")
        try assertNoAccent(look: .liquidGlass, width: width, zone: .tabs, token: "test.accent.folded", folded: true)
    }

    func testGlassSegmentedActionDrawsNoAccentInAKeyWindow() throws {
        try assertNoAccent(look: .liquidGlass, width: 1060, zone: .actions, token: "test.accent.action")
    }

    /// The control case: the Flat cell draws by hand, so the same key window must read neutral. If this row
    /// is red too, the system's selection shows under the Flat cell as well.
    func testFlatTabsAndActionStayNeutralInAKeyWindow() throws {
        try assertNoAccent(look: .flat, width: 1060, zone: .tabs, token: "test.accent.flatTabs", folded: false)
        try assertNoAccent(look: .flat, width: 1060, zone: .actions, token: "test.accent.flatAction")
    }
}
