import XCTest
import AppKit
import SwiftUI
import HelmTestSupport
@testable import HelmUI

/// **The published design system is still this tree's.**
///
/// The design system is published outside the repository, where nothing in a
/// build can reach it, and it is a copy: forty-odd colours resolved in both
/// appearances, the two ladders, the layout metrics. A copy of values has one
/// failure mode and it is silent — the tree moves, the copy does not, and the
/// document goes on describing an app that has changed. Nobody notices, because
/// a design system is read by people who are *not* looking at the code.
///
/// So the tree keeps a record of exactly what it resolves to, and this compares
/// the two. What the record is *for* lives elsewhere; what it says is checked
/// here, which is the only half a build can hold.
///
/// **Resolved, not read.** Every value comes from the live type, in a named
/// appearance — `HelmSignal.warning` is one dynamic colour that answers for
/// itself, `HelmSurface.cardFill` is `Color.primary` at an opacity, and
/// `PaletteColor.red` is macOS's. Reading the source for `0.035` would pin the
/// literal and miss the two things that actually change what lands on screen:
/// `Color.primary` is `labelColor`, black or white at alpha 0.847 rather than
/// pure ink, and a system colour moves when macOS moves.
///
/// That second one is why `inks` is in the record beside the colours. A
/// difference there is this tree's — somebody edited an opacity. A difference in
/// `colours` with `inks` and the ladders unchanged came from the operating
/// system, and the fix is to regenerate the record rather than to argue with it.
///
/// Not covered, deliberately: the type styles, whose sizes follow the interface
/// text size and so are a fact about the Mac running the suite rather than about
/// Helm; `HelmWallpaper`'s stops, which are literals inside a view body and
/// reachable from nowhere; and contrast, which is
/// `SignalColourContrastTests`, `RecessedTextIsReadableTests` and
/// `ModuleTintTests` and is not restated here.
final class PublishedTokensAreTheTreesTests: XCTestCase {

    /// The record, by its path from the repository root. It is not a resource of
    /// any target: nothing in the app reads it, and a build that stopped without
    /// it would be a build held up by a document.
    private static let path = "Resources/DesignSystem/design-tokens.json"

    /// Set this to rewrite the record instead of checking it:
    ///
    /// ```bash
    /// HELM_WRITE_DESIGN_TOKENS=1 bash Scripts/test.sh --filter PublishedTokensAreTheTrees
    /// ```
    ///
    /// The run **fails anyway**, whatever it wrote. A mode that rewrites the
    /// expectation and then reports success is a check that cannot fail, and the
    /// day somebody leaves the variable exported is the day this stops being a
    /// guard without saying so.
    private static let writeFlag = "HELM_WRITE_DESIGN_TOKENS"

    // MARK: - What the tree resolves to

    /// `#rrggbb` where the colour is opaque and `rgba(r, g, b, a)` where it is
    /// not, which is the distinction the published system is built on: every
    /// surface and every recessed ink is translucent, and spelling one as a hex
    /// would be publishing a colour the app never draws.
    private static func spelled(_ color: Color, _ appearance: NSAppearance.Name) -> String {
        var resolved = NSColor.clear
        NSAppearance(named: appearance)!.performAsCurrentDrawingAppearance {
            resolved = NSColor(color).usingColorSpace(.sRGB) ?? .clear
        }
        let r = Int((resolved.redComponent * 255).rounded())
        let g = Int((resolved.greenComponent * 255).rounded())
        let b = Int((resolved.blueComponent * 255).rounded())
        let a = resolved.alphaComponent
        if a >= 0.9995 { return String(format: "#%02x%02x%02x", r, g, b) }
        return "rgba(\(r), \(g), \(b), \(String(format: "%.3f", a)))"
    }

    private static func colours() -> [String: [String: String]] {
        var out: [String: [String: String]] = [:]
        func add(_ name: String, _ color: Color) {
            out[name] = ["light": spelled(color, .aqua), "dark": spelled(color, .darkAqua)]
        }

        add("ink", .primary)

        add("signal-warning", HelmSignal.warning(increased: false))
        add("signal-success", HelmSignal.success(increased: false))
        add("signal-danger", HelmSignal.danger(increased: false))

        add("surface-card", HelmSurface.cardFill)
        add("surface-well", HelmSurface.wellFill)
        add("surface-on-panel", HelmSurface.onPanelFill)
        add("surface-panel-card", HelmSurface.panelCardFill)
        add("hairline", HelmSurface.hairline)
        add("panel-selection", HelmSurface.panelSelection)

        add("text-quiet", HelmText.quiet)
        add("text-faint", HelmText.faint)
        add("mark-separator", HelmText.separator)

        // Every case, not `offered`: a retired colour is still reachable from a
        // setting stored before the set narrowed, so it is still published — and
        // dropping one from the type has to move this file.
        for tint in ModuleTint.allCases {
            add("tint-\(published(tint.rawValue))", tint.colour(increased: false))
        }
        for colour in PaletteColor.allCases {
            add("palette-\(published(colour.rawValue))", colour.color)
        }

        return out
    }

    /// The thirteen colours this tree defines itself, as they are under Increase
    /// Contrast.
    ///
    /// A separate table rather than a fourth and fifth entry per token, because
    /// the two sets answer to different floors — white clears 3:1 on a tint and
    /// 4,5:1 on its increased form, and a signal ink clears 4,5:1 and 7:1 — so
    /// reading them side by side would invite comparing numbers that are not
    /// comparable. The system colours have no row here: macOS supplies their
    /// increased variants, and this tree neither writes nor can read them.
    private static func increasedContrastColours() -> [String: [String: String]] {
        var out: [String: [String: String]] = [:]
        func add(_ name: String, _ color: Color) {
            out[name] = ["light": spelled(color, .aqua), "dark": spelled(color, .darkAqua)]
        }
        add("signal-warning", HelmSignal.warning(increased: true))
        add("signal-success", HelmSignal.success(increased: true))
        add("signal-danger", HelmSignal.danger(increased: true))
        for tint in ModuleTint.allCases {
            add("tint-\(published(tint.rawValue))", tint.colour(increased: true))
        }
        return out
    }

    /// A case name as the published system spells it: `keepAwake` → `keep-awake`.
    ///
    /// The record could as easily carry the raw case name, and did — which left
    /// one token in the whole set whose two spellings had to be reconciled by
    /// eye, on exactly the comparison this file exists to make mechanical. The
    /// tree's name is still the one a reader recognises, because only the word
    /// boundary moves.
    private static func published(_ rawValue: String) -> String {
        var out = ""
        for character in rawValue {
            if character.isUppercase {
                out.append("-")
                out.append(Character(character.lowercased()))
            } else {
                out.append(character)
            }
        }
        return out
    }

    /// The opacities this tree chose, beside the colours they produce. This is
    /// the half a person edits, and it is the half that says whose edit it was.
    ///
    /// **Read back, not restated.** These nine numbers were a literal table here
    /// first, and the mutation that proved this guard showed what that is worth:
    /// `cardFill` moved from 0.035 to 0.04, the check went red on the right
    /// token — and told the reader macOS had done it, because a hand-written
    /// table cannot move when the tree does. A number spelled twice reports on
    /// the spelling.
    ///
    /// So each one comes back out of the resolved colour: `Color.primary` is
    /// `labelColor` at alpha 0.847, an ink is that at a further opacity, and the
    /// division recovers what this tree asked for. The two survive three decimal
    /// places apart — 0.035 recovers as 0.035 and 0.04 as 0.040 — which is the
    /// separation the ladder of opacities needs and no more.
    private static func inks() -> [String: Double] {
        let base = Double(alpha(of: .primary))
        func read(_ color: Color) -> Double {
            ((Double(alpha(of: color)) / base) * 1000).rounded() / 1000
        }
        return [
            "surface-card": read(HelmSurface.cardFill),
            "surface-well": read(HelmSurface.wellFill),
            "surface-panel-card": read(HelmSurface.panelCardFill),
            "surface-on-panel": read(HelmSurface.onPanelFill),
            "hairline": read(HelmSurface.hairline),
            "panel-selection": read(HelmSurface.panelSelection),
            "text-quiet": read(HelmText.quiet),
            "text-faint": read(HelmText.faint),
            "mark-separator": read(HelmText.separator),
        ]
    }

    /// The alpha as drawn, in the light appearance. Both appearances carry the
    /// same one — `labelColor` is 0.847 in each — so one reading is the whole
    /// fact, and taking it in a named appearance rather than the current one is
    /// the rule `Contrast` exists to enforce.
    private static func alpha(of color: Color) -> CGFloat {
        var out: CGFloat = 0
        NSAppearance(named: .aqua)!.performAsCurrentDrawingAppearance {
            out = (NSColor(color).usingColorSpace(.sRGB) ?? .clear).alphaComponent
        }
        return out
    }

    /// Written out rather than taken from the enum, for the reason
    /// `LaddersAreTheStepsTheyClaimTests` gives: both sides spelling the numbers
    /// is what makes a comparison a check rather than a restatement. Here it also
    /// catches the case that file cannot — a published record that has drifted
    /// off a ladder nobody moved.
    private static func ladders() -> ([String: Double], [String: Double]) {
        let space: [String: Double] = [
            "s1": .init(HelmSpace.s1), "s2": .init(HelmSpace.s2),
            "s3": .init(HelmSpace.s3), "s4": .init(HelmSpace.s4),
            "s5": .init(HelmSpace.s5), "s6": .init(HelmSpace.s6),
            "s7": .init(HelmSpace.s7), "s8": .init(HelmSpace.s8),
        ]
        let radius: [String: Double] = [
            "tiny": .init(HelmRadius.tiny), "ctl": .init(HelmRadius.ctl),
            "card": .init(HelmRadius.card), "frame": .init(HelmRadius.frame),
            "panel": .init(HelmRadius.panel),
        ]
        return (space, radius)
    }

    private static func layout() -> [String: Double] {
        [
            "settingsColumn": .init(HelmLayout.settingsColumn),
            "formInset": .init(HelmLayout.formInset),
            "cardWidth": .init(HelmLayout.cardWidth),
            "groupedHeaderOutset": .init(HelmLayout.groupedHeaderOutset),
            "groupedHeaderGap": .init(HelmLayout.groupedHeaderGap),
            "readingColumn": .init(HelmLayout.readingColumn),
        ]
    }

    /// Sorted keys and a trailing newline, so the file is a diff a person can
    /// read and a rewrite that changed nothing changes nothing.
    private static func document() throws -> String {
        let (space, radius) = ladders()
        let body: [String: Any] = [
            "colours": colours(),
            "coloursIncreasedContrast": increasedContrastColours(),
            "inks": inks(),
            "space": space, "radius": radius, "layout": layout(),
        ]
        let data = try JSONSerialization.data(
            withJSONObject: body, options: [.prettyPrinted, .sortedKeys])
        return String(decoding: data, as: UTF8.self) + "\n"
    }

    // MARK: - The check

    func testTheRecordIsWhatTheTreeResolvesTo() throws {
        let current = try Self.document()

        if ProcessInfo.processInfo.environment[Self.writeFlag] != nil {
            let url = RepoSource.root.appendingPathComponent(Self.path)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try current.write(to: url, atomically: true, encoding: .utf8)
            XCTFail("""
                Wrote \(Self.path). This mode never passes — re-run without \
                \(Self.writeFlag) to check what it wrote, and republish the design \
                system from it.
                """)
            return
        }

        let recorded = try RepoSource.text(of: Self.path)
        guard current != recorded else { return }

        XCTFail("""
            \(Self.path) is not what this tree resolves to any more.

            \(Self.report(recorded: recorded, current: current))

            Regenerate it with
                \(Self.writeFlag)=1 bash Scripts/test.sh --filter PublishedTokensAreTheTrees
            and republish the design system, whose published values are this file's.
            """)
    }

    /// The first differences, by name, and which side they point at.
    ///
    /// A whole-document diff would say "these two strings differ", which for
    /// forty colours is a wall nobody reads to the end of. The names are what a
    /// person needs, and so is the sentence under them: a colour that moved on
    /// its own is macOS's doing and the record is simply out of date, where an
    /// ink or a step that moved is somebody's edit and the published prose about
    /// it may have stopped being true.
    private static func report(recorded: String, current: String) -> String {
        /// One line per token, whatever shape it has. A colour is a pair and a
        /// step is a number, and both go through here rather than through string
        /// interpolation: a dictionary interpolates as three lines of Cocoa
        /// description, and a `Double` read back out of JSON interpolates as
        /// `0.035000000000000003`, which reads as a defect of its own.
        func flat(_ text: String) -> [String: String] {
            func spell(_ value: Any) -> String {
                if let pair = value as? [String: String] {
                    return "light \(pair["light"] ?? "—"), dark \(pair["dark"] ?? "—")"
                }
                if let number = value as? NSNumber { return String(format: "%g", number.doubleValue) }
                return "\(value)"
            }
            guard let data = text.data(using: .utf8),
                  let top = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { return [:] }
            var out: [String: String] = [:]
            for (family, value) in top {
                guard let table = value as? [String: Any] else { continue }
                for (name, entry) in table { out["\(family).\(name)"] = spell(entry) }
            }
            return out
        }

        let was = flat(recorded), now = flat(current)
        guard !was.isEmpty else { return "The record could not be parsed at all." }

        let names = Set(was.keys).union(now.keys).sorted()
        let changed = names.filter { was[$0] != now[$0] }
        let shown = changed.prefix(12).map { name in
            "  \(name): \(was[name] ?? "absent") → \(now[name] ?? "absent")"
        }
        let more = changed.count > shown.count ? "\n  …and \(changed.count - shown.count) more" : ""
        let onlyColours = changed.allSatisfy { $0.hasPrefix("colours.") }

        return shown.joined(separator: "\n") + more + "\n\n" + (onlyColours
            ? "Only resolved colours moved, and no ink or step did — so this is macOS's "
              + "doing rather than an edit here. Check the OS version before changing the tree."
            : "An ink, a step or a metric moved, which is an edit in this tree. The published "
              + "system says in prose why several of these numbers are what they are; read those "
              + "sentences before republishing.")
    }

    /// The record is a record of something. A file of forty names and no values,
    /// or a file this test would write as empty, would pass the comparison above
    /// every day.
    func testTheRecordHoldsEveryTokenTheTreeHas() throws {
        let text = try RepoSource.text(of: Self.path)
        let data = try XCTUnwrap(text.data(using: .utf8))
        let top = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let colours = try XCTUnwrap(top["colours"] as? [String: [String: String]])

        for tint in ModuleTint.allCases {
            XCTAssertNotNil(colours["tint-\(Self.published(tint.rawValue))"],
                            "no record of \(tint.rawValue)")
        }
        for colour in PaletteColor.allCases {
            XCTAssertNotNil(colours["palette-\(Self.published(colour.rawValue))"],
                            "no record of \(colour.rawValue)")
        }
        let increased = try XCTUnwrap(top["coloursIncreasedContrast"] as? [String: [String: String]])
        XCTAssertEqual(increased.count, ModuleTint.allCases.count + 3,
                       "thirteen colours this tree defines itself")
        XCTAssertEqual((top["space"] as? [String: Double])?.count, 8)
        XCTAssertEqual((top["radius"] as? [String: Double])?.count, 5)

        for (name, pair) in colours {
            for appearance in ["light", "dark"] {
                let value = pair[appearance] ?? ""
                XCTAssertTrue(value.hasPrefix("#") || value.hasPrefix("rgba("),
                              "\(name).\(appearance) is \(value.isEmpty ? "empty" : value)")
            }
        }
    }
}
