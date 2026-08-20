// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import Foundation
import HelmTestSupport
import XCTest

/// **Four readings are four VoiceOver stops, not twelve.**
///
/// Each card in the hero's row draws three `Text`s — «Скорость», «343», «incy ·
/// utun8» — and left alone SwiftUI makes each of them an element of its own. So
/// a person moving through the row by keyboard or by swipe hears twelve things
/// where the page shows four, and hears the caption *after* the figure it
/// captions in three of them. `HelmMetricStrip` decided this one file over —
/// «one VoiceOver stop, not two in value-then-label order» — and the hero's own
/// readings, drawn in the same card shape for the same reason, did not follow.
///
/// **Read off the source, and that is not a shortcut.** The in-process
/// accessibility tree cannot answer it: `NSHostingView.accessibilityChildren()`
/// comes back as one `AXGroup` with nothing under it, which
/// `TheStripDrawsOnlyWhatIsKnownTests` and `TheSwitcherDrawsTheTunnelYouChoseTests`
/// both record, and a probe run against this very question on 2026-08-20 —
/// two identical stacks, one combined and one not, as a control — read
/// *identically*. A reading that cannot tell the fix from the defect is an
/// instrument, not an answer.
///
/// So the promise is held to the line that makes it, with the shape asserted
/// beside it: if the card stops being three stacked `Text`s the assertion below
/// says so instead of passing, because a card rebuilt some other way is a
/// decision to re-make rather than a check to inherit.
final class TheReadingsAreFourStopsTests: XCTestCase {

    private static let hero = "Sources/Modules/VPN/UI/VPNTunnelHero.swift"

    // MARK: - The promise

    func testAReadingIsOneStop() throws {
        let body = try body(of: "private func column(", in: Self.hero)

        XCTAssertTrue(body.contains(".accessibilityElement(children: .combine)"), """
            the hero's reading card draws its label, its figure and its note as three \
            separate `Text`s with nothing combining them, so the four cards are twelve \
            VoiceOver stops and three of them read the figure before the word that names \
            it. `HelmMetricStrip` combines its two for exactly this reason.
            \(body)
            """)
    }

    /// And it is still the card that promise is about.
    func testTheCardIsStillThreeStackedTexts() throws {
        let body = try body(of: "private func column(", in: Self.hero)
        let drawn = body.components(separatedBy: "Text(").count - 1

        XCTAssertEqual(drawn, 3, """
            the reading card no longer draws three `Text`s — it draws \(drawn). The rule \
            above is about a label, a figure and a note read as one sentence; a card built \
            some other way needs that decision made again rather than inherited
            """)
    }

    // MARK: - The rule can still fail

    /// The shape the card had, past the same reading — otherwise the day the
    /// tree is clean is the day this stops being able to fail at all.
    func testTheRuleRecognisesACardOfLooseTexts() {
        let loose = """
            private func column(_ tile: VPNTunnelStrip.Tile) -> some View {
                VStack(alignment: .leading, spacing: HelmSpace.s3) {
                    Text(tile.label)
                    Text(tile.value)
                    Text(tile.note)
                }
                .padding(HelmSpace.s5)
            }
            """
        let combined = loose.replacingOccurrences(
            of: "    .padding(HelmSpace.s5)",
            with: "    .accessibilityElement(children: .combine)\n    .padding(HelmSpace.s5)")

        XCTAssertFalse(Self.block(from: loose).contains(".accessibilityElement(children: .combine)"),
                       "the reading cannot see the shape it was written from")
        XCTAssertTrue(Self.block(from: combined).contains(".accessibilityElement(children: .combine)"),
                      "the reading cannot see the fix either, so it reports every card for ever")
    }

    /// **Comments are stripped.** This file explains its own cards at length,
    /// and the paragraph above quotes the modifier it asks for — a reading that
    /// took comments would be satisfied by an explanation.
    func testAModifierNamedOnlyInACommentDoesNotCount() {
        let explained = """
            private func column(_ tile: VPNTunnelStrip.Tile) -> some View {
                // One stop, not three: .accessibilityElement(children: .combine)
                VStack { Text(tile.label) }
            }
            """

        XCTAssertFalse(Self.block(from: explained).contains(".accessibilityElement(children: .combine)"),
                       "the reading is taking comments, so a promise in prose passes for the fix")
    }

    // MARK: - Reading the source

    /// The body of the declaration opening with `opening`, comments stripped.
    ///
    /// Unwrapped rather than defaulted: a file that has moved, or a function
    /// that has been renamed, must fail here — an empty string would satisfy
    /// nothing above and would read as «the card is gone», which is a different
    /// report from «the scan lost the file».
    private func body(of opening: String, in file: String) throws -> String {
        let lines = try RepoSource.lines(of: file)
        let start = try XCTUnwrap(lines.firstIndex { RepoSource.code($0).contains(opening) },
                                  "no declaration opening `\(opening)` in \(file)")
        return Self.block(from: lines[start...].joined(separator: "\n"))
    }

    /// From the first line to the brace it closes.
    private static func block(from source: String) -> String {
        var text = ""
        var depth = 0
        for raw in source.components(separatedBy: "\n") {
            let code = RepoSource.code(raw)
            text += code + "\n"
            depth += code.filter { $0 == "{" }.count - code.filter { $0 == "}" }.count
            if depth <= 0 && text.contains("{") { break }
        }
        return text
    }
}
