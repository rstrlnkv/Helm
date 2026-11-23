import HelmTestSupport
import XCTest
@testable import Module_Launchpad_Engine
@testable import Module_Launchpad_UI

/// Chords by the hundred over layouts with large folders, stored page breaks, a hidden app and grids of other shapes: whatever
/// a chord writes or refuses, no app is lost or placed twice, and the choice is still on the tile (or the folder it went into).
@MainActor final class AKeyMoveOverEveryShapeOfPageLosesNothingTests: XCTestCase {
    private struct Rng {
        var s: UInt64
        mutating func next(_ n: Int) -> Int { s = s &* 6364136223846793005 &+ 1442695040888963407; return Int((s >> 33) % UInt64(n)) }
    }

    private func describe(_ i: LaunchpadLayout.Item) -> String {
        switch i {
        case .app(let a): a
        case .pageBreak: "|"
        case .folder(let f): "[" + (f.large ? "L:" : "") + f.apps.joined(separator: ",") + "]"
        }
    }

    private func walk(_ r: LiftRig, to id: String) {
        guard let at = r.state.pages.joined().map(\.id).firstIndex(of: id) else { return }
        if r.state.selection == nil { r.state.move(dx: 1, dy: 0) }
        var n = 0
        while let s = r.state.selection, s != at, n < 200 { r.state.move(dx: s < at ? 1 : -1, dy: 0); n += 1 }
    }

    func testNoChordLosesOrCopiesAnAppOrLosesTheChoice() async {
        var failures: [String] = [], writes = 0, chords = 0
        for seed in 1...16 {
            var rng = Rng(s: UInt64(seed))
            let n = 8 + rng.next(14)
            let ids = (0..<n).map { String(format: "app%02d", $0) }
            let hiddenID = rng.next(3) == 0 ? ids.last : nil
            var items: [LaunchpadLayout.Item] = [], used = 0
            while used < n - (hiddenID == nil ? 0 : 1) {
                let k = rng.next(10)
                if k < 2, used > 0 { items.append(.pageBreak); continue }
                if k < 4, used + 2 < n - 1 {
                    items.append(.folder(.init(id: UUID(), name: "F", apps: [ids[used], ids[used + 1], ids[used + 2]], large: rng.next(2) == 0)))
                    used += 3
                    continue
                }
                items.append(.app(ids[used])); used += 1
            }
            var layout = LaunchpadLayout(items: items)
            if let hiddenID { layout.hidden = [hiddenID] }
            let r = LiftRig(self, apps: ids, layout: layout, screen: CGSize(width: 900, height: 700))
            r.state.regrid(LaunchpadGridSettings(automatic: false, rows: 2 + rng.next(2), columns: 3 + rng.next(2), iconSize: 80))
            let before = r.placedApps.sorted()
            for step in 0..<12 {
                let flat = r.state.pages.joined().map(\.id)
                guard !flat.isEmpty else { break }
                let tile = flat[rng.next(flat.count)]
                walk(r, to: tile)
                let was = r.layout.items.map(describe).joined(separator: " "), sent = r.placed.count
                let k = rng.next(10), dirs = [(-1, 0), (1, 0), (0, 1), (0, -1)]
                var desc = ""
                if k < 4 { desc = "move \(dirs[k])"; _ = r.state.reorderKey(dx: dirs[k].0, dy: dirs[k].1, combine: false) }
                else if k < 8 { desc = "combine \(dirs[k - 4])"; _ = r.state.reorderKey(dx: dirs[k - 4].0, dy: dirs[k - 4].1, combine: true) }
                else { desc = "page \(k == 8 ? -1 : 1)"; r.state.reorder(tile: tile, .page(k == 8 ? -1 : 1)) }
                await grace(0.02)
                chords += 1
                writes += r.placed.count - sent
                let ctx = "seed \(seed) step \(step) \(tile) \(desc): \(was) -> \(r.layout.items.map(describe).joined(separator: " "))"
                if r.placedApps.sorted() != before { failures.append("lost or copied: \(ctx)") }
                if r.state.openFolder != nil { r.state.closeFolder() }
                guard let sel = r.state.selection, let entry = r.state.pages.joined().dropFirst(sel).first else { failures.append("no choice: \(ctx)"); continue }
                var holds = entry.id == tile
                if case .folder(_, _, let apps, _) = entry, apps.contains(where: { $0.id == tile }) { holds = true }
                if !holds { failures.append("the choice left the tile (\(entry.id)): \(ctx)") }
            }
        }
        XCTAssertGreaterThan(writes, chords / 4, "subject: the chords wrote a good share of the time (\(writes) of \(chords))")
        XCTAssertTrue(failures.isEmpty, failures.prefix(5).joined(separator: "\n"))
    }
}
