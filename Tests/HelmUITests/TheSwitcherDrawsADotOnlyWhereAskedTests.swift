import AppKit
import HelmTestSupport
import SwiftUI
import XCTest
@testable import HelmUI

/// **The switcher draws a dot on the segment whose tab asked for one, and on no other — in every style, folded
/// and unfolded, and it takes the dot back when the tab stops asking, on the same control.**
///
/// `HelmToolbarTab.needsAttention` defaults to false so that the pages that never say it draw as before. A dot is
/// an image on the segment and an image cannot be read back as a flag, so what is read here is what was drawn:
/// the segment's own image, rendered to pixels, and its *coloured* pixels (the glyph is the label colour, grey; the
/// dot is the warning ink, which has saturation). The probe is fixed English words, not localized ones — nothing
/// here is a visible string a language decides (`TheSwitcherFoldsToOneSegmentTests.Mounted`'s header).
///
/// The folded switcher draws one segment, so a dot on a tab that is not the one shown is said in its menu instead,
/// as a badge; the menu is asked for every tab, full, never for the shown segment alone.
@MainActor
final class TheSwitcherDrawsADotOnlyWhereAskedTests: XCTestCase {

    static let words = ["Capturing", "Editor", "System"]
    static let symbols = ["circle", "square", "triangle"]
    static let note = "Still on in macOS"

    struct Probe: View {
        let attention: [Bool]
        var selected = 0
        var compact = false
        var style: ToolbarSwitcherStyle = .text
        var note: String? = TheSwitcherDrawsADotOnlyWhereAskedTests.note

        var body: some View {
            HelmToolbarSwitcher("Probe", selection: .constant(selected),
                                segments: TheSwitcherDrawsADotOnlyWhereAskedTests.words.enumerated().map { index, word in
                                    HelmSwitcherSegment(index, word, symbol: TheSwitcherDrawsADotOnlyWhereAskedTests.symbols[index],
                                                        needsAttention: attention[index], attentionNote: attention[index] ? note : nil)
                                }, compact: compact)
                .environment(\.helmSwitcherStyle, style)
        }
    }

    private func mount(_ probe: Probe) throws -> (NSHostingView<Probe>, NSSegmentedControl) {
        let host = NSHostingView(rootView: probe)
        host.appearance = NSAppearance(named: .aqua)
        host.frame = NSRect(x: 0, y: 0, width: 600, height: 60)
        host.layoutSubtreeIfNeeded()
        let control = try XCTUnwrap(host.everyView(ofType: NSSegmentedControl.self).first,
                                    "the switcher put no NSSegmentedControl in the tree")
        return (host, control)
    }

    /// What an image drew: every pixel that is opaque and coloured, as (column, row from the top), and how many opaque
    /// grey ones there are besides (the glyph).
    private func ink(of image: NSImage?) throws -> (coloured: [(x: Int, y: Int)], grey: Int, size: NSSize) {
        let image = try XCTUnwrap(image, "the segment has no image")
        let scale = 4
        let pixelsWide = Int(image.size.width.rounded(.up)) * scale, pixelsHigh = Int(image.size.height.rounded(.up)) * scale
        let rep = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixelsWide, pixelsHigh: pixelsHigh,
                                                 bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                                 colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        rep.size = NSSize(width: CGFloat(pixelsWide) / CGFloat(scale), height: CGFloat(pixelsHigh) / CGFloat(scale))
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        let context = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: rep))
        NSGraphicsContext.current = context
        NSAppearance(named: .aqua)?.performAsCurrentDrawingAppearance {
            image.draw(in: NSRect(origin: .zero, size: rep.size))
        }
        var coloured: [(x: Int, y: Int)] = []
        var grey = 0
        for y in 0..<pixelsHigh {
            for x in 0..<pixelsWide {
                guard let colour = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB), colour.alphaComponent > 0.5 else { continue }
                if colour.saturationComponent > 0.4 { coloured.append((x / scale, y / scale)) } else { grey += 1 }
            }
        }
        return (coloured, grey, image.size)
    }

    /// How many coloured pixels a segment's image drew; none for a segment with no image.
    private func dots(_ control: NSSegmentedControl, _ index: Int) throws -> Int {
        guard let image = control.image(forSegment: index) else { return 0 }
        return try ink(of: image).coloured.count
    }

    // MARK: - The default

    func testATabAndASegmentThatSayNothingAskForNoDot() {
        let tab = HelmToolbarTab(id: "a", title: "A", symbol: "circle")
        XCTAssertFalse(tab.needsAttention)
        XCTAssertNil(tab.attentionNote)
        let segment = HelmSwitcherSegment(0, "A", symbol: "circle")
        XCTAssertFalse(segment.needsAttention)
        XCTAssertNil(segment.attentionNote)
    }

    // MARK: - Every style, only the asked segment

    func testEveryStyleDrawsTheDotOnTheAskedSegmentAndOnNoOtherOne() throws {
        for style in ToolbarSwitcherStyle.allCases {
            for asked in Self.words.indices {
                var flags = [Bool](repeating: false, count: Self.words.count)
                flags[asked] = true
                let (_, control) = try mount(Probe(attention: flags, style: style))
                XCTAssertEqual(control.segmentCount, Self.words.count, "\(style): the subject, every segment drawn")
                for index in Self.words.indices {
                    let coloured = try dots(control, index)
                    if index == asked {
                        XCTAssertGreaterThan(coloured, 0, "\(style): segment \(index) asked for a dot and drew none")
                    } else {
                        XCTAssertEqual(coloured, 0, "\(style): segment \(index) drew a dot nobody asked for (asked: \(asked))")
                    }
                }
            }
        }
    }

    func testNoSegmentAsksNoSegmentDraws() throws {
        for style in ToolbarSwitcherStyle.allCases {
            let (_, control) = try mount(Probe(attention: [false, false, false], style: style))
            for index in Self.words.indices {
                XCTAssertEqual(try dots(control, index), 0, "\(style): segment \(index) drew a dot")
            }
        }
    }

    /// A text segment keeps its word beside the dot, and the dot is the whole image; a glyph segment keeps its glyph
    /// and carries the dot in the glyph's upper right corner, the size of the glyph unchanged.
    func testTheDotLeavesTheWordAndTheGlyphWhereTheyWere() throws {
        let (_, text) = try mount(Probe(attention: [false, false, true], style: .text))
        XCTAssertEqual(text.label(forSegment: 2), Self.words[2], "the dot took the word away")
        let textDot = try ink(of: text.image(forSegment: 2))
        XCTAssertEqual(textDot.grey, 0, "a text segment's image is the dot alone")
        XCTAssertLessThanOrEqual(textDot.size.width, 8, "the dot is 6 pt")

        for style in [ToolbarSwitcherStyle.icons, .iconsAndText] {
            let (_, plain) = try mount(Probe(attention: [false, false, false], style: style))
            let (_, marked) = try mount(Probe(attention: [false, false, true], style: style))
            XCTAssertEqual(marked.label(forSegment: 2), plain.label(forSegment: 2), "\(style): the dot changed the word")
            let bare = try ink(of: plain.image(forSegment: 2))
            let withDot = try ink(of: marked.image(forSegment: 2))
            XCTAssertEqual(withDot.size, bare.size, "\(style): the glyph's size moved")
            XCTAssertGreaterThan(withDot.grey, 0, "\(style): the glyph was replaced by the dot")
            XCTAssertFalse(withDot.coloured.isEmpty, "\(style): no dot")
            let width = Int(withDot.size.width.rounded(.up)), height = Int(withDot.size.height.rounded(.up))
            for pixel in withDot.coloured {
                XCTAssertGreaterThanOrEqual(pixel.x, width - 7, "\(style): the dot is not in the right corner (\(pixel))")
                XCTAssertLessThanOrEqual(pixel.y, 6, "\(style): the dot is not in the upper corner (\(pixel) of \(width)x\(height))")
            }
        }
    }

    func testTheDotWidensTheStripSoTheWidthMeasuredIncludesIt() throws {
        let (_, plain) = try mount(Probe(attention: [false, false, false]))
        let (_, marked) = try mount(Probe(attention: [false, false, true]))
        XCTAssertGreaterThan(marked.fittingSize.width, plain.fittingSize.width,
                             "the dot is on the strip and the strip is not wider: a width measured without it is too short")
    }

    // MARK: - On the same control, coming and going

    func testTheDotComesAndGoesOnTheSameControlWithoutAMount() throws {
        for style in ToolbarSwitcherStyle.allCases {
            let (host, control) = try mount(Probe(attention: [false, false, false], style: style))
            func dotted() throws -> Bool { try dots(control, 2) > 0 }
            XCTAssertFalse(try dotted(), "\(style): the control began with a dot")
            host.rootView = Probe(attention: [false, false, true], style: style)
            host.layoutSubtreeIfNeeded()
            XCTAssertTrue(control === host.everyView(ofType: NSSegmentedControl.self).first, "\(style): the control was rebuilt, not refilled")
            XCTAssertTrue(try dotted(), "\(style): the tab began asking and the segment kept its old image")
            host.rootView = Probe(attention: [false, false, false], style: style)
            host.layoutSubtreeIfNeeded()
            XCTAssertFalse(try dotted(), "\(style): the tab stopped asking and the dot stayed")
            host.rootView = Probe(attention: [true, false, true], style: style)
            host.layoutSubtreeIfNeeded()
            XCTAssertGreaterThan(try dots(control, 0), 0, "\(style): a second asked segment drew no dot")
        }
    }

    // MARK: - Folded

    private func tabsMenu(of control: NSSegmentedControl) throws -> NSMenu {
        let coordinator = try XCTUnwrap(control.target as? HelmToolbarSwitcher<Int>.Coordinator, "the control's target is not the coordinator")
        return try XCTUnwrap(coordinator.tabsMenu, "the folded switcher has no menu of its tabs")
    }

    func testTheFoldedSwitcherSaysTheDotOfAnotherTabInItsMenuAndOnlyThere() throws {
        let (_, control) = try mount(Probe(attention: [false, false, true], selected: 0, compact: true))
        XCTAssertEqual(control.segmentCount, 1, "the subject: folded")
        XCTAssertEqual(try dots(control, 0), 0, "the shown tab did not ask and its segment drew a dot")
        let menu = try tabsMenu(of: control)
        XCTAssertEqual(menu.items.map(\.title), Self.words, "the menu names every tab, not the shown one alone")
        XCTAssertEqual(menu.items.map { $0.badge?.stringValue }, [nil, nil, Self.note],
                       "the tab that asked is badged with what the dot says, and no other")
    }

    func testTheFoldedSwitcherDrawsTheDotWhenTheShownTabAsksAndBadgesItToo() throws {
        let (_, control) = try mount(Probe(attention: [false, false, true], selected: 2, compact: true))
        XCTAssertEqual(control.label(forSegment: 0), Self.words[2], "the subject: the shown segment is the asking tab")
        XCTAssertFalse(try ink(of: control.image(forSegment: 0)).coloured.isEmpty, "the shown tab asked and drew no dot")
        XCTAssertEqual(try tabsMenu(of: control).items.map { $0.badge?.stringValue }, [nil, nil, Self.note])
    }

    func testAMenuBadgeWithNoNoteIsTheDotAloneAndNoTabAsksNoBadge() throws {
        let (_, noted) = try mount(Probe(attention: [false, true, false], selected: 0, compact: true, note: nil))
        XCTAssertEqual(try tabsMenu(of: noted).items.map { $0.badge?.stringValue }, [nil, "•", nil])
        let (_, quiet) = try mount(Probe(attention: [false, false, false], selected: 1, compact: true))
        XCTAssertEqual(try tabsMenu(of: quiet).items.map { $0.badge?.stringValue }, [nil, nil, nil], "a badge on a tab that did not ask")
    }

    /// Fold and unfold keep the dot: it is drawn again by the fill the fold causes.
    func testFoldingAndUnfoldingKeepWhatTheTabsAsked() throws {
        let (host, control) = try mount(Probe(attention: [false, false, true], selected: 2))
        host.rootView = Probe(attention: [false, false, true], selected: 2, compact: true)
        host.layoutSubtreeIfNeeded()
        XCTAssertFalse(try ink(of: control.image(forSegment: 0)).coloured.isEmpty, "folded on the asking tab: no dot")
        host.rootView = Probe(attention: [false, false, true], selected: 2)
        host.layoutSubtreeIfNeeded()
        XCTAssertEqual(control.segmentCount, Self.words.count)
        for index in Self.words.indices {
            XCTAssertEqual(try dots(control, index) > 0, index == 2, "unfolded: segment \(index)")
        }
    }
}
