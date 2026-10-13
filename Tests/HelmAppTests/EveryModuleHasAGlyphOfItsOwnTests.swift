import XCTest
import SwiftUI
import HelmTestSupport
@testable import HelmApp
@testable import HelmUI

/// `ModuleRegistryTintTests` says no two modules share a colour; this says no
/// two share a shape. A module's descriptor names its glyph, the compiler makes
/// every module name one, and nothing else stops two of them naming the same —
/// or a glyph whose body is empty, which leaves nothing to fill when the glyph
/// is drawn filled.
///
/// Every check over the modules starts by asserting that there are modules to
/// look at, so a registry without them fails the first assertion instead of
/// making the rest vacuously true.
@MainActor
final class EveryModuleHasAGlyphOfItsOwnTests: XCTestCase {

    private var modules: [(id: String, glyph: ShellGlyph)] {
        ModuleRegistry.all.map { ($0.idRaw, $0.moduleGlyph) }
    }

    /// Tolerance when a path's bounds are compared with the grid's edge.
    private let slack: CGFloat = 0.001

    func testNoTwoModulesShareAGlyph() {
        XCTAssertGreaterThan(ModuleRegistry.all.count, 1, "fewer than two modules: nothing below compares anything")
        var owner: [ShellGlyph: String] = [:]
        for (id, glyph) in modules {
            if let first = owner[glyph] {
                XCTFail("two modules share a glyph: \(first) and \(id) both name \(glyph)")
            }
            owner[glyph] = id
        }
        XCTAssertEqual(Set(modules.map(\.glyph)).count, ModuleRegistry.all.count,
                       "two modules share a glyph: \(modules.map { "\($0.id)=\($0.glyph)" })")
    }

    /// Distinct cases could still draw one shape. The geometry is compared as
    /// well, whole: body, extra and detail together.
    func testNoTwoModulesDrawTheSameShape() {
        XCTAssertGreaterThan(modules.count, 1, "fewer than two modules: nothing below compares anything")
        for (i, a) in modules.enumerated() {
            for b in modules[(i + 1)...] {
                let same = a.glyph.body == b.glyph.body && a.glyph.extra == b.glyph.extra
                    && a.glyph.detail == b.glyph.detail
                XCTAssertFalse(same, "two modules share a glyph: \(a.id) and \(b.id) draw the same shape")
            }
        }
    }

    func testEveryModulesGlyphHasABodyInsideTheGrid() {
        XCTAssertFalse(modules.isEmpty, "the registry is empty: nothing below was checked")
        XCTAssertEqual(ShellGlyph.grid, 24, "the shapes are drawn on a 24-unit grid")
        let grid = CGRect(x: 0, y: 0, width: ShellGlyph.grid, height: ShellGlyph.grid)
            .insetBy(dx: -slack, dy: -slack)
        for (id, glyph) in modules {
            XCTAssertFalse(glyph.body.isEmpty || glyph.body.boundingRect.isEmpty,
                           "a glyph with an empty body: drawn filled, there is nothing to fill (\(id))")
            for (name, path) in [("body", glyph.body), ("extra", glyph.extra), ("detail", glyph.detail)]
            where !path.isEmpty {
                XCTAssertTrue(grid.contains(path.boundingRect),
                              "\(id): the \(name) leaves the 0...24 grid: \(path.boundingRect)")
            }
        }
    }

    /// A body within a unit of the whole grid square is a box, not a shape.
    func testNoBodyIsTheWholeGridSquare() {
        XCTAssertFalse(modules.isEmpty, "the registry is empty: nothing below was checked")
        let side = ShellGlyph.grid
        for (id, glyph) in modules {
            let box = glyph.body.boundingRect
            XCTAssertFalse(box.width >= side - 1 && box.height >= side - 1,
                           "\(id): the body is within a unit of the whole grid square, not a shape")
        }
    }

    /// `filled` must change what is drawn.
    /// Both drawings are read in both appearances; a blank pair must not pass
    /// as "differs", so each is first asserted to have drawn something.
    func testTheFilledDrawingDiffersFromTheLineDrawingForEveryModule() {
        XCTAssertFalse(modules.isEmpty, "the registry is empty: nothing below was checked")
        let size: CGFloat = 48
        for (id, glyph) in modules {
            for appearance in RenderedInk.bothAppearances {
                let screen = RenderedInk.label(of: appearance)
                func drawing(filled: Bool) -> (ink: Int?, bytes: Data?) {
                    let mount = MountedRender(ShellGlyphView(glyph, filled: filled, size: size)
                        .frame(width: size, height: size),
                                              width: size, height: size, appearance: appearance)
                    defer { mount.drop() }
                    mount.settle(3)
                    return (mount.ink(), mount.pixels())
                }
                let line = drawing(filled: false)
                let filled = drawing(filled: true)
                guard let lineInk = line.ink, let filledInk = filled.ink,
                      let lineBytes = line.bytes, let filledBytes = filled.bytes else {
                    XCTFail("\(id) (\(screen)): a drawing could not be read at all")
                    continue
                }
                XCTAssertGreaterThan(lineInk, 0, "\(id) (\(screen)): the line drawing drew nothing")
                XCTAssertGreaterThan(filledInk, 0, "\(id) (\(screen)): the filled drawing drew nothing")
                XCTAssertNotEqual(lineBytes, filledBytes,
                                  "\(id) (\(screen)): the filled drawing is the line drawing, `filled` changes nothing")
                XCTAssertGreaterThan(filledInk, lineInk,
                                     "\(id) (\(screen)): the filled drawing carries no more ink than the line one")
            }
        }
    }

    /// The cases no module names are read by no other test. Every case is read
    /// here: a non-empty path lies inside the grid, and at least one of the
    /// three is not empty.
    func testEveryCaseReadsInsideTheGridAndDrawsSomething() {
        XCTAssertGreaterThan(ShellGlyph.allCases.count, ModuleRegistry.all.count,
                             "there are no cases beyond the modules' own, so this test adds nothing to the ones above")
        let grid = CGRect(x: 0, y: 0, width: ShellGlyph.grid, height: ShellGlyph.grid)
            .insetBy(dx: -slack, dy: -slack)
        for glyph in ShellGlyph.allCases {
            let paths = [("body", glyph.body), ("extra", glyph.extra), ("detail", glyph.detail)]
            for (name, path) in paths where !path.isEmpty {
                XCTAssertTrue(grid.contains(path.boundingRect),
                              "\(glyph): the \(name) leaves the 0...24 grid: \(path.boundingRect)")
            }
            XCTAssertTrue(paths.contains { !$0.1.isEmpty },
                          "\(glyph): body, extra and detail are all empty, it draws nothing")
        }
    }

    // MARK: - The size a glyph is drawn at

    /// `side(for:)` is what the view's body draws with. This test does not mount
    /// the view: the answer for a size is a value, and a size that is not a
    /// number must not reach a frame. Asserted on the result not being NaN as
    /// well as on its value, so a pass-through of the input fails twice.
    func testASizeThatIsNothingOrNotANumberOrNegativeDrawsNothing() {
        for size: CGFloat in [0, -0.0, -16, -.leastNonzeroMagnitude, .nan, -.infinity, -.greatestFiniteMagnitude] {
            let side = ShellGlyphView.side(for: size)
            XCTAssertFalse(side.isNaN, "a size of \(size) draws at a side that is not a number")
            XCTAssertEqual(side, 0, "a size of \(size) draws at \(side), not nothing")
        }
    }

    func testASizeThatIsAUsableSizeIsDrawnAsAsked() {
        XCTAssertEqual(ShellGlyphView.side(for: 20.8), 20.8, "the sidebar's own size is changed")
        XCTAssertEqual(ShellGlyphView.side(for: 16 * 1.3), 16 * 1.3)
        XCTAssertEqual(ShellGlyphView.side(for: 1), 1)
        XCTAssertEqual(ShellGlyphView.side(for: 48), 48)
        XCTAssertEqual(ShellGlyphView.side(for: ShellGlyphView.largest), ShellGlyphView.largest)
    }

    /// Infinity is a size, only a huge one: it draws at the bound, not at nothing
    /// and not at infinity. Past the bound is the bound.
    func testASizeBeyondTheLargestDrawsAtTheLargest() {
        XCTAssertEqual(ShellGlyphView.largest, 1024)
        XCTAssertEqual(ShellGlyphView.side(for: .infinity), ShellGlyphView.largest)
        XCTAssertEqual(ShellGlyphView.side(for: ShellGlyphView.largest + 1), ShellGlyphView.largest)
        XCTAssertEqual(ShellGlyphView.side(for: .greatestFiniteMagnitude), ShellGlyphView.largest)
    }

    /// The pure answer is only worth having if the body draws with it. A body that
    /// went back to the raw `size` would pass every test above, so the body is
    /// read: it asks `side(for:)`, draws nothing when the side is not above 0, and
    /// does not spell `size` again.
    func testTheBodyDrawsWithTheSideAndNotWithTheSizeItWasGiven() throws {
        let source = SwiftSource.code(try RepoSource.text(of: "Sources/HelmUI/DesignSystem/ShellGlyph.swift"))
        let lines = source.components(separatedBy: "\n")
        let start = try XCTUnwrap(lines.firstIndex { $0.contains("public var body: some View") },
                                  "ShellGlyphView has no public body")
        let body = SwiftSource.modifierChain(from: start, in: lines)
        XCTAssertTrue(body.contains("Self.side(for: size)"), "the body does not ask side(for:)")
        XCTAssertTrue(body.contains("if side > 0"), "the body draws at a side of nothing")
        XCTAssertTrue(body.contains("width: side, height: side"), "the frame is not the side")
        XCTAssertGreaterThanOrEqual(body.components(separatedBy: "side / ShellGlyph.grid").count - 1, 2,
                                    "the scale and the pen are not made from the side")
        let withoutTheAsk = body.replacingOccurrences(of: "Self.side(for: size)", with: "")
        XCTAssertFalse(withoutTheAsk.contains("size"), "the body reads the size it was given beside the side")
    }
}
