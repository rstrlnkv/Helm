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
}
