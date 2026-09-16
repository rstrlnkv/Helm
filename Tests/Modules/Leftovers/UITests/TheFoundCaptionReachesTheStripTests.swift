import AppKit
import HelmContract
import HelmRuntime
import HelmTestSupport
import HelmUI
import SwiftUI
import XCTest
import Module_Leftovers_Engine
@testable import Module_Leftovers_UI

/// **«Not checked: N» reaches the screen beside «Found: N».**
///
/// The rows it counts are the ones the default filter hides, so this strip is
/// the only place the number can be read.
///
/// This file held two more cases about the same strip when it also carried the
/// filter and Scan: that Scan was never drawn narrower than its words — at
/// 606 pt a third fixed-width caption had squeezed «Сканировать заново» to
/// 20.5 pt against the 154.0 it needs — and that a caption stepped aside where
/// the strip could not hold both. Scan and the filter moved into the settings
/// window's toolbar (2026-09-16), which lays out and overflows its own items,
/// so the strip holds the captions alone and there is nothing left in it for a
/// caption to squeeze. What remains is the half that still describes the page.
@MainActor
final class TheFoundCaptionReachesTheStripTests: XCTestCase {

    /// The strip, in points from the top of the page: 48 pt of controls and the
    /// hairline under them.
    private static let strip = 0...47

    private var previous: AppLanguage?

    override func setUp() {
        super.setUp()
        previous = AppLanguage.override
    }

    override func tearDown() {
        AppLanguage.override = previous
        super.tearDown()
    }

    private static func agent(_ name: String, _ status: ItemStatus) -> StaleItem {
        StaleItem(path: "\(NSHomeDirectory())/Library/LaunchAgents/\(name).plist",
                  identifier: name, kind: .launchAgent, sizeBytes: 4_096, status: status)
    }

    /// One leftover to keep the list drawn, and `unchecked` rows the scan could
    /// not judge — which are never in the list, being neither `.orphaned` nor
    /// anything else the filter keeps.
    private static func items(unchecked: Int) -> [StaleItem] {
        [agent("com.vendor.gone", .orphaned)]
        + (0..<unchecked).map { agent("com.vendor.u\($0)", .undetermined) }
    }

    private func toolbar(_ language: AppLanguage, width: CGFloat, unchecked: Int)
    async -> (scan: CGRect?, ink: Int) {
        AppLanguage.override = language
        let (mount, model) = await LeftoversPageRender.page(Self.items(unchecked: unchecked),
                                                            language: language, width: width,
                                                            height: 620, appearance: .aqua)
        defer { mount.drop() }
        mount.settle(20)
        XCTAssertEqual(model.uncheckedCount, unchecked, "precondition: the scan carried them")
        let controls = LeftoversPageRender.controls(in: mount).filter { $0.minY < 90 }
        return (controls.max { $0.minX < $1.minX }, mount.ink(Self.strip) ?? 0)
    }

    /// And the caption is drawn where there is room for it — without this the
    /// check above passes with the caption deleted, which is the arrangement it
    /// is supposed to be making room for.
    func testTheCaptionIsDrawnWhereTheStripCanHoldIt() async {
        for language in [AppLanguage.en, .ru] {
            let without = await toolbar(language, width: 845, unchecked: 0).ink
            let with = await toolbar(language, width: 845, unchecked: 3).ink
            XCTAssertGreaterThan(with, without, """
                \(language.rawValue) at 845 pt: the strip draws no more than it did without a \
                single unjudged row, so «\(LfStr.uncheckedLine(3))» is not on the screen at all.
                """)
        }
    }
}
