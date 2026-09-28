import AppKit
import ObjectiveC
import SwiftUI
import XCTest
@testable import HelmApp
@testable import HelmUI

/// **The owner's "as AppKit" for a disabled action (2026-09-28): a disabled
/// entry in `HelmToolbarActionsCapsule` dims exactly as a disabled live AppKit
/// toolbar button does, in Light and Dark, with the window key and not.** The
/// reference is AppKit's own drawing, photographed fresh every run beside ours
/// in the same bar, never a number this file remembers — so this check says
/// nothing about which values `disabledGlyphOpacityDark` and its three siblings
/// hold, only whether what they produce lands where AppKit's own disabled
/// button lands.
///
/// **Photographed through the window server, not read through `cacheDisplay`.**
/// AppKit's toolbar glyph is vibrant: its final brightness is made by the
/// compositor, which `cacheDisplay` never runs. Read in this process through
/// `cacheDisplay` (tester, 2026-09-28), a live disabled `NSToolbarButton` drew
/// 0.098 not key where the built-in display shows 0.178 Dark and 0.256
/// Light, and the enabled one 0.847 key where the screen shows 1.000, while
/// ours moved by at most 0.025 between the two instruments — so a
/// `cacheDisplay` comparison holds the right constants red in three of the
/// four states, and the ink share `TheCapsuleDrawsWhatAppKitsPlatterDrawsTests`
/// compares passed with the inactive Dark and Light constants swapped. Here
/// the test's own window is ordered on screen and captured by its window
/// number — a process's own windows are the part of the screen macOS lets it
/// read without a Screen Recording grant; not measured here, since this Mac's
/// runner holds one — and each glyph is read as the median of the border of a
/// 48-pixel crop (24 pt on a 2x display) for the background, and the
/// strongest forty pixels' mean departure from it as a fraction of the room
/// there was (`255 − bg` over a dark ground, `bg` over a light one) — the
/// core of the stroke, less quantised than one pixel.
///
/// **On every attached display, because the display moves the reading.** The
/// same bar photographed on three displays of one Mac read AppKit's disabled
/// button, Light and key, at 0.302, 0.277 and 0.308, and one of them read
/// 0.313 earlier the same session — the compositor's output for a display, not
/// what is behind the window (a white, black or red window behind moved
/// nothing). Ours moves with it: ours minus AppKit, disabled button, at rest,
/// stayed within −0.005 … +0.007 on all three (Light key +0.004 … +0.007,
/// Light not key +0.001 … +0.002, Dark key −0.005 … +0.001, Dark not key
/// −0.004 … −0.001), the toggle and the menu within 0.004 of the button, and
/// main but not key draws what key draws on both sides. So the reference is
/// never a remembered number, and `tolerance` is 0.015.
///
/// **What stands in for the window server's key and main** is what
/// `TheCapsuleDrawsWhatAppKitsPlatterDrawsTests` uses, for the reason its own
/// header gives: a test process cannot activate itself, so the two getters
/// answer for this window and AppKit's own key and main appearance calls move
/// what it draws. The capsule's `appearsActive` is set the way
/// `SettingsToolbar.setWindowAppearsActive(_:)` sets it, `isKeyWindow ||
/// isMainWindow`, and the host is rebuilt as it rebuilds it;
/// `TheActionsCapsuleFollowsTheWindowsAppearsActiveTests` holds that feed.
///
/// **Red from every side** (tester, 2026-09-28, three displays): the Dark and
/// Light constants swapped, 54 failures; key and not key swapped, 54; the four
/// constants' change taken out, 54 — ours 0.505 against AppKit's 0.302 Light
/// key and 0.124 against 0.178 Dark not key; any one constant moved by 0.04
/// either way, 18 for a key constant (key and main-only) and 9 for a not-key
/// one, on every display. A move of 0.03 is the edge — Dark key +0.03 went red
/// on two displays by 0.0008 (the menu by 0.0033) and stayed green on the
/// third — and is not claimed. `.disabled(...)` taken off the entry: 55, the
/// press case below among them.
///
/// **What this cannot see.** A backdrop other than the bar at rest: with
/// content under the bar AppKit's vibrant glyph follows it and ours, a fixed
/// opacity, does not — measured with a solid fill under the bar, ours minus
/// AppKit reached −0.121 (Dark, white under the bar, key) and −0.078 (Light,
/// black), and the enabled glyph not key diverges the same way, so "as AppKit"
/// holds at rest only. Another macOS: the reference is live, so a run on
/// macOS 26 checks macOS 26, but only a run there does. Increase Contrast: a
/// window given the high-contrast appearance moved neither side, so the system
/// setting is not what that produces. VoiceOver: an `NSHostingView` answered
/// no accessibility children here, so the disabled trait is not read — the
/// press is.
@MainActor
final class ADisabledActionDimsAsAppKitsOwnButtonTests: XCTestCase {

    /// Ours minus AppKit, in core alpha, that a disabled glyph may differ by —
    /// see this file's header for the residuals it clears and the step it sees.
    private static let tolerance = 0.015

    /// The same for an enabled glyph with the window not key, which
    /// `inactiveGlyphOpacityDark` and `inactiveGlyphOpacityLight` draw:
    /// ours minus AppKit measured +0.012 to +0.015 on all three displays, so
    /// this pins "unchanged" and sees those two swapped, not a small step.
    private static let enabledInactiveTolerance = 0.025

    // MARK: - The window server's answer

    nonisolated(unsafe) static var answers: [ObjectIdentifier: (key: Bool, main: Bool)] = [:]

    /// `isKeyWindow` and `isMainWindow` answer from `answers` for a window
    /// registered there until this test's teardown puts AppKit's own back.
    private func standInForTheWindowServer() throws {
        Self.answers = [:]
        for (selector, isKey) in [(#selector(getter: NSWindow.isKeyWindow), true),
                                  (#selector(getter: NSWindow.isMainWindow), false)] {
            let method = try XCTUnwrap(class_getInstanceMethod(NSWindow.self, selector),
                                       "NSWindow has no \(selector) to answer for")
            let original = method_getImplementation(method)
            typealias Getter = @convention(c) (NSWindow, Selector) -> Bool
            let call = unsafeBitCast(original, to: Getter.self)
            let answering: @convention(block) (NSWindow) -> Bool = { window in
                guard let answer = ADisabledActionDimsAsAppKitsOwnButtonTests.answers[ObjectIdentifier(window)] else {
                    return call(window, selector)
                }
                return isKey ? answer.key : answer.main
            }
            method_setImplementation(method, imp_implementationWithBlock(answering))
            addTeardownBlock { method_setImplementation(method, original) }
        }
        addTeardownBlock { ADisabledActionDimsAsAppKitsOwnButtonTests.answers = [:] }
    }

    private static func appKit(_ window: NSWindow, _ name: String) {
        let selector = NSSelectorFromString(name)
        guard let method = class_getInstanceMethod(type(of: window), selector) else {
            return XCTFail("NSWindow no longer answers \(name): this file's stand-in for the window server is gone")
        }
        typealias Call = @convention(c) (AnyObject, Selector) -> Void
        unsafeBitCast(method_getImplementation(method), to: Call.self)(window, selector)
    }

    // MARK: - The photograph

    private typealias CreateImage = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?

    /// The window server's own composite of one of this process's windows, by
    /// number — looked up at run time because the SDK marks it obsoleted
    /// since macOS 15, which this package's macOS 26 floor makes uncallable
    /// from Swift.
    private static let createImage: CreateImage? = {
        guard let handle = dlopen(nil, RTLD_NOW), let symbol = dlsym(handle, "CGWindowListCreateImage") else { return nil }
        return unsafeBitCast(symbol, to: CreateImage.self)
    }()

    /// An sRGB, 8-bit copy of the photograph, its stride computed here.
    private struct Pixels {
        let width: Int
        let height: Int
        private var bytes: [UInt8]

        init?(_ image: CGImage) {
            let width = image.width, height = image.height
            self.width = width
            self.height = height
            bytes = [UInt8](repeating: 0, count: width * height * 4)
            guard let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
            let drawn: Bool = bytes.withUnsafeMutableBytes { raw in
                guard let context = CGContext(data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                              bytesPerRow: width * 4, space: space,
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
                context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
                return true
            }
            guard drawn else { return nil }
        }

        func luminance(_ x: Int, _ y: Int) -> Double {
            let index = (y * width + x) * 4
            return 0.2126 * Double(bytes[index]) + 0.7152 * Double(bytes[index + 1]) + 0.0722 * Double(bytes[index + 2])
        }

        /// The glyph centred at `centre` (pixels, top-left origin): see this
        /// file's header for the algebra.
        func coreAlpha(at centre: CGPoint) -> Double {
            let x0 = max(0, Int(centre.x) - 24), y0 = max(0, Int(centre.y) - 24)
            let x1 = min(width, x0 + 48), y1 = min(height, y0 + 48)
            guard x1 - x0 > 8, y1 - y0 > 8 else { return -1 }
            var border: [Double] = []
            for x in x0..<x1 { border += [luminance(x, y0), luminance(x, y1 - 1)] }
            for y in y0..<y1 { border += [luminance(x0, y), luminance(x1 - 1, y)] }
            border.sort()
            let ground = border[border.count / 2]
            var departures: [Double] = []
            var signed = 0.0
            for y in y0..<y1 {
                for x in x0..<x1 {
                    let value = luminance(x, y)
                    departures.append(abs(value - ground))
                    signed += value - ground
                }
            }
            let core = departures.sorted(by: >).prefix(40).reduce(0, +) / 40
            return signed >= 0 ? core / max(1, 255 - ground) : core / max(1, ground)
        }
    }

    // MARK: - The bar

    /// One glyph's reading per slot, for one appearance and one window state.
    private struct Reading {
        let appKitEnabled: Double
        let appKitDisabled: Double
        let ours: [String: Double]
    }

    private static let symbol = "arrow.up.circle"
    /// Every kind that draws through the capsule's shared glyph, disabled,
    /// after one enabled button — each read against AppKit's disabled button.
    private static let disabledKinds = ["button", "toggle", "menu"]

    private func read(_ appearance: NSAppearance.Name, on screen: NSScreen) throws -> [String: Reading] {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 120),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = HelmBandChoice.running.titlebarAppearsTransparent
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: appearance)
        let bar = DisabledPairBar(symbol: Self.symbol, disabledKinds: Self.disabledKinds)
        let toolbar = NSToolbar(identifier: NSToolbar.Identifier("disabled.dim.\(appearance.rawValue)"))
        toolbar.delegate = bar
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        window.toolbar = toolbar
        window.setFrameTopLeftPoint(NSPoint(x: screen.visibleFrame.minX + 120, y: screen.visibleFrame.maxY - 80))
        window.orderFrontRegardless()
        defer {
            withExtendedLifetime(bar) {
                Self.answers[ObjectIdentifier(window)] = nil
                window.orderOut(nil)
                window.toolbar = nil
            }
        }
        func settle(_ seconds: TimeInterval = 0.6) {
            let end = Date().addingTimeInterval(seconds)
            while Date() < end {
                autoreleasepool {
                    window.layoutIfNeeded()
                    RunLoop.current.run(until: Date().addingTimeInterval(0.02))
                }
            }
        }
        settle()
        XCTAssertTrue(window.screen === screen, """
            the window meant for \(screen.localizedName) sits on \(window.screen?.localizedName ?? "no screen") — \
            a reading below would be named after the wrong display
            """)
        let capture = try XCTUnwrap(Self.createImage, """
            CGWindowListCreateImage is gone from this system — photograph the window another way \
            (ScreenCaptureKit) before this check can say anything
            """)
        var readings: [String: Reading] = [:]
        for (state, key, main) in [("key", true, true), ("main, not key", false, true), ("not key", false, false)] {
            Self.answers[ObjectIdentifier(window)] = (key, main)
            XCTAssertEqual(window.isKeyWindow, key, "the window server stand-in does not answer isKeyWindow")
            XCTAssertEqual(window.isMainWindow, main, "the window server stand-in does not answer isMainWindow")
            Self.appKit(window, main ? "acquireMainAppearance" : "resignMainAppearance")
            Self.appKit(window, key ? "acquireKeyAppearance" : "resignKeyAppearance")
            bar.model.setAppearsActive(key || main)
            bar.rebuild()
            settle()

            let frame = try XCTUnwrap(window.contentView?.superview, "no theme frame")
            let buttons = Self.views(frame).filter { String(describing: type(of: $0)) == "NSToolbarButton" }
                .sorted { $0.convert($0.bounds, to: nil).minX < $1.convert($1.bounds, to: nil).minX }
            XCTAssertEqual(buttons.count, 2, """
                \(state): AppKit drew \(buttons.count) NSToolbarButton for its two live bordered items — \
                an item AppKit draws another way is not the reference this file holds ours to; re-probe
                """)
            guard buttons.count == 2 else { continue }
            let host = try XCTUnwrap(bar.item?.view, "no capsule on the bar")
            let side = HelmToolbarActionsCapsule.side
            let capsule = host.convert(host.bounds, to: nil)

            let image = try XCTUnwrap(capture(.null, 8, UInt32(window.windowNumber), 1 | 8)?.takeRetainedValue(),
                                      "\(state): the window server returned no photograph of this process's own window")
            let pixels = try XCTUnwrap(Pixels(image), "\(state): the photograph could not be read")
            let scale = CGFloat(pixels.width) / window.frame.width
            func alpha(_ rect: NSRect) -> Double {
                pixels.coreAlpha(at: CGPoint(x: rect.midX * scale, y: (window.frame.height - rect.midY) * scale))
            }
            func slot(_ index: Int) -> NSRect {
                NSRect(x: capsule.minX + CGFloat(index) * side, y: capsule.midY - side / 2, width: side, height: side)
            }
            var ours: [String: Double] = ["enabled": alpha(slot(0))]
            for (offset, kind) in Self.disabledKinds.enumerated() { ours[kind] = alpha(slot(offset + 1)) }
            readings[state] = Reading(appKitEnabled: alpha(buttons[0].convert(buttons[0].bounds, to: nil)),
                                      appKitDisabled: alpha(buttons[1].convert(buttons[1].bounds, to: nil)),
                                      ours: ours)
        }
        return readings
    }

    private static func views(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(views) }

    // MARK: - The check

    func testADisabledActionDimsAsAppKitsOwnDisabledToolbarButtonKeyAndNotKey() throws {
        try standInForTheWindowServer()
        XCTAssertFalse(NSScreen.screens.isEmpty, "no display attached — nothing below is photographed")
        let runs = NSScreen.screens.flatMap { screen in
            [NSAppearance.Name.aqua, .darkAqua].map { (screen: screen, appearance: $0) }
        }
        for (screen, appearance) in runs {
            let name = "\(appearance == .darkAqua ? "Dark" : "Light") on \(screen.localizedName)"
            let readings = try read(appearance, on: screen)
            for (state, active) in [("key", true), ("main, not key", true), ("not key", false)] {
                let reading = try XCTUnwrap(readings[state], "\(name) \(state): no reading")
                // The subject exists: the photograph holds AppKit drawing this
                // state, and a disabled button AppKit draws dimmer than its
                // enabled twin — otherwise every equality below is about nothing.
                if active {
                    XCTAssertGreaterThan(reading.appKitEnabled, 0.9, """
                        \(name) \(state): AppKit's enabled button reads \(reading.appKitEnabled), not full ink — \
                        the photograph does not hold an active window's bar
                        """)
                } else {
                    XCTAssertLessThan(reading.appKitEnabled, 0.5, """
                        \(name) \(state): AppKit's enabled button reads \(reading.appKitEnabled) — \
                        the photograph does not hold an inactive window's bar
                        """)
                }
                XCTAssertLessThan(reading.appKitDisabled, reading.appKitEnabled - 0.03, """
                    \(name) \(state): AppKit's disabled button reads \(reading.appKitDisabled) beside its enabled \
                    twin's \(reading.appKitEnabled) — the disabled state was not produced
                    """)
                XCTAssertGreaterThan(reading.appKitDisabled, 0.1, """
                    \(name) \(state): AppKit's disabled button reads \(reading.appKitDisabled) — nothing drawn to compare
                    """)

                for kind in Self.disabledKinds {
                    let mine = try XCTUnwrap(reading.ours[kind], "\(name) \(state): no reading of the disabled \(kind)")
                    XCTAssertEqual(mine, reading.appKitDisabled, accuracy: Self.tolerance, """
                        \(name) \(state): the disabled \(kind)'s glyph draws at \(mine) on screen, AppKit's own \
                        disabled toolbar button beside it at \(reading.appKitDisabled) \
                        (ours − AppKit = \(mine - reading.appKitDisabled))
                        """)
                }
                let enabled = try XCTUnwrap(reading.ours["enabled"], "\(name) \(state): no reading of the enabled button")
                XCTAssertEqual(enabled, reading.appKitEnabled,
                               accuracy: active ? Self.tolerance : Self.enabledInactiveTolerance, """
                    \(name) \(state): the enabled glyph draws at \(enabled) on screen, AppKit's own enabled \
                    toolbar button beside it at \(reading.appKitEnabled)
                    """)
            }
        }
    }

    /// The dim is only half of "disabled": the entry must still refuse the
    /// press. Clicked through the window the way a person clicks, with the
    /// enabled twin clicked first so a click that reaches nothing cannot pass.
    func testADisabledActionStillRefusesThePress() throws {
        try standInForTheWindowServer()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 120),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = HelmBandChoice.running.titlebarAppearsTransparent
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .aqua)
        let bar = DisabledPairBar(symbol: Self.symbol, disabledKinds: ["button", "toggle"])
        var pressed: [String] = []
        bar.model.press = { pressed.append($0) }
        let toolbar = NSToolbar(identifier: NSToolbar.Identifier("disabled.press"))
        toolbar.delegate = bar
        toolbar.displayMode = .iconOnly
        window.toolbar = toolbar
        window.setFrameTopLeftPoint(NSPoint(x: 120, y: (NSScreen.main?.visibleFrame.maxY ?? 900) - 80))
        window.orderFrontRegardless()
        defer {
            withExtendedLifetime(bar) {
                Self.answers[ObjectIdentifier(window)] = nil
                window.orderOut(nil)
                window.toolbar = nil
            }
        }
        Self.answers[ObjectIdentifier(window)] = (true, true)
        Self.appKit(window, "acquireMainAppearance")
        Self.appKit(window, "acquireKeyAppearance")
        func settle(_ seconds: TimeInterval) {
            let end = Date().addingTimeInterval(seconds)
            while Date() < end { RunLoop.current.run(until: Date().addingTimeInterval(0.02)) }
        }
        settle(0.6)
        let host = try XCTUnwrap(bar.item?.view, "no capsule on the bar")
        let capsule = host.convert(host.bounds, to: nil)
        let side = HelmToolbarActionsCapsule.side
        for (index, id) in ["enabled", "button", "toggle"].enumerated() {
            let point = NSPoint(x: capsule.minX + (CGFloat(index) + 0.5) * side, y: capsule.midY)
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                let event = try XCTUnwrap(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
                                                             timestamp: ProcessInfo.processInfo.systemUptime,
                                                             windowNumber: window.windowNumber, context: nil,
                                                             eventNumber: 0, clickCount: 1, pressure: 1))
                window.sendEvent(event)
                settle(0.1)
            }
            if id == "enabled" {
                XCTAssertEqual(pressed, ["enabled"], "a click on the enabled entry did not press it — nothing below is read")
            }
        }
        XCTAssertEqual(pressed, ["enabled"], "a disabled entry took a press: \(pressed)")
    }
}

/// One bar holding AppKit's pair — a live bordered item with a target and an
/// action, enabled, then its disabled twin — and the capsule holding one
/// enabled button and one disabled entry per kind, every glyph the same symbol.
@MainActor
private final class DisabledPairBar: NSObject, NSToolbarDelegate {
    let model = HelmToolbarActionsModel()
    let symbol: String
    private(set) var item: NSToolbarItem?

    init(symbol: String, disabledKinds: [String]) {
        self.symbol = symbol
        super.init()
        var entries: [HelmToolbarActionsModel.Entry] = [
            .init(id: "enabled", title: "Enabled", symbol: symbol, isEnabled: true),
        ]
        for kind in disabledKinds {
            switch kind {
            case "toggle":
                entries.append(.init(id: kind, title: kind, symbol: symbol, isEnabled: false, kind: .toggle(isOn: false)))
            case "menu":
                entries.append(.init(id: kind, title: kind, symbol: symbol, isEnabled: false,
                                     kind: .menu([.init(id: "item", title: "Item", isOn: true, isEnabled: true)])))
            default:
                entries.append(.init(id: kind, title: kind, symbol: symbol, isEnabled: false))
            }
        }
        model.setDeclared(entries)
        model.setVisibleIDs(entries.map(\.id))
    }

    private func host() -> NSView {
        let host = NSHostingView(rootView: HelmToolbarActionsCapsule(model))
        host.sizingOptions = [.intrinsicContentSize]
        return host
    }

    /// What `SettingsToolbar` does on every change of `appearsActive`.
    func rebuild() { item?.view = host() }

    @objc private func press(_ sender: Any?) {}

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        let item = NSToolbarItem(itemIdentifier: identifier)
        switch identifier.rawValue {
        case "appkit.enabled", "appkit.disabled":
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: identifier.rawValue)
            item.label = identifier.rawValue
            item.isBordered = true
            item.target = self
            item.action = #selector(press(_:))
            item.autovalidates = false
            item.isEnabled = identifier.rawValue == "appkit.enabled"
        case "helm.actions":
            item.view = host()
            self.item = item
        default:
            return nil
        }
        return item
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace, .init("appkit.enabled"), .init("appkit.disabled"), .space, .init("helm.actions"), .flexibleSpace]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }
}
