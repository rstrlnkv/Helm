import AppKit
import HelmTestSupport
import SwiftUI
import XCTest
@testable import HelmApp
@testable import HelmUI

/// **What the bar draws through SwiftUI sits in the middle of its zone's frame, in the real Settings window.**
///
/// The frames-only tests pass because the frames are right; the ink was measured 10 pt below them (name 10.0,
/// tab labels 11.2, action glyph 10.2, status badge 10.0). The window has no toolbar, the 32 pt titlebar lies
/// over the bar, the bar's top safe area is 28 and each zone's `NSHostingView` reads 20 of it, and SwiftUI
/// centres its content in what is left. So there are two claims, one per mechanism and one per symptom:
///
/// - (a) no hosting view under the bar hands SwiftUI a top safe-area inset (its `safeAreaInsets.top` is
///   zero, or its `safeAreaRegions` no longer include the container, which is the same thing to SwiftUI);
/// - (b) the ink the window's own bitmap holds for each zone's content is centred on the zone's frame, within
///   1.5 pt. That is read from pixels, not from frames.
///
/// **The page content is a stand-in.** The real pages declare nothing in a window that was never ordered, so
/// the content is declared on the window's channel the way `SettingsWindowRig.open` does (two tabs, one
/// action, a search), and the status is drawn through the bar's own `draw` with a status in the identity. The
/// bar, its zones, its hosts and the window are the real ones. The window is never ordered: the bitmap is the
/// theme frame's `cacheDisplay`, in a named appearance, read twice.
///
/// **The search zone's two inks are here too** (`testThePlaceholderAndTheMagnifierEachSitAtThePlatesMiddle`),
/// because they are read from this same bitmap of the real window; the existing union test in
/// `TheSearchRestsAsItsMagnifierTests` reads a bare field and stays as it is.
@MainActor
final class TheBarsInkSitsInTheMiddleOfTheBarTests: XCTestCase {

    /// The two settings this family writes, kept as the raw objects the defaults hold under their full keys
    /// (nil when the key is absent), so a teardown puts back exactly what was found: an absent key stays
    /// absent, and a key a neighbour left behind is neither read as the style nor written over.
    private var saved: [String: Any?] = [:]
    private static let keys = ["module.app.\(PageBarStyle.storageKey)", "module.app.alwaysCollapseSearch"]
    override func setUp() {
        super.setUp()
        for key in Self.keys { saved[key] = UserDefaults.standard.object(forKey: key) }
        // The style every test below measures under is set by the test itself; start from none stored.
        UserDefaults.standard.removeObject(forKey: Self.keys[0])
    }
    override func tearDown() {
        for key in Self.keys {
            if let found = saved[key] ?? nil { UserDefaults.standard.set(found, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }
        saved = [:]
        super.tearDown()
    }

    /// The measurement, printed so a passing run still shows it (`INKMID` lines).
    private func report(_ what: String, _ label: String, ink: (top: CGFloat, bottom: CGFloat), frameMiddle: CGFloat) {
        let middle = (ink.top + ink.bottom) / 2
        print("INKMID \(label) | \(what) | ink \(ink.top)...\(ink.bottom) middle \(middle) | frame middle \(frameMiddle) | off \(middle - frameMiddle)")
    }

    // MARK: - Reading a window

    /// One bitmap of a view, read in points from its top.
    @MainActor private struct Shot {
        let rep: NSBitmapImageRep
        let scale: CGFloat

        init?(_ view: NSView) {
            guard view.bounds.width > 0, view.bounds.height > 0,
                  let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
            view.cacheDisplay(in: view.bounds, to: rep)
            guard rep.bitmapData != nil, rep.samplesPerPixel == 4, rep.bitsPerSample == 8 else { return nil }
            self.rep = rep
            scale = CGFloat(rep.pixelsWide) / view.bounds.width
        }

        /// The rows (in points from the top) that hold a pixel further than `threshold` from the region's own
        /// background (its most common pixel), within `columns` of `rows`; nil when none does.
        func ink(columns: ClosedRange<CGFloat>, rows: ClosedRange<CGFloat>, threshold: Int) -> (top: CGFloat, bottom: CGFloat)? {
            guard let data = rep.bitmapData else { return nil }
            let x0 = max(0, Int((columns.lowerBound * scale).rounded())), x1 = min(rep.pixelsWide, Int((columns.upperBound * scale).rounded()))
            let y0 = max(0, Int((rows.lowerBound * scale).rounded())), y1 = min(rep.pixelsHigh, Int((rows.upperBound * scale).rounded()))
            guard x0 < x1, y0 < y1 else { return nil }
            let stride = rep.bytesPerRow
            var counts: [UInt32: Int] = [:]
            for y in y0..<y1 {
                for x in x0..<x1 {
                    let at = y * stride + x * 4
                    let key = UInt32(data[at]) << 24 | UInt32(data[at + 1]) << 16 | UInt32(data[at + 2]) << 8 | UInt32(data[at + 3])
                    counts[key, default: 0] += 1
                }
            }
            guard let modal = counts.max(by: { ($0.value, $0.key) < ($1.value, $1.key) })?.key else { return nil }
            let ground = (0..<4).map { Int(modal >> UInt32((3 - $0) * 8) & 255) }
            var first: Int?, last: Int?
            for y in y0..<y1 {
                var on = false
                for x in x0..<x1 {
                    let at = y * stride + x * 4
                    for c in 0..<4 where abs(Int(data[at + c]) - ground[c]) > threshold { on = true; break }
                    if on { break }
                }
                if on { if first == nil { first = y }; last = y }
            }
            guard let first, let last else { return nil }
            return (CGFloat(first) / scale, CGFloat(last + 1) / scale)
        }
    }

    /// `rect` of `view` in points from the top of `target`.
    private func topDown(_ rect: CGRect, of view: NSView, in target: NSView) -> CGRect {
        let r = view.convert(rect, to: target)
        return target.isFlipped ? r : CGRect(x: r.minX, y: target.bounds.height - r.maxY, width: r.width, height: r.height)
    }

    private func settle(_ rig: SettingsWindowRig, _ seconds: TimeInterval = 0.35) {
        rig.window.contentView?.layoutSubtreeIfNeeded()
        SettingsWindowRig.pump(seconds)
        rig.window.contentView?.layoutSubtreeIfNeeded()
        rig.window.displayIfNeeded()
    }

    /// The page with a name, tabs, an action and a search; or, when `status` is asked, a bare page (the bar
    /// draws a status only beside a name alone, `Snapshot.statusWord`) with a status drawn through the bar's
    /// own `draw`.
    private func prepare(_ rig: SettingsWindowRig, _ appearance: NSAppearance.Name, status: Bool) {
        rig.window.appearance = NSAppearance(named: appearance)
        rig.window.setContentSize(NSSize(width: 1060, height: 760))
        rig.pageBar?.setWindowAppearsActive(true)
        if status {
            rig.model.selection = .module("keep-awake")
            settle(rig)
            var identity = ShellPageBar.identity(for: .module("keep-awake"), host: rig.model.host)
            identity.status = (word: AppStr.moduleActive, active: true)
            rig.pageBar?.draw(identity)
        } else {
            rig.open("homebrew", search: true)
        }
        settle(rig)
    }

    /// A window of its own for each reading, so one appearance's drawing is never the next one's starting point.
    private func freshRig(_ appearance: NSAppearance.Name, status: Bool) -> SettingsWindowRig? {
        guard let rig = SettingsWindowRig.build(in: self, failure: "the window has no shell: no bar was read") else { return nil }
        prepare(rig, appearance, status: status)
        return rig
    }

    private func hostingViews(under view: NSView) -> [NSView] {
        var out: [NSView] = []
        if String(describing: type(of: view)).hasPrefix("NSHostingView") { out.append(view) }
        for sub in view.subviews where !sub.isHidden { out += hostingViews(under: sub) }
        return out
    }

    /// What SwiftUI is handed as the top inset by a hosting view: AppKit's own reading, unless the view has
    /// told SwiftUI to leave the container's safe area out.
    private func insetSwiftUIGets(_ host: NSView) -> CGFloat {
        guard let regioned = host as? SafeRegioned else { return host.safeAreaInsets.top }
        return regioned.safeAreaRegions.contains(.container) ? host.safeAreaInsets.top : 0
    }

    // MARK: - (a) the mechanism

    func testNoHostingViewUnderTheBarHandsSwiftUIATitlebarInset() {
        for (status, least) in [(false, 3), (true, 2)] {
            guard let rig = freshRig(.aqua, status: status) else { return }
            guard let bar = rig.pageBar?.view else { XCTFail("SettingsWindow holds no page bar: nothing was measured"); return }
            let hosts = hostingViews(under: bar)
            XCTAssertGreaterThanOrEqual(hosts.count, least,
                "the bar (status \(status)) holds \(hosts.count) hosting views, fewer than \(least): nothing was measured")
            XCTAssertNotNil(bar.window, "the bar is in no window: its safe area is not a reading")
            for host in hosts {
                XCTAssertEqual(insetSwiftUIGets(host), 0, accuracy: 0.01,
                    "\(type(of: host)) at \(host.frame) hands SwiftUI a top safe-area inset of \(host.safeAreaInsets.top) (the bar's is \(bar.safeAreaInsets.top)): its content is centred below the zone's middle")
            }
        }
    }

    // MARK: - (b) the symptom

    private func assertZonesInkIsCentred(_ rig: SettingsWindowRig, _ appearance: NSAppearance.Name, status: Bool,
                                         line: UInt = #line) {
        let label = RenderedInk.label(of: appearance)
        guard let bar = rig.pageBar?.view, let target = rig.window.contentView?.superview else {
            XCTFail("\(label): the window holds no bar or no theme frame: nothing was measured", line: line); return
        }
        guard let one = Shot(target), let two = Shot(target) else {
            XCTFail("\(label): the window gave no bitmap: nothing was measured", line: line); return
        }
        let barRect = topDown(bar.bounds, of: bar, in: target)
        var zones: [ShellPageBarView.Zone] = [.name, .tabs, .actions]
        if status { zones.append(.status) }
        var measured = 0
        for zone in zones {
            guard let view = bar.view(for: zone), !view.isHidden, view.frame.width > 0 else {
                XCTFail("\(label): the \(zone) zone is not mounted: nothing was measured there", line: line); continue
            }
            let frame = topDown(view.bounds, of: view, in: target)
            let columns = (frame.minX + 1)...(frame.maxX - 1)
            let rows = barRect.minY...barRect.maxY
            guard let a = one.ink(columns: columns, rows: rows, threshold: 60),
                  let b = two.ink(columns: columns, rows: rows, threshold: 60) else {
                XCTFail("\(label): the \(zone) zone drew no ink at all in \(frame): nothing was measured", line: line); continue
            }
            XCTAssertEqual(a.top, b.top, "\(label): two reads of the \(zone) zone differ", line: line)
            XCTAssertEqual(a.bottom, b.bottom, "\(label): two reads of the \(zone) zone differ", line: line)
            measured += 1
            report("\(zone)", label, ink: a, frameMiddle: frame.midY)
            let middle = (a.top + a.bottom) / 2
            XCTAssertEqual(middle, frame.midY, accuracy: 1.5,
                "\(label): the \(zone) zone's ink (y \(a.top) to \(a.bottom), middle \(middle)) is \(middle - frame.midY) pt off its frame's middle \(frame.midY) (frame y \(frame.minY) to \(frame.maxY))",
                line: line)
        }
        XCTAssertGreaterThan(measured, 0, "the bar drew no ink at all: nothing was measured", line: line)
    }

    func testTheInkOfTheNameTheTabsAndTheActionSitsAtTheirZonesMiddle() {
        AppSettings.pageBarStyle = .moduleName
        for appearance in RenderedInk.bothAppearances {
            guard let rig = freshRig(appearance, status: false) else { return }
            assertZonesInkIsCentred(rig, appearance, status: false)
        }
    }

    func testTheInkOfTheStatusBadgeSitsAtItsZonesMiddle() {
        AppSettings.pageBarStyle = .moduleName
        for appearance in RenderedInk.bothAppearances {
            guard let rig = freshRig(appearance, status: true) else { return }
            guard let bar = rig.pageBar?.view, let target = rig.window.contentView?.superview,
                  let view = bar.view(for: .status), !view.isHidden, view.frame.width > 0,
                  let shot = Shot(target), let again = Shot(target) else {
                XCTFail("\(RenderedInk.label(of: appearance)): the status zone is not mounted or the window gave no bitmap: nothing was measured")
                continue
            }
            let label = RenderedInk.label(of: appearance)
            let frame = topDown(view.bounds, of: view, in: target)
            let barRect = topDown(bar.bounds, of: bar, in: target)
            let args = ((frame.minX + 1)...(frame.maxX - 1), barRect.minY...barRect.maxY)
            guard let a = shot.ink(columns: args.0, rows: args.1, threshold: 60),
                  let b = again.ink(columns: args.0, rows: args.1, threshold: 60) else {
                XCTFail("\(label): the status zone drew no ink at all in \(frame): nothing was measured"); continue
            }
            XCTAssertEqual(a.top, b.top, "\(label): two reads differ")
            report("status", label, ink: a, frameMiddle: frame.midY)
            let middle = (a.top + a.bottom) / 2
            XCTAssertEqual(middle, frame.midY, accuracy: 1.5,
                "\(label): the status badge's ink (y \(a.top) to \(a.bottom), middle \(middle)) is \(middle - frame.midY) pt off its frame's middle \(frame.midY)")
        }
    }

    func testTheInkOfTheNameWithoutAnIconSitsAtItsZonesMiddle() {
        AppSettings.pageBarStyle = .windowTitle
        for appearance in RenderedInk.bothAppearances {
            guard let rig = freshRig(appearance, status: false) else { return }
            rig.shell.sidebarCollapsed = true
            settle(rig)
            guard let bar = rig.pageBar?.view, let target = rig.window.contentView?.superview,
                  let view = bar.view(for: .name), !view.isHidden, view.frame.width > 0,
                  let shot = Shot(target), let again = Shot(target) else {
                XCTFail("\(RenderedInk.label(of: appearance)): the name zone is not mounted or the window gave no bitmap: nothing was measured")
                continue
            }
            let label = RenderedInk.label(of: appearance)
            let frame = topDown(view.bounds, of: view, in: target)
            let barRect = topDown(bar.bounds, of: bar, in: target)
            let columns = (frame.minX + 1)...(frame.maxX - 1)
            guard let a = shot.ink(columns: columns, rows: barRect.minY...barRect.maxY, threshold: 60),
                  let b = again.ink(columns: columns, rows: barRect.minY...barRect.maxY, threshold: 60) else {
                XCTFail("\(label): the name zone drew no ink at all in \(frame): nothing was measured"); continue
            }
            XCTAssertEqual(a.top, b.top, "\(label): two reads differ")
            report("name without icon", label, ink: a, frameMiddle: frame.midY)
            let middle = (a.top + a.bottom) / 2
            XCTAssertEqual(middle, frame.midY, accuracy: 1.5,
                "\(label): the name without an icon (y \(a.top) to \(a.bottom), middle \(middle)) is \(middle - frame.midY) pt off its frame's middle \(frame.midY)")
        }
    }

    // MARK: - The search zone's two inks, each on its own

    private func all<T: NSView>(_ type: T.Type, under view: NSView) -> [T] {
        var out: [T] = []
        for sub in view.subviews {
            if let hit = sub as? T { out.append(hit) }
            out += all(type, under: sub)
        }
        return out
    }

    func testThePlaceholderAndTheMagnifierEachSitAtThePlatesMiddle() {
        for appearance in RenderedInk.bothAppearances {
            let label = RenderedInk.label(of: appearance)
            guard let rig = freshRig(appearance, status: false) else { return }
            guard let bar = rig.pageBar?.view, let target = rig.window.contentView?.superview,
                  let plate = bar.view(for: .search), !plate.isHidden,
                  let field = all(NSSearchField.self, under: plate).first, !field.isHidden else {
                XCTFail("\(label): the search zone shows no field: nothing was measured"); continue
            }
            XCTAssertEqual(field.stringValue, "", "\(label): precondition: the field holds text, not its placeholder")
            // The placeholder is drawn by the field's own label view (a private class, not an NSTextField); the
            // magnifier is the button the field holds.
            let buttons = all(NSButton.self, under: field)
            let texts = field.subviews.filter { !($0 is NSButton) }
            guard let text = texts.first, let glass = buttons.first else {
                XCTFail("\(label): the field holds \(texts.count) label views and \(buttons.count) buttons: no placeholder or no magnifier to measure"); continue
            }
            guard let shot = Shot(target), let again = Shot(target) else {
                XCTFail("\(label): the window gave no bitmap: nothing was measured"); continue
            }
            let plateRect = topDown(plate.bounds, of: plate, in: target)
            let barRect = topDown(bar.bounds, of: bar, in: target)
            let textRect = topDown(text.bounds, of: text, in: target)
            let glassRect = topDown(glass.bounds, of: glass, in: target)
            // The glyph's own columns: the button's, less its edges; the text's, less the glyph's.
            let glassColumns = (glassRect.minX + 3)...(glassRect.maxX - 3)
            let textColumns = max(textRect.minX, glassRect.maxX + 2)...(textRect.maxX - 2)
            for (what, columns) in [("placeholder text", textColumns), ("magnifier", glassColumns)] {
                guard let a = shot.ink(columns: columns, rows: barRect.minY...barRect.maxY, threshold: 30),
                      let b = again.ink(columns: columns, rows: barRect.minY...barRect.maxY, threshold: 30) else {
                    XCTFail("\(label): the \(what) drew no ink at all: nothing was measured"); continue
                }
                XCTAssertEqual(a.top, b.top, "\(label): two reads of the \(what) differ")
                report(what, label, ink: a, frameMiddle: plateRect.midY)
                let middle = (a.top + a.bottom) / 2
                XCTAssertEqual(middle, plateRect.midY, accuracy: 1.5,
                    "\(label): the \(what)'s ink (y \(a.top) to \(a.bottom), middle \(middle)) is \(middle - plateRect.midY) pt off the plate's middle \(plateRect.midY) (plate y \(plateRect.minY) to \(plateRect.maxY))")
            }
            let fieldRect = topDown(field.bounds, of: field, in: target)
            XCTAssertGreaterThanOrEqual(fieldRect.minY, plateRect.minY - 0.01,
                "\(label): the field (y \(fieldRect.minY) to \(fieldRect.maxY)) runs past the plate's top \(plateRect.minY)")
            XCTAssertLessThanOrEqual(fieldRect.maxY, plateRect.maxY + 0.01,
                "\(label): the field (y \(fieldRect.minY) to \(fieldRect.maxY)) runs \(fieldRect.maxY - plateRect.maxY) pt past the plate's bottom \(plateRect.maxY)")
        }
    }
}

@MainActor private protocol SafeRegioned: AnyObject { var safeAreaRegions: SafeAreaRegions { get set } }
extension NSHostingView: SafeRegioned {}
