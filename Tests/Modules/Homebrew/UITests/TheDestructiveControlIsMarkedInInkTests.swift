import XCTest
import AppKit
import SwiftUI
import HelmContract
import HelmTestSupport
import HelmUI
@testable import Module_Homebrew_Engine
@testable import Module_Homebrew_UI

/// **Two buttons side by side, one of which deletes a package, drawn in
/// identical ink.**
///
/// The fix row offers Copy and Run. Run raises a question now and stands 12 pt
/// clear of its neighbour, and neither of those is something the eye catches
/// before the hand moves. `role: .destructive` was supposed to be: it is not.
/// Measured on a 984 pt pane in light appearance, 2026-09-16, the darkest pixel
/// of each label on the button's own `#EFEFEF` fill — «Скопировать» `#303030`
/// at 11.49:1, «Выполнить» `#303030` at 11.49:1. The same byte. On this macOS
/// the role reaches menus and dialogs and never the drawing, which
/// `GeneralSettingsPage` had already found out for a form row.
///
/// **So the claim here is a measurement and not an attribute.** A case that
/// asserted "the Run button has a modifier applied" proves nothing about what a
/// person sees — the defect it would be guarding against passed exactly that
/// test for a fortnight. What this reads is the pixels: the two labels must not
/// sample the same ink, in both appearances, each against the fill it is drawn
/// on rather than against the page behind it.
///
/// **And it asserts the neighbour is still ordinary.** A page that drew *both*
/// labels in danger ink would fail "they are the same" only because they are
/// the same; the marked one has to be the one that destroys something, so Copy
/// is checked against the window's own label ink as well.
@MainActor
final class TheDestructiveControlIsMarkedInInkTests: XCTestCase {

    /// A `brew doctor` finding whose fix is on the allowlist and runnable, so
    /// the row draws both buttons. The command is the irreversible one — the
    /// same deletion the Uninstall button raises a dialog for.
    nonisolated(unsafe) static let runnable = DoctorIssue(
        severity: .caution,
        title: "Some installed formulae are deprecated",
        body: "You should find replacements for the following formulae:\n  periphery",
        fix: DoctorFix(argv: ["uninstall", "periphery"], kind: .runnable))

    private final class OneRunnableFinding: EngineTransport, @unchecked Sendable {
        private let stream = AsyncStream<EngineEvent>.makeStream()
        var events: AsyncStream<EngineEvent> { stream.stream }
        func send(_ command: EngineCommand) async throws -> Data {
            switch HomebrewCommand(rawValue: command.name) {
            case .status:
                return try JSONEncoder().encode(
                    BrewStatus(installed: true, brewPath: "/opt/fixture/bin/brew"))
            case .listInstalled:
                // `refreshDoctor` judges a fix against what is on this Mac —
                // a name not in the Cellar reads `.copyOnly`, and then the row
                // draws one button and there is nothing to compare.
                return try JSONEncoder().encode(
                    [BrewPackage(name: "periphery", version: "3.5.1", isCask: false)])
            case .doctor:
                return try JSONEncoder().encode(
                    [TheDestructiveControlIsMarkedInInkTests.runnable])
            default:
                return Data("[]".utf8)
            }
        }
    }

    /// The colour a label is actually drawn in, and the colour of the fill under
    /// it, read off the pixels of one control.
    ///
    /// **The fill is the band's own most common pixel** — a bordered button is
    /// mostly its fill — and the label is the pixel furthest from it in
    /// luminance. Antialiasing means that pixel never quite reaches the token:
    /// `labelColor` is black and reads `#303030` at 13 pt. That is the same
    /// understatement for both labels, so a comparison between them is sound
    /// where an absolute reading against a specification is not, and the doc
    /// comment on `helmDestructive` carries the token arithmetic separately.
    private struct Sample {
        let fill: NSColor
        let ink: NSColor
        var contrast: Double { Self.ratio(Self.luminance(ink), Self.luminance(fill)) }
        var inkHex: String { Self.hex(ink) }
        var fillHex: String { Self.hex(fill) }

        static func luminance(_ colour: NSColor) -> Double {
            let srgb = colour.usingColorSpace(.sRGB) ?? colour
            func channel(_ value: CGFloat) -> Double {
                let v = Double(value)
                return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * channel(srgb.redComponent)
                 + 0.7152 * channel(srgb.greenComponent)
                 + 0.0722 * channel(srgb.blueComponent)
        }
        static func ratio(_ a: Double, _ b: Double) -> Double {
            (max(a, b) + 0.05) / (min(a, b) + 0.05)
        }
        static func hex(_ colour: NSColor) -> String {
            let srgb = colour.usingColorSpace(.sRGB) ?? colour
            return String(format: "#%02X%02X%02X",
                          Int((srgb.redComponent * 255).rounded()),
                          Int((srgb.greenComponent * 255).rounded()),
                          Int((srgb.blueComponent * 255).rounded()))
        }
    }

    private func sample(_ host: NSView, _ frame: CGRect) -> Sample? {
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return nil }
        host.cacheDisplay(in: host.bounds, to: rep)
        let scale = max(1, rep.pixelsHigh / max(1, Int(host.bounds.height)))
        let x0 = Int(frame.minX) * scale, x1 = Int(frame.maxX) * scale
        let y0 = Int(frame.minY) * scale, y1 = Int(frame.maxY) * scale
        guard x0 >= 0, y0 >= 0, x1 <= rep.pixelsWide, y1 <= rep.pixelsHigh, x1 > x0, y1 > y0
        else { return nil }
        var counts: [String: Int] = [:]
        var colours: [String: NSColor] = [:]
        for y in y0..<y1 {
            for x in x0..<x1 {
                guard let pixel = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                let key = Sample.hex(pixel)
                counts[key, default: 0] += 1
                colours[key] = pixel
            }
        }
        // Ties broken by value, so two readings of one drawing agree.
        guard let modal = counts.max(by: { ($0.value, $0.key) < ($1.value, $1.key) })?.key,
              let fill = colours[modal] else { return nil }
        let ground = Sample.luminance(fill)
        var ink = fill
        var furthest = 0.0
        for y in y0..<y1 {
            for x in x0..<x1 {
                guard let pixel = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                let distance = abs(Sample.luminance(pixel) - ground)
                if distance > furthest { furthest = distance; ink = pixel }
            }
        }
        return Sample(fill: fill, ink: ink)
    }

    /// **The claim, in both appearances.** Light first, deliberately:
    /// `RenderedInk.bothAppearances` carries the reason — the appearance a Mac
    /// happens to be in at this hour is not a reading of anything.
    func testTheTwoButtonsInTheFixRowAreNotDrawnInOneInk() async {
        for appearance in RenderedInk.bothAppearances {
            let screen = RenderedInk.label(of: appearance)
            let transport = OneRunnableFinding()
            let mvm = ModuleViewModel(transport: transport)
            let hb = HomebrewViewModel.shared(vm: mvm)
            await hb.loadIfNeeded()
            hb.segment = .health
            await hb.refreshDoctor()
            XCTAssertEqual(hb.issues.count, 1, "\(screen): precondition: one finding to select")
            hb.select(hb.issues.first?.id)

            let mount = MountedRender(HomebrewSettingsPage(vm: mvm),
                                      width: 984, height: 700, appearance: appearance)
            // **The window's own colour, put on the host's layer.** A bench
            // window paints nothing where the page paints nothing, and
            // `cacheDisplay` hands back a premultiplied bitmap — so every pixel
            // of a transparent view reads `#000000` whatever was drawn on it,
            // which is `RenderedInk`'s own lesson about colour mass and the
            // reason its readings are departures from a ground rather than
            // brightnesses. A colour is what this test is about, so the ground
            // has to be the one a person sees.
            mount.host.wantsLayer = true
            NSAppearance(named: appearance)?.performAsCurrentDrawingAppearance {
                mount.host.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
            }
            mount.settle(30)
            // The fix row's two buttons: the only two focus rings in the
            // inspector's column, side by side on one row. The segment bar draws
            // one of its own wherever the pane takes the menu shape, which is
            // why the reading is banded below the bar.
            let buttons = mount.host.everyView(named: "_FocusRingView")
                .map { $0.convert($0.bounds, to: mount.host) }
                .filter { $0.minY >= 48 && $0.minX > 400 }
                .sorted { $0.minX < $1.minX }
            XCTAssertEqual(buttons.count, 2, """
                \(screen): \(buttons.count) control(s) in the inspector where the fix row draws \
                Copy and Run — nothing below is a reading of either button
                """)
            guard buttons.count == 2 else { mount.drop(); continue }

            let copy = sample(mount.host, buttons[0])
            let run = sample(mount.host, buttons[1])
            mount.drop()
            withExtendedLifetime(transport) {}

            XCTAssertNotNil(copy, "\(screen): Copy could not be read")
            XCTAssertNotNil(run, "\(screen): Run could not be read")
            guard let copy, let run else { continue }

            // Both were drawn: a button holding nothing but its own fill reads
            // as ink equal to fill, and "the two differ" would then be a reading
            // of an empty rectangle.
            XCTAssertGreaterThan(copy.contrast, 3, """
                \(screen): Copy's label reads \(copy.inkHex) on \(copy.fillHex), \
                \(copy.contrast):1 — there is no label there to compare against
                """)
            XCTAssertGreaterThan(run.contrast, 2, """
                \(screen): Run's label reads \(run.inkHex) on \(run.fillHex), \
                \(run.contrast):1 — the mark has been applied by making the word disappear
                """)

            XCTAssertNotEqual(run.inkHex, copy.inkHex, """
                \(screen): «Run» and «Copy» sample the same ink, \(run.inkHex) — the button \
                that deletes a package is drawn exactly like the one that copies a string, \
                and the role it carries is visible only in the source
                """)

            // And the marked one is the destructive one: Copy still draws in
            // the page's ordinary label ink, which is grey by the channel and
            // never red.
            let copyChannels = copy.ink.usingColorSpace(.sRGB)!
            XCTAssertLessThan(abs(copyChannels.redComponent - copyChannels.greenComponent), 0.08, """
                \(screen): «Copy» is drawn in \(copy.inkHex), which is not the ordinary label \
                ink — both buttons have been marked, so the mark says nothing
                """)
            let runChannels = run.ink.usingColorSpace(.sRGB)!
            XCTAssertGreaterThan(runChannels.redComponent - runChannels.greenComponent, 0.15, """
                \(screen): «Run» is drawn in \(run.inkHex), which carries no more red than \
                green — whatever marks it, it is not the signal palette's danger
                """)
        }
    }
}
