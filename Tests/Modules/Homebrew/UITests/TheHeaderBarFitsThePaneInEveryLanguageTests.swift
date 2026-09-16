import XCTest
import AppKit
import SwiftUI
import HelmContract
import HelmTestSupport
import HelmUI
@testable import Module_Homebrew_Engine
@testable import Module_Homebrew_UI

/// **Everything on the segment bar, inside the pane, in all eight languages —
/// at the narrowest pane a person can open.**
///
/// The switcher is `.fixedSize()`, so it is as wide as the language makes it:
/// measured 2026-09-16, zh 252 · en 302 · de 320 · fr 388 · pt 404 · es 476 ·
/// ru 488 · ja 494 pt, with the bar needing `picker + 65.5` before «Обновить всё»
/// took its reserved slot beside Refresh (`upgradeAll`). The narrowest pane
/// is **540** — `max(detailItem.minimumThickness, minSize.width −
/// sidebarMaximum)` from `SettingsWindow.swift` — and at 540 in Russian the
/// picker sat at x = 7.5 where the page's inset is 20, with Refresh drawn 13 pt
/// past the pane's own edge. Nothing reported anything: SwiftUI centres what
/// does not fit and draws it anyway.
///
/// **Parameterised by language and not by luck.** A width check run in one
/// language proves nothing about the other seven, and this Mac runs in Russian,
/// so the very case that fails is the one a bare assertion might have picked —
/// or missed. `AppLanguage.each` puts the app back afterwards, which a
/// hand-rolled loop does not when a body fails mid-way.
@MainActor
final class TheHeaderBarFitsThePaneInEveryLanguageTests: XCTestCase {

    /// 540. `SettingsWindow.swift` carries the three numbers behind it —
    /// `detailItem.minimumThickness` 420, `minSize.width` 860 and
    /// `sidebarMaximum` 320 — and a person reaches it by dragging the window to
    /// its own minimum with the sidebar at its widest.
    private static let narrowestPane: CGFloat = 540
    /// The pane the app draws on this Mac, measured 2026-09-15.
    private static let usualPane: CGFloat = 984
    /// Narrower than **any** language's segments — Chinese's are the smallest at
    /// 252 pt and need a 317.5 pt pane. Not a width the window allows: the claim
    /// it carries is that the exchange is a thing this layout really does in all
    /// eight languages, where at the reachable 540 only Spanish, Russian and
    /// Japanese need it. 420 was the first choice and proved nothing — Chinese,
    /// English and German still fit their segments there.
    private static let belowEverySegments: CGFloat = 300

    /// Says brew is here and answers nothing else: the bar draws whatever the
    /// lists do.
    private final class BrewIsHere: EngineTransport, @unchecked Sendable {
        private let stream = AsyncStream<EngineEvent>.makeStream()
        var events: AsyncStream<EngineEvent> { stream.stream }
        func send(_ command: EngineCommand) async throws -> Data {
            switch HomebrewCommand(rawValue: command.name) {
            case .status:
                return try JSONEncoder().encode(
                    BrewStatus(installed: true, brewPath: "/opt/fixture/bin/brew"))
            case .listInstalled:
                return try JSONEncoder().encode([BrewPackage]())
            default:
                return Data()
            }
        }
    }

    private struct Bar {
        /// The segmented control, when that is the shape the bar took. Absent
        /// means the menu was chosen — which is an answer and not a failure.
        let segments: CGRect?
        /// Every control drawn in the bar's own band, whichever shape it is:
        /// the picker and the Refresh glyph.
        let controls: [CGRect]
    }

    /// What the bar drew, in the pane's own coordinates.
    ///
    /// The band is the top of the page, above the first `Divider()`: the bar is
    /// `HelmSpace.s5` of padding around a 24 pt control, so 48 pt covers it and
    /// stops short of the list below.
    private func bar(at width: CGFloat) -> Bar {
        let transport = BrewIsHere()
        let mvm = ModuleViewModel(transport: transport)
        let mount = MountedRender(HomebrewSettingsPage(vm: mvm),
                                  width: width, height: 420, appearance: .aqua)
        mount.settle(12)
        let band: CGFloat = 48
        func frames(_ named: [String]) -> [CGRect] {
            mount.host.everyView
                .filter { named.contains($0.appKitClassName) }
                .map { $0.convert($0.bounds, to: mount.host) }
                .filter { $0.maxY <= band && $0.width > 0.5 }
        }
        // `SwiftUISegmentedControl` is the segmented picker and `_FocusRingView`
        // is the menu one — SwiftUI's own classes, matched as text because the
        // SDK exports no symbol for either (`ViewTree`'s own reason).
        // `SwiftUIAppKitButton` is the Refresh glyph.
        let segments = frames(["SwiftUISegmentedControl"])
        let controls = frames(["SwiftUISegmentedControl", "_FocusRingView", "SwiftUIAppKitButton"])
        mount.drop()
        withExtendedLifetime(transport) {}
        return Bar(segments: segments.first, controls: controls)
    }

    /// **The claim.** At the narrowest pane, in every language, nothing on the
    /// bar is outside the page's own inset — least of all Refresh, which is the
    /// only way to reload a list that refused.
    func testTheWholeBarIsInsideTheNarrowestPaneInEveryLanguage() {
        AppLanguage.each { language in
            let reading = bar(at: Self.narrowestPane)

            XCTAssertGreaterThanOrEqual(reading.controls.count, 2, """
                \(language.rawValue): \(reading.controls.count) control(s) found in the bar's \
                band at \(Self.narrowestPane) pt, where the bar draws a picker and Refresh — \
                the assertions below are not measurements of anything
                """)
            for frame in reading.controls {
                XCTAssertGreaterThanOrEqual(frame.minX, HelmLayout.formInset - 0.5, """
                    \(language.rawValue): a control on the bar begins at x = \(frame.minX) in a \
                    \(Self.narrowestPane) pt pane, where the page's inset is \
                    \(HelmLayout.formInset) — it has walked into the gutter, and at a hundred \
                    points narrower the first segment is cut off entirely
                    """)
                XCTAssertLessThanOrEqual(frame.maxX, Self.narrowestPane - HelmLayout.formInset + 0.5, """
                    \(language.rawValue): a control on the bar ends at x = \(frame.maxX) in a \
                    \(Self.narrowestPane) pt pane inset by \(HelmLayout.formInset) — past the \
                    edge, which for Refresh means the list cannot be reloaded at all
                    """)
            }
        }
    }

    /// **And the wide pane still draws the segmented control.** Without this
    /// the test above passes over a page that answered the width problem by
    /// deleting the switcher — a fallback taken everywhere is not a fallback.
    func testTheSegmentedSwitcherIsWhatAWidePaneDraws() {
        AppLanguage.each { language in
            let reading = bar(at: Self.usualPane)
            XCTAssertNotNil(reading.segments, """
                \(language.rawValue): the bar drew the compact switcher at \(Self.usualPane) pt, \
                where the segmented one fits in every language — the approved drawing is gone \
                from the pane the app actually opens
                """)
        }
    }

    /// **And the fallback is reachable in every language**, so the shape is one
    /// the layout really can take rather than a branch three languages compile.
    /// Below any width the window allows, because that is where the claim is
    /// about all eight rather than about today's font metrics.
    func testEveryLanguageFallsBackWhereTheSegmentsCannotFit() {
        AppLanguage.each { language in
            let reading = bar(at: Self.belowEverySegments)
            XCTAssertNil(reading.segments, """
                \(language.rawValue): the segmented switcher is still what is drawn at \
                \(Self.belowEverySegments) pt, where its own segments do not fit — so it is \
                being drawn outside the pane rather than exchanged for the control that fits
                """)
            for frame in reading.controls {
                XCTAssertLessThanOrEqual(frame.maxX,
                                         Self.belowEverySegments - HelmLayout.formInset + 0.5,
                                         "\(language.rawValue): a control ends at x = \(frame.maxX)")
            }
        }
    }
}
