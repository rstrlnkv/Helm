import AppKit
import HelmTestSupport
@testable import HelmUI
import SwiftUI
import XCTest
@testable import HelmApp

/// Follow's two eyes (`HelmToolbarToggleFace`), fed what their own tests did
/// not feed: the real Log page pressed through the capsule and through the
/// overflow menu, the frames between the press and the new glyph, and a toggle
/// with no face drawn beside a plain button.
///
/// The Log page is mounted with a real `SettingsToolbar`
/// (`LivePageToolbarFixture`), so a press goes down the wire a click does:
/// the capsule's own `press`, or the menu item AppKit shows when the capsule
/// no longer fits.
@MainActor
final class TheFollowEyeUnderInputsNobodyFedTests: XCTestCase {

    private func logPage(_ appearance: NSAppearance.Name) -> LivePageToolbarFixture {
        let source = LogPageUnderHand.log(40)
        let fx = LivePageToolbarFixture(LogView(source: { source.lines }, storedLog: { false }),
                                        selection: .log, width: 1060, height: 700, appearance: appearance)
        fx.settle(40)
        return fx
    }

    private func actionsItem(_ fx: LivePageToolbarFixture) -> NSToolbarItem? {
        fx.mount.window?.toolbar?.items.first { $0.itemIdentifier.rawValue == "helm.actions" }
    }

    private func capsule(_ fx: LivePageToolbarFixture) -> NSHostingView<HelmToolbarActionsCapsule>? {
        actionsItem(fx)?.view as? NSHostingView<HelmToolbarActionsCapsule>
    }

    private func followIsOn(_ model: HelmToolbarActionsModel) -> Bool? {
        guard case .toggle(let isOn) = model.declared.first(where: { $0.id == "follow" })?.kind
        else { return nil }
        return isOn
    }

    /// The overflow menu's own item for Follow, found by what it presses.
    private func followMenuItem(_ item: NSToolbarItem?) -> NSMenuItem? {
        func find(_ menuItem: NSMenuItem) -> NSMenuItem? {
            if menuItem.representedObject as? String == "follow" { return menuItem }
            for child in menuItem.submenu?.items ?? [] { if let hit = find(child) { return hit } }
            return nil
        }
        return item?.menuFormRepresentation.flatMap(find)
    }

    private struct Ink: CustomStringConvertible {
        let coverage: CGFloat
        let red: CGFloat, green: CGFloat, blue: CGFloat
        func distance(to other: Ink) -> CGFloat {
            max(abs(red - other.red), abs(green - other.green), abs(blue - other.blue))
        }
        var description: String {
            String(format: "coverage %.1f, colour %.3f/%.3f/%.3f", coverage, red, green, blue)
        }
    }

    /// Slot `slot` of the capsule as cached now: ink summed over alpha, and its
    /// alpha-weighted colour in sRGB. Nil for a blank.
    ///
    /// The layout and the window's display are forced first: an offscreen
    /// window has no display cycle, and without them a cached bitmap is the
    /// graph as last laid out — an animation running on the model reads as a
    /// step. With them, a swap the harness animated itself over 500 ms read
    /// as 50 frames easing from the open eye's ink to the slashed eye's, and a
    /// dim as 50 frames of falling ink (probe, X-C tester).
    private func ink(_ view: NSView, slot: Int) -> Ink? {
        view.layoutSubtreeIfNeeded()
        view.window?.displayIfNeeded()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: rep)
        let side = HelmToolbarActionsCapsule.side
        let scale = CGFloat(rep.pixelsWide) / max(view.bounds.width, 1)
        let from = Int((side * CGFloat(slot) * scale).rounded(.down))
        let to = min(rep.pixelsWide, Int((side * CGFloat(slot + 1) * scale).rounded(.up)))
        var c: CGFloat = 0, r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
        for y in 0..<rep.pixelsHigh {
            for x in from..<to {
                guard let k = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                let a = k.alphaComponent
                c += a; r += k.redComponent * a; g += k.greenComponent * a; b += k.blueComponent * a
            }
        }
        return c > 0 ? Ink(coverage: c, red: r / c, green: g / c, blue: b / c) : nil
    }

    // MARK: - The overflow menu

    /// **When the capsule folds into AppKit's «»» menu, Follow is a
    /// checkmarked item, and the checkmark is the state.** The eyes do not
    /// reach the menu (a menu item carries the control's name and a state,
    /// the way every other toggle in this app's menus does): what a person
    /// sees there is «Follow ✓» while following and «Follow» while not. Held:
    /// the checkmark agrees with the capsule's own state before any press,
    /// after a press through the menu item, and after a second one — and a
    /// press through the menu reaches the page, which flips the capsule's eye.
    func testTheOverflowMenusFollowIsCheckedExactlyWhileFollowing() throws {
        let fx = logPage(.aqua)
        defer { fx.drop() }
        let model = try XCTUnwrap(capsule(fx)?.rootView.model, "no capsule")
        XCTAssertEqual(followIsOn(model), true, "the Log does not open following")
        var states: [String] = []
        for press in 0..<3 {
            let menuItem = try XCTUnwrap(followMenuItem(actionsItem(fx)),
                                         "press \(press): the overflow menu has no Follow item")
            let isOn = try XCTUnwrap(followIsOn(model))
            states.append("\(isOn ? "following" : "not following") → \(menuItem.state == .on ? "✓" : "no ✓")")
            XCTAssertEqual(menuItem.state, isOn ? .on : .off, """
                press \(press): the capsule says \(isOn ? "following" : "not following") and the \
                overflow menu's Follow is \(menuItem.state == .on ? "checked" : "unchecked")
                """)
            XCTAssertEqual(menuItem.title, AppStr.logFollow)
            XCTAssertTrue(menuItem.isEnabled, "press \(press): Follow in the menu is disabled")
            guard press < 2 else { break }
            let action = try XCTUnwrap(menuItem.action)
            NSApp.sendAction(action, to: menuItem.target, from: menuItem)
            fx.settle(20)
            XCTAssertEqual(followIsOn(model), !isOn,
                           "press \(press): a press on the menu's Follow did not reach the page")
        }
        XCTAssertEqual(states.count, 3, "the loop did not read three states: \(states)")
    }

    // MARK: - The frames of a press

    /// **A press swaps the eye in one step: no frame in between, no frame in
    /// the accent.** The capsule's slot is cached on every turn of the run loop
    /// from the press until 400 ms after it, in both appearances; every frame
    /// must be one of the two glyphs as they stand before and after — its ink
    /// within 2 % of one of them, its colour within 0.03 of the plain ink — and
    /// the last must be the slashed eye. The subject is asserted first: the
    /// glyph before the press and the glyph after it differ by more than 5 %,
    /// so an unchanged glyph cannot pass as a clean swap.
    ///
    /// **What it can see**: the same swap animated over 500 ms on the capsule's
    /// model reads as frames easing between the two inks through this reading
    /// (`ink(_:slot:)`'s own note), so a crossfade or a symbol replace would
    /// fail here. What it cannot see is the glass: it does not composite
    /// offscreen, so a flash of the glass itself on the press is not read.
    func testAPressSwapsTheEyeInOneStepWithNoAccentInBetween() throws {
        for appearance in RenderedInk.bothAppearances {
            let screen = RenderedInk.label(of: appearance)
            let fx = logPage(appearance)
            defer { fx.drop() }
            let view = try XCTUnwrap(capsule(fx), "\(screen): no capsule")
            let model = view.rootView.model
            let slot = try XCTUnwrap(model.declared.filter { model.visibleIDs.contains($0.id) }
                .firstIndex { $0.id == "follow" }, "\(screen): Follow is not in the capsule")
            XCTAssertEqual(followIsOn(model), true, "\(screen): the Log does not open following")
            let open = try XCTUnwrap(ink(view, slot: slot), "\(screen): the open eye drew nothing")

            var frames: [(TimeInterval, Ink?)] = []
            let pressed = Date()
            model.press("follow")
            while Date().timeIntervalSince(pressed) < 0.4 {
                frames.append((Date().timeIntervalSince(pressed), ink(view, slot: slot)))
                RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.005))
            }
            XCTAssertEqual(followIsOn(model), false, "\(screen): the press did not reach the page")
            let slashed = try XCTUnwrap(frames.last?.1, "\(screen): the last frame is blank")
            XCTAssertGreaterThan(abs(slashed.coverage - open.coverage) / open.coverage, 0.05, """
                \(screen): the glyph after the press draws the ink of the glyph before it \
                (\(open) → \(slashed)) — nothing was swapped, so no frame could be in between
                """)
            XCTAssertGreaterThan(frames.count, 10, "\(screen): only \(frames.count) frames were read")
            for (at, frame) in frames {
                let label = String(format: "%.0f ms", at * 1000)
                guard let frame else { XCTFail("\(screen): blank frame at \(label)"); continue }
                let isOpen = abs(frame.coverage / open.coverage - 1) <= 0.02
                let isSlashed = abs(frame.coverage / slashed.coverage - 1) <= 0.02
                XCTAssertTrue(isOpen || isSlashed, """
                    \(screen): the frame at \(label) is neither eye — \(frame), between the open \
                    eye's \(open) and the slashed eye's \(slashed)
                    """)
                XCTAssertLessThan(frame.distance(to: open), 0.03, """
                    \(screen): the frame at \(label) is drawn in a colour of its own — \(frame) \
                    against the plain ink \(open)
                    """)
            }
        }
    }

    // MARK: - A toggle with no face

    /// **A toggle with no face is drawn as it was: off, it is the plain button
    /// to the pixel; on, it is the accent.** No page but the Log declares a
    /// toggle today, so the page a face could have changed is the next one
    /// that does; this draws that one. With `HELM_FRAMES_DIR` set the four
    /// states are written for a person to look at, in both appearances.
    func testAToggleWithNoFaceIsThePlainButtonWhenOffAndTheAccentWhenOn() throws {
        for appearance in RenderedInk.bothAppearances {
            let screen = RenderedInk.label(of: appearance)
            func draw(_ action: HelmToolbarAction, _ name: String) throws -> (Ink, NSBitmapImageRep) {
                let fx = LivePageToolbarFixture(Color.clear, selection: .module("test.toggle"),
                                                width: 1060, height: 700, appearance: appearance)
                defer { fx.drop() }
                fx.channel.declare(HelmPageToolbarContent(actions: [action]), token: "test.toggle",
                                   generation: fx.channel.nextGeneration())
                fx.settle(30)
                let view = try XCTUnwrap(capsule(fx), "\(screen): no capsule")
                XCTAssertEqual(view.rootView.model.visibleIDs, [action.id])
                let reading = try XCTUnwrap(ink(view, slot: 0), "\(screen): \(name) drew nothing")
                let rep = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
                view.cacheDisplay(in: view.bounds, to: rep)
                write(rep, appearance: appearance, name: name)
                return (reading, rep)
            }
            let (plain, plainRep) = try draw(HelmToolbarAction(id: "mode", title: "Mode",
                                                               symbol: "text.alignleft") {}, "noface-plain")
            let (off, offRep) = try draw(HelmToolbarAction(id: "mode", title: "Mode", symbol: "text.alignleft",
                                                           isOn: false) {}, "noface-off")
            let (on, _) = try draw(HelmToolbarAction(id: "mode", title: "Mode", symbol: "text.alignleft",
                                                     isOn: true) {}, "noface-on")
            _ = try draw(HelmToolbarAction(id: "follow", title: "Follow", symbol: "eye", isOn: true,
                                           face: HelmToolbarToggleFace(offSymbol: "eye.slash", onValue: "Following",
                                                                       offValue: "Not following")) {}, "face-on")
            _ = try draw(HelmToolbarAction(id: "follow", title: "Follow", symbol: "eye", isOn: false,
                                           face: HelmToolbarToggleFace(offSymbol: "eye.slash", onValue: "Following",
                                                                       offValue: "Not following")) {}, "face-off")
            XCTAssertEqual(plainRep.pixelsWide, offRep.pixelsWide)
            XCTAssertEqual(plainRep.pixelsHigh, offRep.pixelsHigh)
            XCTAssertEqual(plainRep.bitmapData.map { Data(bytes: $0, count: plainRep.bytesPerPlane) },
                           offRep.bitmapData.map { Data(bytes: $0, count: offRep.bytesPerPlane) }, """
                \(screen): a toggle with no face, off, is not the plain button to the pixel \
                (\(off) against \(plain))
                """)
            XCTAssertGreaterThan(on.distance(to: plain), 0.15, """
                \(screen): a toggle with no face, on, is not in the accent (\(on) against \(plain))
                """)
        }
    }

    // MARK: - A return visit

    /// **A return visit draws the eye, not the accent, before the page
    /// redeclares.** Leaving a page and coming back shows its bar from a
    /// closure-free copy (`SettingsToolbar`'s frozen bar) until the page
    /// declares again; that copy is built action by action, and a toggle
    /// copied without its face is a toggle with no face — drawn in the accent,
    /// the blue the owner asked to be rid of, for as long as the page takes to
    /// redeclare. Held: on the return, before any redeclare, the capsule's
    /// entry still carries the face and the state, and so draws the open eye.
    /// The sequence is the ordinary return visit of
    /// `AnOrdinaryReturnVisitKeepsTheBarLitTests`.
    func testAReturnVisitKeepsTheEyeBeforeThePageRedeclares() throws {
        let face = HelmToolbarToggleFace(offSymbol: "eye.slash", onValue: "Following",
                                         offValue: "Not following")
        let model = SettingsModel(host: ModuleHost.shared)
        let channel = HelmWindowToolbarChannel()
        let toolbar = SettingsToolbar(model: model, channel: channel)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1060, height: 700),
                              styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        toolbar.window = window
        func capsuleEntry() throws -> HelmToolbarActionsModel.Entry {
            let item = try XCTUnwrap(window.toolbar?.items.first { $0.itemIdentifier.rawValue == "helm.actions" },
                                     "no actions item")
            let view = try XCTUnwrap(item.view as? NSHostingView<HelmToolbarActionsCapsule>, "no capsule")
            return try XCTUnwrap(view.rootView.model.declared.first { $0.id == "follow" }, "no Follow entry")
        }
        for isOn in [true, false] {
            model.selection = .module("test.followA")
            let generation = channel.nextGeneration()
            channel.declare(HelmPageToolbarContent(actions: [
                HelmToolbarAction(id: "follow", title: "Follow", symbol: "eye", isOn: isOn, face: face) {}
            ]), token: "test.followA", generation: generation)
            window.layoutIfNeeded()
            XCTAssertEqual(try capsuleEntry().toggleFace, face, "the live bar lost the face — the fixture is wrong")

            model.selection = .module("test.followB")
            channel.declare(HelmPageToolbarContent(actions: [
                HelmToolbarAction(id: "other", title: "Other", symbol: "bolt") {}
            ]), token: "test.followB", generation: channel.nextGeneration())
            channel.withdraw(token: "test.followA", generation: generation)
            model.selection = .module("test.followA")
            window.layoutIfNeeded()

            XCTAssertNil(channel.content(for: AnyHashable("test.followA")),
                         "the page redeclared — the frozen copy was never drawn")
            let entry = try capsuleEntry()
            XCTAssertEqual(entry.kind, .toggle(isOn: isOn), "the return visit lost Follow's state")
            XCTAssertEqual(entry.toggleFace, face, """
                \(isOn ? "following" : "not following"): the bar drawn on a return visit carries \
                Follow with no face, so until the page redeclares it is a plain toggle\
                \(isOn ? " — lit in the accent" : "") rather than the \(isOn ? "open" : "slashed") eye
                """)
        }
        _ = toolbar
    }

    /// The bitmap as drawn, over the window's background of that appearance,
    /// white glyphs recoloured to the label ink (offscreen a toolbar glyph comes
    /// out white on transparent in both appearances; glass does not composite).
    private func write(_ rep: NSBitmapImageRep, appearance: NSAppearance.Name, name: String) {
        guard let dir = ProcessInfo.processInfo.environment["HELM_FRAMES_DIR"] else { return }
        var background = NSColor.white, labelInk = NSColor.black
        NSAppearance(named: appearance)?.performAsCurrentDrawingAppearance {
            background = NSColor.windowBackgroundColor.usingColorSpace(.sRGB) ?? .white
            labelInk = NSColor.labelColor.usingColorSpace(.sRGB) ?? .black
        }
        let width = rep.pixelsWide, height = rep.pixelsHigh
        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        func byte(_ value: CGFloat) -> UInt8 { UInt8(max(0, min(255, (value * 255).rounded()))) }
        for y in 0..<height {
            for x in 0..<width {
                let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) ?? .clear
                let a = c.alphaComponent
                let white = c.redComponent > 0.95 && c.greenComponent > 0.95 && c.blueComponent > 0.95
                let source = white ? labelInk : c
                let at = (y * width + x) * 4
                bytes[at] = byte(source.redComponent * a + background.redComponent * (1 - a))
                bytes[at + 1] = byte(source.greenComponent * a + background.greenComponent * (1 - a))
                bytes[at + 2] = byte(source.blueComponent * a + background.blueComponent * (1 - a))
            }
        }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData),
              let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                                  bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                                  provider: provider, decode: nil, shouldInterpolate: false,
                                  intent: .defaultIntent),
              let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
        else { return }
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try? png.write(to: URL(fileURLWithPath: dir).appendingPathComponent(
            "\(name)-\(RenderedInk.label(of: appearance)).png"))
    }
}
