import AppKit
import HelmContract
import HelmRuntime
import HelmTestSupport
import HelmUI
import SwiftUI
import XCTest
import Module_Leftovers_Engine
@testable import Module_Leftovers_UI

/// **The sentence took the row, and the verb beside it was paid for it.**
///
/// Without Full Disk Access this page draws `HelmPermissionNote`, and its
/// sentence is the longest any caller hands that note. Photographed in Russian at
/// the default window, the sentence wrapped to two lines and «Выдать…» came out a
/// sliver at the right edge — unreadable, and too narrow to press with any
/// confidence. `HelmBanner` gave the words `layoutPriority(1)` so a spacer could
/// not make them wrap, and gave the action nothing, so an `HStack` short of room
/// compressed the one element that has no business being compressed.
///
/// Measured off the render, in all eight languages, at the narrowest pane the
/// window allows, a middle one and the default: a button's frame is the only
/// honest answer to «how wide was it drawn», against the same control mounted
/// alone. `TheToolbarKeepsItsVerbTests` is the same defect one strip up.
@MainActor
final class TheGrantButtonKeepsItsWordsTests: XCTestCase {

    /// The narrowest pane, a middle one and the default window's — the same three
    /// `TheToolbarKeepsItsVerbTests` reads.
    private static let widths: [CGFloat] = [606, 720, 845]

    private static let denied = HelmGrants(accessibility: .granted, fullDisk: .denied)

    private var previous: AppLanguage?

    override func setUp() {
        super.setUp()
        previous = AppLanguage.override
    }

    override func tearDown() {
        AppLanguage.override = previous
        super.tearDown()
    }

    /// The Grant button as the page draws it: the first screen, before a scan, so
    /// the note is the only thing above the invitation and its button the topmost
    /// control on the page.
    private func drawnGrant(_ language: AppLanguage, width: CGFloat) async -> CGRect? {
        let (mount, _) = await LeftoversPageRender.page([], language: language, width: width,
                                                        height: 620, appearance: .aqua,
                                                        scanned: false, grants: Self.denied)
        defer { mount.drop() }
        mount.settle(20)
        return LeftoversPageRender.controls(in: mount).min { $0.minY < $1.minY }
    }

    func testTheGrantButtonIsNeverDrawnNarrowerThanItsOwnWords() async throws {
        var offenders: [String] = []
        for language in AppLanguage.allCases {
            AppLanguage.override = language
            let natural = LeftoversPageRender.naturalWidth(of: HelmPermissionNote.grantLabel,
                                                           prominent: false, appearance: .aqua,
                                                           controlSize: .small)
            XCTAssertGreaterThan(natural, 0, "precondition: the button was measured on its own")
            for width in Self.widths {
                let drawn = await drawnGrant(language, width: width)
                guard let drawn else {
                    offenders.append("  \(language.rawValue) at \(Int(width)): no button drawn")
                    continue
                }
                // The note's own edge: the button is the last thing in the row,
                // so a frame found anywhere else is some other control.
                XCTAssertGreaterThan(drawn.maxX, width / 2, """
                    \(language.rawValue) at \(width): the topmost control is not at the right of \
                    the row, so this is not the note's button
                    """)
                if drawn.width < natural - 0.5 {
                    offenders.append("  \(language.rawValue) at \(Int(width)): «\(HelmPermissionNote.grantLabel)» "
                                     + "drawn \(drawn.width) pt where it needs \(natural)")
                }
            }
        }
        XCTAssertTrue(offenders.isEmpty, """
            the permission note's button is squeezed by its sentence, so the one way off this \
            screen cannot be read or reliably pressed:
            \(offenders.joined(separator: "\n"))
            """)
    }
}
