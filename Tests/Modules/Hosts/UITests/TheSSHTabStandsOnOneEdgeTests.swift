import AppKit
import HelmContract
import HelmRuntime
import HelmTestSupport
import HelmUI
import SwiftUI
import XCTest
@testable import Module_Hosts_Engine
@testable import Module_Hosts_UI

/// **Everything on the SSH tab stands on one left edge and one right edge,
/// whichever view it is in.**
///
/// The text box is a console and sits where the Homebrew console sits
/// (`HostsSettingsPage.textBoxMargin`, 12 pt). Three things used to stand
/// somewhere else:
///
/// - the strip's note and buttons over it, in the page's 20 pt column, so
///   «Apply» ended 8 pt short of the box under it;
/// - the table's cards, in the same 20 pt column, so switching the view moved
///   the edge 8 pt right and 8 pt down;
/// - the «not writable» banner over the table, 6 pt under the toolbar and 26 pt
///   from the first card.
///
/// Every reading is off the drawing: the box and the cards are rounded layers,
/// the strip's extent is the pixels that differ from the page, the banner is the
/// topmost rounded layer that is not a card.
@MainActor
final class TheSSHTabStandsOnOneEdgeTests: XCTestCase {

    private var benches: [SSHStripBench] = []

    override func tearDown() async throws {
        await MainActor.run { benches.forEach { $0.drop() }; benches = [] }
    }

    /// A typed letter and a `known_hosts` that is not there: the strip has a
    /// note on its left and Revert and Apply on its right.
    private func typed(_ bench: SSHStripBench, _ what: String) throws {
        XCTAssertFalse(bench.hvm.knownHostsReadable, "\(what): precondition — known_hosts was readable")
        let tv = try XCTUnwrap(bench.textView)
        bench.mounted.window?.makeFirstResponder(tv)
        tv.insertText("# typed\n", replacementRange: NSRange(location: 0, length: 0))
        bench.mounted.settle(40)
        XCTAssertTrue(bench.hvm.sshHasUnsavedChanges, "\(what): precondition — the keystroke made no edit")
    }

    func testTheStripOverTheBoxStandsOnTheBoxEdges() async throws {
        for appearance in RenderedInk.bothAppearances {
            let what = RenderedInk.label(of: appearance)
            let bench = try await SSHStripBench(appearance, directory: scratchDirectory("hosts-edge-strip"), known: nil)
            benches.append(bench)
            try typed(bench, what)
            let box = try XCTUnwrap(bench.rounded(minHeight: 100).first, "\(what): no box drawn")
            let stripRows = Int(box.minY - HostsSettingsPage.textBoxMargin) - 2
            XCTAssertGreaterThan(stripRows, 10, "\(what): precondition — the strip is not open")
            let span = try XCTUnwrap(bench.inkSpan(rows: 0...stripRows), "\(what): nothing drawn in the strip")
            XCTAssertEqual(span.right, box.maxX, accuracy: 1.5,
                           "\(what): the strip's buttons end at \(span.right), the box under them at \(box.maxX)")
            XCTAssertEqual(span.left, box.minX, accuracy: 2.5,
                           "\(what): the strip's note starts at \(span.left), the box under it at \(box.minX)")
            bench.drop()
        }
    }

    func testTheTableStandsWhereTheBoxStandsAndSoDoesTheStripOverIt() async throws {
        for appearance in RenderedInk.bothAppearances {
            let what = RenderedInk.label(of: appearance)
            let bench = try await SSHStripBench(appearance, directory: scratchDirectory("hosts-edge-table"))
            benches.append(bench)
            let box = try XCTUnwrap(bench.rounded(minHeight: 100).first, "\(what): no box drawn")
            try bench.select(mode: "table")
            bench.mounted.settle(40)
            let card = try XCTUnwrap(bench.rounded().min { $0.minY < $1.minY }, "\(what): no card drawn")
            XCTAssertEqual(card.minX, box.minX, accuracy: 0.5, "\(what): the table's left edge is not the box's")
            XCTAssertEqual(card.maxX, box.maxX, accuracy: 0.5, "\(what): the table's right edge is not the box's")
            XCTAssertEqual(card.minY, box.minY, accuracy: 0.5, "\(what): the table's top is not the box's")

            // The same with the strip open, typed in the box and read in the table.
            try bench.select(mode: "text")
            bench.mounted.settle(10)
            let tv = try XCTUnwrap(bench.textView)
            bench.mounted.window?.makeFirstResponder(tv)
            tv.insertText("# typed\n", replacementRange: NSRange(location: 0, length: 0))
            bench.mounted.settle(40)
            XCTAssertTrue(bench.hvm.sshHasUnsavedChanges, "\(what): precondition — the keystroke made no edit")
            let openBox = try XCTUnwrap(bench.rounded(minHeight: 100).first)
            try bench.select(mode: "table")
            bench.mounted.settle(40)
            let openCard = try XCTUnwrap(bench.rounded().min { $0.minY < $1.minY })
            XCTAssertGreaterThan(openBox.minY, HostsSettingsPage.textBoxMargin + 10,
                                 "\(what): precondition — the strip did not open")
            XCTAssertEqual(openCard.minY, openBox.minY, accuracy: 0.5,
                           "\(what): under the strip the table's top is not the box's")
            let stripRows = Int(openCard.minY - HostsSettingsPage.textBoxMargin) - 2
            let span = try XCTUnwrap(bench.inkSpan(rows: 0...stripRows), "\(what): nothing drawn in the strip")
            XCTAssertEqual(span.right, openCard.maxX, accuracy: 1.5,
                           "\(what): over the table the strip's buttons end at \(span.right), the cards at \(openCard.maxX)")
            bench.drop()
        }
    }
}
