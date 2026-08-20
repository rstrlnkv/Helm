import AppKit
import HelmTestSupport
import HelmUI
import SwiftUI
import XCTest
@testable import HelmApp

/// **The two changes a reader can see that only a drawing can settle.**
///
/// Each starts by asserting the subject drew at all: an assertion about an
/// absence — no names in a tab, no plate under a glyph — passes when the window
/// server drew nothing.
///
/// **What is deliberately not here** is a count of the switches in the settings
/// page's panel section. The first version of this file drew a *copy* of that
/// section and counted one switch in it, which is a check on the copy: the page
/// could grow a second switch tomorrow and this would stay green. What holds the
/// fold is `OneSwitchAnswersForThreeTests`, which is about the migration, and
/// the compiler — `AppSettings.showSettingsButton` and its two siblings do not
/// exist, so a second switch cannot be written against them. The caption under
/// it is held by `NoOrphanTranslationsTests`, which fails on a translation
/// nothing in the source asks for.
@MainActor
final class WhatThePanelSectionDrawsTests: XCTestCase {

    // MARK: - A tab strip that measures itself

    /// Names the panel has room for stay names; the same strip with names it
    /// has no room for is drawn as glyphs and fits.
    ///
    /// **Measured with the production font**, which the unit test around
    /// `TabStripFit` deliberately does not use: it passes a fixed width per
    /// character so its assertions are about the arithmetic. What that leaves
    /// open is whether the arithmetic lands anywhere near a real strip, and this
    /// is where that is asked.
    func testALongNamedStripIsDrawnAsGlyphsAndFits() {
        let names = ["Everything I keep an eye on daily",
                     "The other things I check less often"]
        let available = helmPanelWidth - PanelGrid.padding * 2
        XCTAssertEqual(TabStripFit.style(tabs: [("Main", "star"), ("Disk", "gear")],
                                         editing: false, available: available), .text,
                       "two short names do not fit the panel, measured at the strip's own font")
        XCTAssertEqual(TabStripFit.style(tabs: [(names[0], "star"), (names[1], "gear")],
                                         editing: false, available: available), .glyph,
                       "two names of \(names.map(\.count)) characters fit a 296 pt strip")

        let long = strip(names: names)
        XCTAssertGreaterThan(long.layers.count, 3,
                             "the strip drew \(long.layers.count) layers, so measuring what it "
                             + "fits into is measuring an empty bitmap")
        let widest = long.layers.map(\.frame.width).max() ?? 0
        XCTAssertLessThanOrEqual(widest, helmPanelWidth, """
            the widest thing the strip drew is \(widest) pt against a \(helmPanelWidth) pt panel, \
            so it is still setting names it has no room for.
            """)
    }

    // MARK: - Plain module icons, in the panel too

    /// The plate under `.plain` is a glyph and no plate: no rounded background
    /// layer, and nothing macOS could confuse for one.
    func testAPlainModuleIconHasNoPlateBehindIt() {
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            let coloured = plate(.colour, appearance)
            let plain = plate(.plain, appearance)
            XCTAssertGreaterThan(coloured.layers.count, 1,
                                 "the coloured plate drew \(coloured.layers.count) layers")
            XCTAssertGreaterThan(plain.layers.count, 0,
                                 "the plain glyph drew nothing at all")
            XCTAssertLessThan(plain.layers.count, coloured.layers.count, """
                a plain module icon draws \(plain.layers.count) layers in \(appearance.rawValue) \
                and a coloured one \(coloured.layers.count) — the plate and its shadow are still \
                there, so the setting still does not reach whatever asked for this icon.
                """)
        }
    }

    // MARK: - Benches

    private func plate(_ style: SidebarStyle,
                       _ appearance: NSAppearance.Name) -> ModulePageRender.Shell {
        ModulePageRender.drawn(
            HelmIconPlate(symbol: "internaldrive", tint: .blue, size: 26)
                .environment(\.helmModuleIconStyle, style),
            in: appearance, width: 60, height: 60)
    }

    private func strip(names: [String]) -> ModulePageRender.Shell {
        ModulePageRender.drawn(TabStripProbe(names: names), in: .aqua,
                               width: helmPanelWidth, height: 60)
    }
}

/// The real strip, over a layout built here — the names are the whole variable.
private struct TabStripProbe: View {
    let names: [String]
    @Namespace private var selection
    @State private var activeTab = 0
    @State private var picking: String?

    private var layout: PanelLayout {
        PanelLayout(tabs: names.enumerated().map { index, name in
            PanelLayout.Tab(id: "tab.\(index)", name: name, widgets: [],
                            glyph: PanelLayout.Tab.glyphs[index])
        })
    }

    var body: some View {
        PanelTabStrip(layout: layout, tabIndex: 0, editing: false, selection: selection,
                      activeTab: $activeTab, pickingGlyph: $picking,
                      rename: { _, _ in }, apply: { _ in })
    }
}
