import XCTest
import SwiftUI
import AppKit
@testable import HelmApp
@testable import HelmUI

/// `PanelGrid.roomForGrid` against the shape it is arithmetic about.
///
/// The arithmetic subtracts a number of gaps, and which number is a fact about
/// SwiftUI rather than about Helm: a stack spends its spacing on every child it
/// has, including one that draws nothing. The card was written knowing that —
/// the tab strip is wrapped in an `if` for exactly this reason — and the
/// arithmetic was written not knowing it, so the default panel (one tab, no
/// strip) reserved a gap under a bar nobody draws and lost 8 pt of grid.
///
/// So this measures the card's own sandwich in all four states and asks the
/// arithmetic what the middle block gets. Every rule about the term is here as
/// a subtraction from something AppKit reported, not as the formula spelled a
/// second time.
@MainActor
final class PanelCardGapsProbe: XCTestCase {

    /// The middle block's height. Above `PanelGrid.minimumGrid`, or every case
    /// answers the floor and the term under test is never reached — which is
    /// how this probe first passed on all four shapes at once.
    private static let grid: CGFloat = 200
    private static let strip: CGFloat = 30
    private static let foot: CGFloat = 38

    /// The card in `HelmPanel.card`: a conditional tab strip, the scroll view,
    /// and a footer block that is always there and often empty.
    private struct Card: View {
        let strip: Bool
        let footer: Bool

        var body: some View {
            VStack(alignment: .leading, spacing: PanelGrid.gap) {
                if strip { Color.gray.frame(height: PanelCardGapsProbe.strip) }
                Color.gray.frame(height: PanelCardGapsProbe.grid)
                VStack(alignment: .leading, spacing: PanelGrid.gap) {
                    if footer { Color.gray.frame(height: PanelCardGapsProbe.foot) }
                }
            }
            .padding(PanelGrid.padding)
        }
    }

    private func drawn(strip: Bool, footer: Bool) -> CGFloat {
        NSHostingController(rootView: Card(strip: strip, footer: footer))
            .sizeThatFits(in: CGSize(width: helmPanelWidth,
                                     height: CGFloat.greatestFiniteMagnitude)).height
    }

    /// The one that pins the whole term: give the arithmetic a strip exactly as
    /// tall as the card AppKit drew, and it must hand the grid back exactly the
    /// middle block — in every state of the two bars. A card that fits its strip
    /// and a grid that has to scroll inside it are the same defect.
    func testTheArithmeticLeavesTheGridWhatTheCardDoesInEveryState() {
        for strip in [false, true] {
            for footer in [false, true] {
                let card = drawn(strip: strip, footer: footer)
                let room = PanelGrid.roomForGrid(
                    strip: card,
                    top: strip ? Self.strip : nil,
                    foot: footer ? Self.foot : nil)
                XCTAssertEqual(room, Self.grid,
                               "strip \(strip), footer \(footer): a \(card) pt card left \(room) pt")
            }
        }
    }

    /// The premise, on its own, so a failure above says which half moved: the
    /// footer block is drawn empty and the stack still spends its spacing on it.
    func testAnEmptyFooterBlockStillCostsItsGap() {
        XCTAssertEqual(drawn(strip: false, footer: false),
                       PanelGrid.padding * 2 + Self.grid + PanelGrid.gap)
    }

    /// And the other half: the strip is wrapped in an `if`, so it takes its gap
    /// away with it rather than leaving one behind.
    func testTheStripTakesItsGapWithIt() {
        XCTAssertEqual(drawn(strip: true, footer: true) - drawn(strip: false, footer: true),
                       Self.strip + PanelGrid.gap)
    }
}
