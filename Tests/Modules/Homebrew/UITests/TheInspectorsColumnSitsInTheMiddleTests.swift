import XCTest
import AppKit
import SwiftUI
import HelmContract
import HelmTestSupport
import HelmUI
@testable import Module_Homebrew_Engine
@testable import Module_Homebrew_UI

/// **Once the inspector's content is capped, the slack belongs to both sides.**
///
/// `HelmLayout.readingColumn` bounds what the package view draws to 444 pt so a
/// tile holding `3.6.4` is not a third of the window wide. That left the pane
/// wider than the column, and the block sat against the leading edge: measured
/// 2026-09-16 at the 984 pt pane the app draws, the column was 347…791 inside a
/// 335…984 inspector — 193 pt of empty pane down one side and 12 down the other.
/// A bounded column in a corner reads as a page that failed to fill rather than
/// as a column.
///
/// **Horizontally centred, vertically still at the top.** A detail pane fills
/// from the top; centring it vertically would float a two-line finding in the
/// middle of the pane, which is a different defect with the same cause.
///
/// **And centring is not a margin.** Below `HomebrewSplit`'s threshold the
/// inspector is narrower than the cap, so the block already fills it and there
/// is no slack to divide — the second case is that width, read as «the column is
/// exactly as wide as it was», because the narrow branch is where the page can
/// least afford a new inset.
///
/// **The instrument is the fact tiles' own wells.** They are `RoundedRectangle`
/// fills, which become `CALayer`s with a corner radius, and the grid they sit in
/// spans the bounded column — so the leftmost and rightmost of them are the
/// column's own edges, read in the host's coordinate space. Frames are converted
/// through the **layer** tree: a layer's `frame` is in its superlayer's space,
/// and asking an `NSView` to convert it instead reads a number that happens to
/// look plausible and moves with the wrong thing (found here by a reading that
/// shifted −245 pt where the control beside it shifted +90).
@MainActor
final class TheInspectorsColumnSitsInTheMiddleTests: XCTestCase {

    /// One installed formula and everything the package view needs to draw its
    /// second tier — the tiles are the instrument, so a fixture that earns none
    /// would leave every case below measuring nothing.
    private final class Cellar: EngineTransport, @unchecked Sendable {
        private let stream = AsyncStream<EngineEvent>.makeStream()
        var events: AsyncStream<EngineEvent> { stream.stream }

        static let openssl = BrewPackage(name: "openssl@3", version: "3.6.4", isCask: false)

        func send(_ command: EngineCommand) async throws -> Data {
            switch HomebrewCommand(rawValue: command.name) {
            case .status:
                return try JSONEncoder().encode(
                    BrewStatus(installed: true, brewPath: "/opt/fixture/bin/brew"))
            case .listInstalled: return try JSONEncoder().encode([Self.openssl])
            case .outdated: return try JSONEncoder().encode([OutdatedPackage]())
            case .descriptions: return try JSONEncoder().encode([String: String]())
            case .info:
                return try JSONEncoder().encode(
                    PackageInfo(name: "openssl@3", isCask: false,
                                desc: "Cryptography and SSL/TLS Toolkit",
                                homepage: "https://openssl-library.org", license: "Apache-2.0",
                                tap: "homebrew/core", latestVersion: "3.6.4",
                                installedVersion: "3.6.4",
                                installedAt: Date(timeIntervalSince1970: 1_757_700_000),
                                installedOnRequest: true, deprecationReason: nil,
                                replacement: nil, siblings: [], dependencies: [], caveats: nil))
            case .size: return try JSONEncoder().encode(41_353_216)
            default: return Data()
            }
        }
    }

    /// Where the bounded column's content begins and ends, and the pane it is
    /// in — both in the host's own points.
    private struct Column {
        let content: ClosedRange<CGFloat>
        let pane: ClosedRange<CGFloat>
        var width: CGFloat { content.upperBound - content.lowerBound }
        var before: CGFloat { content.lowerBound - pane.lowerBound }
        var after: CGFloat { pane.upperBound - content.upperBound }
    }

    /// Mounts the page at `width` with the fixture's package selected and reads
    /// the column out of it, or fails saying which half was not there.
    ///
    /// Light, named: an unnamed appearance is a reading of whatever this Mac is
    /// set to at this hour (`RenderedInk`'s reason).
    private func column(_ hb: HomebrewViewModel, _ mvm: ModuleViewModel, at width: CGFloat,
                        file: StaticString = #filePath, line: UInt = #line) -> Column? {
        hb.segment = .installed
        hb.select(Cellar.openssl.id)
        let mount = MountedRender(HomebrewSettingsPage(vm: mvm),
                                  width: width, height: 900, appearance: .aqua)
        mount.settle(30)
        defer { mount.drop() }

        // The inspector is the scroll view the package view is mounted in — the
        // list beside it is a `ListCoreScrollView`, which is a different class.
        guard let root = mount.host.layer else {
            XCTFail("the host has no layer to read", file: file, line: line)
            return nil
        }
        let panes = mount.host.everyView
            .filter { $0.appKitClassName.contains("HostingScrollView") }
            .map { $0.convert($0.bounds, to: mount.host) }
        guard panes.count == 1, let pane = panes.first else {
            XCTFail("""
                \(panes.count) scrolled panes drew at \(width) pt where the package view is \
                exactly one — the page's containers have moved and this is measuring whichever \
                of them the walk found
                """, file: file, line: line)
            return nil
        }

        var tiles: [CGRect] = []
        func walk(_ layer: CALayer) {
            if abs(layer.cornerRadius - HelmRadius.ctl) < 0.01 {
                let frame = layer.convert(layer.bounds, to: root)
                if frame.minX >= pane.minX, frame.maxX <= pane.maxX, frame.width > 100 {
                    tiles.append(frame)
                }
            }
            layer.sublayers?.forEach(walk)
        }
        walk(root)

        // The subject, before anything about where it sits: a fixture that
        // earned no tiles would make every measurement below read zero, and a
        // rule about two equal gaps is satisfied by no column at all.
        guard let low = tiles.map(\.minX).min(), let high = tiles.map(\.maxX).max(),
              tiles.count >= 2 else {
            XCTFail("""
                the package view drew \(tiles.count) fact tiles at \(width) pt, where this \
                fixture earns four — there is nothing here whose position could be measured
                """, file: file, line: line)
            return nil
        }
        return Column(content: low...high, pane: pane.minX...pane.maxX)
    }

    private func loaded() async -> (HomebrewViewModel, ModuleViewModel, Cellar) {
        let transport = Cellar()
        let mvm = ModuleViewModel(transport: transport)
        let hb = HomebrewViewModel.shared(vm: mvm)
        await hb.loadIfNeeded()
        hb.segment = .installed
        hb.select(Cellar.openssl.id)
        await hb.infoAsk?.value
        return (hb, mvm, transport)
    }

    /// The narrowest width `HomebrewSplit` answers `true` for, asked of the type
    /// rather than read off its private constant.
    private var threshold: CGFloat {
        for width in stride(from: CGFloat(200), through: 1400, by: 1)
        where HomebrewSplit(availableWidth: width).showsInspector { return width }
        return 0
    }

    /// **At the pane the app draws, the empty space falls on both sides.**
    func testTheColumnIsCentredWhereThePaneIsWiderThanIt() async {
        let (hb, mvm, transport) = await loaded()
        defer { withExtendedLifetime(transport) {} }
        guard let column = column(hb, mvm, at: 984) else { return }

        // Precondition, and it is the reason the rest of this case exists: the
        // pane really is wider than the cap. If the bound ever grew past the
        // pane there would be no slack to divide and this would pass on nothing.
        XCTAssertGreaterThan(column.before + column.after, 40, """
            the column fills its \(column.pane.upperBound - column.pane.lowerBound) pt pane at \
            984 pt, so «centred» and «against the leading edge» are the same picture and this \
            case cannot tell them apart
            """)
        XCTAssertEqual(column.before, column.after, accuracy: 1, """
            the bounded column sits \(Int(column.before)) pt from one edge of the inspector and \
            \(Int(column.after)) pt from the other — all the empty pane is down one side, which \
            is the reading this centring was made against
            """)
    }

    /// **And the narrow branch pays nothing for it.**
    ///
    /// Below the threshold the package view is the whole pane, which is narrower
    /// than the cap: there is no slack, so centring must not invent one. Read as
    /// «the same width as where there *is* slack», because that is the number a
    /// new inset would take from.
    func testCentringTakesNothingOffTheNarrowBranch() async {
        let (hb, mvm, transport) = await loaded()
        defer { withExtendedLifetime(transport) {} }
        let narrow = threshold - 60
        XCTAssertFalse(HomebrewSplit(availableWidth: narrow).showsInspector,
                       "precondition: \(narrow) pt is meant to be below the split")

        guard let wide = column(hb, mvm, at: 984), let tight = column(hb, mvm, at: narrow) else {
            return
        }
        XCTAssertEqual(tight.width, wide.width, accuracy: 1, """
            the column is \(Int(tight.width)) pt at \(narrow) pt where it is \(Int(wide.width)) pt \
            with room to spare — the narrow branch has paid a margin for a centring that has \
            nothing to centre
            """)
        XCTAssertEqual(tight.before, tight.after, accuracy: 1, """
            at \(narrow) pt the column sits \(Int(tight.before)) pt from one edge and \
            \(Int(tight.after)) from the other
            """)
    }

    /// **At the threshold itself the pane is narrower than the cap, and nothing
    /// moves at all.**
    ///
    /// This is the width the inspector is squeezed hardest at, and the one where
    /// a centring that behaved like a padding would show first: the column fills
    /// the pane, so both gaps are the block's own padding and neither grew.
    func testAtTheThresholdTheColumnStillFillsTheInspector() async {
        let (hb, mvm, transport) = await loaded()
        defer { withExtendedLifetime(transport) {} }
        guard let column = column(hb, mvm, at: threshold) else { return }

        XCTAssertLessThan(column.before + column.after, 2 * HelmSpace.s5 + 2, """
            the column leaves \(Int(column.before + column.after)) pt of the inspector empty at \
            the split's own threshold, where the pane is narrower than \
            \(Int(HelmLayout.readingColumn)) and the only gap should be the block's own padding
            """)
    }
}
