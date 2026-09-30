import AppKit
import HelmTestSupport
import SwiftUI
import XCTest
@testable import HelmUI

/// **`helmStripedList(rowPitch:)` declares one number and nothing may move it
/// — not an empty list, not rows that change after the mount, not a remount
/// under a new identity, not a neighbour table in the same hosting view.**
///
/// The pitch is `rowHeight` on the backing `NSTableView`, which AppKit repeats
/// below the last row (`NSTableView.h`, on `rowHeight`). Every case reads that
/// property *and*, where the empty area is tall enough to hold two whole
/// stripes, the pitch it is actually painted at (`StripedEmptyAreaPitch`).
/// The rows themselves are read too: the declared number is a floor for every
/// row, so a short row must sit at the pitch and a taller row must keep its
/// own height — a floor raised by one row onto the rest is the defect a modifier
/// taking its pitch from a measured row would have, and it is what the
/// tall-first case exists to catch.
///
/// The pitch used is `HelmSpace.s8` (40 pt), which is what every call site in
/// the tree passes and is well away from AppKit's own 24 pt default, so a
/// modifier that stopped declaring anything reads 24 here, not 40.
@MainActor
final class AStripedListHoldsItsDeclaredPitchTests: XCTestCase {

    private static let pitch = HelmSpace.s8

    final class Model: ObservableObject {
        @Published var count: Int
        @Published var tallIndex: Int?
        @Published var long = false
        @Published var revision = 0
        init(count: Int, tallIndex: Int? = nil) { self.count = count; self.tallIndex = tallIndex }
    }

    struct Row: View {
        let index: Int
        let tall: Bool
        let long: Bool
        var body: some View {
            VStack(alignment: .leading, spacing: 2) {
                Text(long ? "row \(index) with a name long enough to wrap in a narrow list, twice over"
                          : "row \(index)")
                if tall {
                    Text("second line")
                    Text("third line")
                }
            }
            .listRowSeparator(.hidden)
        }
    }

    struct Rows: View {
        @ObservedObject var model: Model
        var body: some View {
            List {
                ForEach(0..<model.count, id: \.self) { i in
                    Row(index: i, tall: i == model.tallIndex, long: model.long)
                }
            }
            .helmStripedList(rowPitch: AStripedListHoldsItsDeclaredPitchTests.pitch)
            .id(model.revision)
        }
    }

    private var renders: [MountedRender] = []

    override func tearDown() {
        renders.forEach { $0.drop() }
        renders = []
        super.tearDown()
    }

    private func mount<V: View>(_ view: V, width: CGFloat = 300, height: CGFloat = 400) -> MountedRender {
        let render = MountedRender(view, width: width, height: height, appearance: .aqua)
        renders.append(render)
        render.settle(30)
        return render
    }

    private func table(_ render: MountedRender, file: StaticString = #filePath,
                       line: UInt = #line) throws -> NSTableView {
        let tables = render.host.everyView(ofType: NSTableView.self)
        XCTAssertEqual(tables.count, 1, "precondition: one NSTableView under the mount",
                       file: file, line: line)
        return try XCTUnwrap(tables.first, "no NSTableView under the mount", file: file, line: line)
    }

    private func heights(_ table: NSTableView) -> [CGFloat] {
        (0..<table.numberOfRows).map { table.rect(ofRow: $0).height }
    }

    /// `rowHeight` is the pitch and the empty area is painted at it.
    private func assertDeclared(_ render: MountedRender, _ table: NSTableView, _ label: String,
                                file: StaticString = #filePath, line: UInt = #line) {
        let painted = StripedEmptyAreaPitch.read(render.host, table)
        print("PITCH[\(label)] rowHeight=\(table.rowHeight) rows=\(heights(table)) "
              + "painted \(painted.map { "\($0)" } ?? "unreadable")")
        XCTAssertEqual(table.rowHeight, Self.pitch, accuracy: 0.5, """
            \(label): the table's rowHeight is \(table.rowHeight) where the list declared \(Self.pitch)
            """, file: file, line: line)
        XCTAssertEqual(painted?.pitch ?? -1, Self.pitch, accuracy: 1, """
            \(label): the empty area is painted at \(painted?.pitch.map { "\($0)" } ?? "no readable pitch") \
            where the list declared \(Self.pitch)
            """, file: file, line: line)
    }

    // MARK: - Empty

    /// **An empty list is all empty area, and it is striped at the pitch** —
    /// in both appearances, since the dark stripe is a different pair of
    /// colours and the reading is of pixels. The control — the same list
    /// without the modifier's pitch — paints at AppKit's own default, so the
    /// reading tells the two apart.
    func testAnEmptyListIsStripedAtThePitch() throws {
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            let render = MountedRender(Rows(model: Model(count: 0)), width: 300, height: 400,
                                       appearance: appearance)
            renders.append(render)
            render.settle(30)
            let table = try table(render)
            XCTAssertEqual(table.numberOfRows, 0, "precondition: the list is empty")
            assertDeclared(render, table, "empty, \(appearance.rawValue)")

            let control = MountedRender(List { ForEach(0..<0, id: \.self) { Text("\($0)") } }
                .listStyle(.inset).alternatingRowBackgrounds(), width: 300, height: 400,
                                        appearance: appearance)
            renders.append(control)
            control.settle(30)
            let controlTable = try self.table(control)
            let controlPainted = StripedEmptyAreaPitch.read(control.host, controlTable)?.pitch
            XCTAssertNotNil(controlPainted,
                            "\(appearance.rawValue): precondition: the control's empty area has a readable pitch")
            XCTAssertNotEqual(controlPainted ?? Self.pitch, Self.pitch, accuracy: 1, """
                \(appearance.rawValue): the control paints at the declared pitch too — the reading \
                cannot tell them apart
                """)
        }
    }

    // MARK: - Unequal rows

    /// **A tall first row keeps its own height and does not raise the rows
    /// under it.** Short rows sit at the pitch.
    func testATallFirstRowDoesNotRaiseTheRowsUnderIt() throws {
        let render = mount(Rows(model: Model(count: 4, tallIndex: 0)))
        let table = try table(render)
        let rows = heights(table)
        XCTAssertEqual(rows.count, 4, "precondition: four rows")
        guard rows.count == 4 else { return }
        XCTAssertGreaterThan(rows[0], Self.pitch + 0.5, "precondition: the first row is taller than the pitch")
        for (index, height) in rows.enumerated().dropFirst() {
            XCTAssertEqual(height, Self.pitch, accuracy: 0.5, """
                row \(index) is \(height) pt under a \(rows[0]) pt first row — a short row \
                sits at the \(Self.pitch) pt pitch, not at its neighbour's height
                """)
        }
        assertDeclared(render, table, "tall first")
    }

    // MARK: - Change after the mount

    /// **Rows that change after the mount leave the pitch where it was** —
    /// filled after being empty, grown in place by a wrap, shrunk back — and
    /// the rows come back down to the pitch when they shrink: a floor that
    /// only rises is a ratchet.
    func testRowsThatChangeAfterTheMountLeaveThePitchAlone() throws {
        let model = Model(count: 0)
        let render = mount(Rows(model: model), height: 640)
        let table = try table(render)
        assertDeclared(render, table, "empty")

        model.count = 3
        render.settle(30)
        XCTAssertEqual(table.numberOfRows, 3, "precondition: filled in place, same table")
        assertDeclared(render, table, "filled")
        for height in heights(table) {
            XCTAssertEqual(height, Self.pitch, accuracy: 0.5, "filled: a short row is \(height) pt")
        }

        model.long = true
        model.tallIndex = 1
        render.settle(30)
        let grown = heights(table)
        XCTAssertTrue(grown.contains { $0 > Self.pitch + 0.5 }, "precondition: rows grew past the pitch in place")
        assertDeclared(render, table, "grown")

        model.long = false
        model.tallIndex = nil
        render.settle(30)
        for height in heights(table) {
            XCTAssertEqual(height, Self.pitch, accuracy: 0.5, """
                shrunk back: a row is \(height) pt where it drew \(Self.pitch) before it grew
                """)
        }
        assertDeclared(render, table, "shrunk back")
    }

    /// **A remount under a new identity — which is how a language change
    /// reaches a page (`content.id(model.languageRevision)`) — builds a new
    /// table, and the new table is at the pitch too.**
    func testANewIdentityBuildsATableAtThePitch() throws {
        let model = Model(count: 3, tallIndex: 0)
        let render = mount(Rows(model: model))
        let first = try table(render)
        assertDeclared(render, first, "identity 0")
        for revision in 1...2 {
            model.revision = revision
            render.settle(30)
            let next = try table(render)
            XCTAssertFalse(next === first, "precondition: the new identity built a new table")
            assertDeclared(render, next, "identity \(revision)")
        }
    }

    // MARK: - Neighbours

    /// **A second table in the same hosting view is neither given the pitch
    /// nor lends its own.** The modifier sits on its `List`, so its
    /// environment reaches that subtree only; a sidebar beside it is compared
    /// with the same sidebar beside an unstriped list.
    func testANeighbourTableKeepsItsOwnRows() throws {
        func page(striped: Bool) -> some View {
            HStack(spacing: 0) {
                List { ForEach(0..<4, id: \.self) { Text("side \($0)") } }
                    .listStyle(.sidebar).frame(width: 120)
                Group {
                    if striped {
                        List { ForEach(0..<3, id: \.self) { Text("row \($0)").listRowSeparator(.hidden) } }
                            .helmStripedList(rowPitch: Self.pitch)
                    } else {
                        List { ForEach(0..<3, id: \.self) { Text("row \($0)").listRowSeparator(.hidden) } }
                            .listStyle(.inset)
                    }
                }
            }
        }
        let striped = mount(page(striped: true), width: 420)
        let plain = mount(page(striped: false), width: 420)
        let a = striped.host.everyView(ofType: NSTableView.self)
        let b = plain.host.everyView(ofType: NSTableView.self)
        XCTAssertEqual(a.count, 2, "precondition: two tables in one hosting view")
        XCTAssertEqual(b.count, 2, "precondition: two tables in one hosting view")
        let sideA = try XCTUnwrap(a.first { !$0.usesAlternatingRowBackgroundColors }, "no sidebar table")
        let sideB = try XCTUnwrap(b.first { $0.enclosingScrollView.map { $0.frame.width < 200 } ?? false },
                                  "no sidebar table in the control")
        XCTAssertEqual(sideA.rowHeight, sideB.rowHeight, "the sidebar's rowHeight moved beside a striped list")
        XCTAssertEqual(heights(sideA), heights(sideB), "the sidebar's rows moved beside a striped list")
        XCTAssertNotEqual(sideA.rowHeight, Self.pitch, accuracy: 0.5,
                          "precondition: the sidebar's own rowHeight is not the pitch, or this proves nothing")
        let content = try XCTUnwrap(a.first { $0.usesAlternatingRowBackgroundColors }, "no striped table")
        assertDeclared(striped, content, "beside a sidebar")
    }

    // MARK: - Unmount

    /// **The table and the model behind the list go with the page.** The
    /// control (no modifier) is read the same way, so a harness that leaks on
    /// its own cannot pass for the modifier holding something.
    func testNothingOutlivesTheMount() throws {
        for striped in [false, true] {
            weak var weakTable: NSTableView?
            weak var weakModel: Model?
            weak var weakHost: NSView?
            try autoreleasepool {
                let model = Model(count: 3, tallIndex: 0)
                weakModel = model
                let view = Group {
                    if striped {
                        Rows(model: model)
                    } else {
                        List { ForEach(0..<model.count, id: \.self) { Text("\($0)") } }
                            .listStyle(.inset).alternatingRowBackgrounds()
                    }
                }
                let render = MountedRender(view, width: 300, height: 400, appearance: .aqua)
                render.settle(30)
                weakHost = render.host
                weakTable = try XCTUnwrap(render.host.everyView(ofType: NSTableView.self).first)
                XCTAssertNotNil(weakTable, "precondition: a table was mounted")
                render.drop()
            }
            for _ in 0..<30 { RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02)) }
            XCTAssertNil(weakTable, "striped=\(striped): the table outlived the page")
            XCTAssertNil(weakModel, "striped=\(striped): the model outlived the page")
            XCTAssertNil(weakHost, "striped=\(striped): the hosting view outlived the page")
        }
    }
}
