import XCTest
import AppKit
import SwiftUI
import HelmContract
import HelmTestSupport
import HelmUI
@testable import Module_Homebrew_Engine
@testable import Module_Homebrew_UI

/// **The verdict does not move when its answer arrives, and the line under it
/// stands on the page's own edge.**
///
/// Two defects, both found by measuring a photograph of the page and not by
/// reading it (`HomebrewHealthPage.verdict`):
///
/// - the row centred its text on the plate, so the title stood where the
///   number of lines put it — a wait with one line lower than the answer
///   that replaced it with two, and a refusal whose sentence wraps higher
///   again: a title that jumps at the moment the person starts reading it;
/// - the line that says a word typed into the field hid every finding sat 13 pt
///   inside the edge the plate and the cards stand on, a fourth left edge on a
///   page that already had three.
///
/// **Measured on a photograph of the page as it is mounted**: the first row
/// with a drawn pixel in the column right of the plate is where the title's
/// letters begin, and the first column with one in a band is where a line
/// begins. The titles differ in their letters (an ascender stands a point above
/// a capital), so the tolerance is a few points.
@MainActor
final class TheVerdictHoldsItsPlaceOnThePageTests: XCTestCase {

    /// Answers what the page asks; `brew doctor` either hangs, refuses (zero
    /// bytes on the wire) or answers with `issues`.
    private final class Bench: EngineTransport, @unchecked Sendable {
        private let stream = AsyncStream<EngineEvent>.makeStream()
        var events: AsyncStream<EngineEvent> { stream.stream }
        enum Doctor { case hanging, refusing, answering([DoctorIssue]) }
        let doctor: Doctor
        init(_ doctor: Doctor) { self.doctor = doctor }

        func send(_ command: EngineCommand) async throws -> Data {
            switch HomebrewCommand(rawValue: command.name) {
            case .status:
                return try JSONEncoder().encode(
                    BrewStatus(installed: true, brewPath: "/opt/fixture/bin/brew"))
            case .listInstalled: return try JSONEncoder().encode([BrewPackage]())
            case .outdated: return try JSONEncoder().encode([OutdatedPackage]())
            case .descriptions: return try JSONEncoder().encode([String: String]())
            case .doctor:
                switch doctor {
                case .hanging:
                    try await Task.sleep(nanoseconds: 60_000_000_000)
                    throw CancellationError()
                case .refusing: return Data()
                case let .answering(issues): return try JSONEncoder().encode(issues)
                }
            default: return Data()
            }
        }
    }

    private static let finding = DoctorIssue(
        severity: .caution, title: "Some installed formulae are deprecated or disabled.",
        body: "You should find replacements for the following formulae:\n\n  periphery")

    private static let width = 984
    private static let height = 700

    /// The page in one reading. `config` is never answered, so no card sits
    /// under the verdict and the bands below hold only what they are about.
    private func mounted(_ doctor: Bench.Doctor, query: String = "") async -> MountedRender {
        let bench = Bench(doctor)
        let mvm = ModuleViewModel(transport: bench)
        let hb = HomebrewViewModel.shared(vm: mvm)
        let mount = MountedRender(HomebrewSettingsPage(vm: mvm),
                                  width: CGFloat(Self.width), height: CGFloat(Self.height),
                                  appearance: .aqua)
        let loading = Task { @MainActor in await hb.loadIfNeeded() }
        hb.segment = .health
        let asking = Task { @MainActor in await hb.refreshDoctor() }
        if case .hanging = doctor {
            mount.settle(40)
        } else {
            await asking.value
            await loading.value
            hb.query = query
            mount.settle(40)
        }
        withExtendedLifetime(bench) {}
        return mount
    }

    // MARK: - Reading the photograph

    /// One mount photographed once, and read where a pixel is drawn — an alpha
    /// of a quarter or more. **Not `RenderedInk`'s sums**: the plate draws a
    /// soft shadow that starts a dozen points outside its edge, and a sum over
    /// a band counts it as ink, so the plate read as standing 4 pt left of and 10 pt
    /// above where it does. The shadow's alpha is a fraction of that; a glyph's
    /// stem and the plate are not.
    @MainActor private struct Photo {
        let rep: NSBitmapImageRep
        let scale: Double

        init?(_ mount: MountedRender) {
            let host = mount.host
            guard host.bounds.width > 0, host.bounds.height > 0,
                  let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return nil }
            host.cacheDisplay(in: host.bounds, to: rep)
            // The layout this reads a pixel by: eight bits, four samples, alpha last.
            guard rep.bitmapData != nil, rep.samplesPerPixel == 4, rep.bitsPerSample == 8,
                  !rep.bitmapFormat.contains(.alphaFirst) else { return nil }
            self.rep = rep
            self.scale = Double(rep.pixelsWide) / Double(host.bounds.width)
        }

        private func drawn(_ x: Int, _ y: Int) -> Bool {
            rep.bitmapData![y * rep.bytesPerRow + x * 4 + 3] >= 64
        }

        /// The topmost row, in points, with a drawn pixel in the columns (in points).
        func firstRow(columns: ClosedRange<Int>) -> Double? {
            let xs = Int(Double(columns.lowerBound) * scale)..<min(rep.pixelsWide, Int(Double(columns.upperBound) * scale))
            for y in 0..<rep.pixelsHigh where xs.contains(where: { drawn($0, y) }) {
                return Double(y) / scale
            }
            return nil
        }

        /// The leftmost column, in points, with a drawn pixel in the rows (in points).
        func firstColumn(rows: ClosedRange<Int>) -> Double? {
            let ys = Int(Double(rows.lowerBound) * scale)..<min(rep.pixelsHigh, Int(Double(rows.upperBound) * scale))
            for x in 0..<rep.pixelsWide where ys.contains(where: { drawn(x, $0) }) {
                return Double(x) / scale
            }
            return nil
        }
    }

    /// Where the page's column begins and where its first block does: the
    /// left edge of what is drawn on the page's first row, and that row.
    private func edge(_ photo: Photo) -> (left: Double, top: Double)? {
        guard let top = photo.firstRow(columns: 0...(Self.width - 1)),
              let left = photo.firstColumn(rows: Int(top)...(Int(top) + 8)) else { return nil }
        return (left, top)
    }

    /// The row where the title's letters begin: the columns right of the plate
    /// slot, which is 44 pt and the step after it.
    private func titleTop(_ photo: Photo, edge: Double) -> Double? {
        photo.firstRow(columns: (Int(edge) + 44 + Int(HelmSpace.s5) + 2)...(Self.width - 1))
    }

    // MARK: - The title

    /// **Every state of the verdict puts its title on one row.** Waiting, clean,
    /// findings and refused are four readings of one question, and a title that
    /// stands lower in the first than in the rest is the wait's sentence
    /// jumping at the moment the answer lands. Two languages, because the
    /// refusal's sentence is one line in one and two in the other, and a
    /// wrapped title is the case a fix that only kept a line's room would miss.
    func testTheTitleStandsOnOneRowInEveryReading() async {
        for language in [AppLanguage.en, .ru] {
            await AppLanguage.only(language) {
                let waiting = await mounted(.hanging)
                let clean = await mounted(.answering([]))
                let found = await mounted(.answering([Self.finding]))
                let refused = await mounted(.refusing)
                defer { waiting.drop(); clean.drop(); found.drop(); refused.drop() }

                // The plate of an answer stands on the page's edge, and the
                // wait's spinner sits inside the same slot: one edge for all.
                guard let photo = Photo(found), let edge = edge(photo)?.left else {
                    return XCTFail("\(language.rawValue): the verdict drew nothing to measure from")
                }
                // The subject first: a page that drew no title cannot be said
                // to have kept it still.
                let readings: [(String, Double?)] = [("waiting", waiting), ("clean", clean),
                                                     ("findings", found), ("refused", refused)]
                    .map { name, mount in (name, Photo(mount).flatMap { titleTop($0, edge: edge) }) }
                for (name, row) in readings {
                    XCTAssertNotNil(row, "\(language.rawValue): the \(name) verdict drew no title")
                }
                guard let anchor = readings[0].1 else { return }
                for (name, row) in readings.dropFirst() {
                    guard let row else { continue }
                    XCTAssertLessThanOrEqual(abs(row - anchor), 3, """
                        \(language.rawValue): the title of the \(name) verdict begins at \(row) pt \
                        and the wait's at \(anchor) pt — it moves when the answer arrives
                        """)
                }
            }
        }
    }

    // MARK: - The line under the verdict

    /// **The line that says the field hid every finding starts on the edge the
    /// plate stands on.** That edge is the page's column: the verdict's plate
    /// and both cards begin on it, and a line of text of its own is the one
    /// thing on the page that has no reason to stand anywhere else.
    func testTheNothingMatchedLineStandsOnThePagesEdge() async {
        await AppLanguage.only(.en) {
            let mount = await mounted(.answering([Self.finding]), query: "zzzz-matches-nothing")
            defer { mount.drop() }

            guard let photo = Photo(mount), let plate = edge(photo) else {
                return XCTFail("the verdict drew no plate, so there is no edge to compare to")
            }
            // The verdict is the plate's height; the line is under it, past
            // the step between two blocks and above the status line.
            let top = Int(plate.top) + 44 + 4
            guard let left = photo.firstColumn(rows: top...(top + 60)) else {
                return XCTFail("nothing is drawn under the verdict — the line is not on the page")
            }
            XCTAssertLessThanOrEqual(abs(left - plate.left), 2, """
                the line starts at \(left) pt and the plate, which stands on the page's edge, at \
                \(plate.left) pt
                """)
        }
    }
}
