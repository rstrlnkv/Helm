import AppKit
import CryptoKit
import HelmRuntime
import HelmTestSupport
import HelmUI
import SwiftUI
import XCTest
@testable import HelmApp

/// **Every module page of Helm in every state a fixture can build, and the Log
/// page and About in two states each, written out as a picture** — for a person
/// to look at before judging or changing a screen. The General page is not
/// written: no case here mounts it.
///
/// `HELM_FRAMES_DIR=<folder>` writes one PNG per page × state × appearance ×
/// language × width, named `<page>-<state>-<light|dark>-<lang>-<width>.png` and
/// read from the right: the width, the language (`en`, `ru`, `de`), the
/// appearance, the state, and what is left is the page — a module's id as the
/// registry spells it (`keep-awake` carries its own hyphen), or `log`, or
/// `about`. A state holds no hyphen: its words are joined by a full stop, and
/// only the axes that change that page are named — and `unwired`, which is
/// always named. Without the variable every case here skips out loud — a run
/// that wrote nothing says `SKIPPED`, not passed.
///
/// **The states are the ones `ModulePageRender.page(for:…)` can build**: the
/// wire (`answering` or `unwired`, written `wired` and `unwired`), the seed
/// (`pastFirstRun` or `configured`, written `unconfigured` and `configured`), the
/// priming (`opened` or `unprimed`, written `primed` and `unprimed`) and the
/// grants (all three held or all three withheld, written `granted` and
/// `withheld`). Not every combination draws a different page, and a folder of
/// sixteen identical pictures per module is no help to anyone, so the table
/// `drawn` below names for each module the states that are written and, for each
/// state not written, the written one it is the same picture as. That table is a
/// claim, and `testTheDroppedCombinationsDrawTheSamePage` is what holds it: an
/// axis whose two fixtures are the same value for a module is dead for it and is
/// told with no render, from the fixtures' own values; every combination of the
/// live axes, with both grants, is then drawn once and told apart by a digest of
/// its pixels. The case prints what it found, and a module added to the registry
/// with no row in the table is red there.
///
/// **Six modules have no answering fixture** — Keep Awake, Uninstaller,
/// Screenshots, Disk, Autopilot and Hosts: `ModulePageRender.answering` has
/// nothing to say for them, so every page of theirs is drawn over the empty wire
/// and every state of theirs is written `unwired`. For Uninstaller that is the
/// failed read of its application list ("Helm could not read the list of
/// applications."), for Disk the volume list nobody answered ("Helm got no
/// answer, so this may not be every volume."), for Hosts the empty key list.
///
/// **The grants are this family's own two values, naming all three** —
/// `ModulePageRender.granted` and `withheld` leave Screen Recording to be asked of
/// the machine, and a frame is not a fact about the screen-recording grant of
/// whoever ran it.
///
/// **A module page is its opening tab.** The other tabs are not among the four
/// axes, so no frame shows them.
///
/// **The two widths** are the settings column (`ModulePageRender.pageWidth`) and
/// the pane of the narrowest window: `SettingsWindow`'s `minSize` width, which is
/// private and is read out of the source the way
/// `TheNarrowPaneCanStillActOnAPackageTests` reads it, less the expanded sidebar
/// and the card's inset, through `ShellGeometry.cardFrame`. The pattern finding
/// nothing is a failure, not a skip.
///
/// **The height is the pane's, grown by what a page scrolls.** The pane is the
/// card of a default-sized window (`cardFrame` of `SettingsWindow.defaultSize`;
/// the toolbar's band is not taken off). A page taller than that is a scroll
/// view whose document is taller than what shows; the host is grown by the
/// largest such overflow of an outermost scroll view, up to
/// `ModulePageRender.pageHeight`, and looked at again — three growths at most. A
/// page shorter than the pane is written at the pane's height.
/// **A table is tiled before its document is read.** The host is reframed from
/// the mount's `pageHeight` to the pane, and the document of Duplicates' list
/// kept the height it had at the mount for as long as it was watched: an
/// overflow that was never there, which grew the host to the cap, the list at
/// the top and blank between it and the bar. `NSTableView.tile()` sizes the
/// document to what the table holds and to its clip, so `settle` calls it
/// before each reading.
///
/// **A frame is refused, and no file is made, for four things**: a view that drew
/// nothing, a view whose appearance is not the one asked for, a ground under the
/// page on the other side of the appearance asked (`StillFrame` says how it is
/// read), and a frame as tall as `ModulePageRender.pageHeight`, which is the
/// mount and not a page. The `[frames]` line counts the last.
///
/// **Known to read the machine or the process, with no seam:** About draws the
/// version and build of the process the cases run in, which are a test runner's
/// and not Helm's, and the update channel read from that process's defaults; the
/// Screenshots page draws a save folder inside the test process's scratch home,
/// so its frames differ from run to run; Layout's apps row counts the built-in
/// refused applications this Mac has installed; and the Log page writes the fixed
/// instants of its lines in this Mac's time zone.
@MainActor
final class EveryPageIsWrittenAsAPictureTests: XCTestCase {

    // MARK: - What a frame is asked

    private static let languages: [AppLanguage] = [.en, .ru, .de]

    /// All three grants held, and all three withheld — named, never asked of the
    /// machine.
    private static let granted = HelmGrants(accessibility: .granted, fullDisk: .granted,
                                            screenRecording: .granted)
    private static let withheld = HelmGrants(accessibility: .denied, fullDisk: .denied,
                                             screenRecording: .denied)

    /// The card of a window opened at its default size, with the sidebar open.
    private static let pane = ShellGeometry.cardFrame(
        in: SettingsWindow.defaultSize, sidebarWidth: ShellGeometry.defaultSidebarWidth).height

    private struct Unread: Error, CustomStringConvertible {
        let description: String
    }

    /// The width of the narrowest pane, and where it came from. `minSize` is
    /// private in `SettingsWindow`, so the number is read out of its source; the
    /// pattern must find exactly one.
    private static func narrowPane() throws -> (width: CGFloat, source: String) {
        let path = "Sources/HelmApp/SettingsWindow.swift"
        let pattern = #"minSize = NSSize\(width: ([0-9.]+)"#
        let text = try RepoSource.text(of: path)
        let found = try NSRegularExpression(pattern: pattern)
            .matches(in: text, range: NSRange(text.startIndex..., in: text))
        guard found.count == 1, let range = Range(found[0].range(at: 1), in: text),
              let minimum = Double(text[range]) else {
            throw Unread(description: """
                \(path) has \(found.count) matches for `\(pattern)` where this reads exactly one — \
                the window's minimum width has moved and the narrow pane cannot be computed
                """)
        }
        let width = ShellGeometry.cardFrame(
            in: CGSize(width: minimum, height: SettingsWindow.defaultSize.height),
            sidebarWidth: ShellGeometry.defaultSidebarWidth).width
        return (width, "\(Int(minimum)) from minSize in \(path) less the sidebar "
            + "\(Int(ShellGeometry.defaultSidebarWidth)) and the inset \(Int(ShellGeometry.inset))")
    }

    // MARK: - The line

    private static var written = 0
    private static var began = Date()
    private static var scale: CGFloat?
    private static var narrow: (width: CGFloat, source: String)?
    private static var heights: [String: CGFloat] = [:]
    private static var refused: [String] = []
    private static var folder: String?
    private static var settles = 0
    private static var unsettled = 0
    /// How many times `settle` pumps the run loop before it gives up agreeing.
    private static let turns = 40

    override class func setUp() {
        super.setUp()
        MainActor.assumeIsolated { began = Date() }
    }

    override class func tearDown() {
        MainActor.assumeIsolated {
            if written == 0 {
                print("[frames] none written: HELM_FRAMES_DIR is not set or no case wrote one")
            } else {
                let seconds = Int(Date().timeIntervalSince(began).rounded())
                let tall = heights.values.max() ?? 0, short = heights.values.min() ?? 0
                print("""
                    [frames] \(written) written, \(seconds) s for the cases that ran, at scale \
                    \(scale.map { "\($0)" } ?? "unread") to \(folder ?? "?"); widths \
                    \(Int(ModulePageRender.pageWidth)) (the settings column) and \
                    \(narrow.map { "\(Int($0.width)) (\($0.source))" } ?? "unread"); \
                    heights \(Int(short))…\(Int(tall)) pt, \(refused.count) refused at the \
                    \(Int(ModulePageRender.pageHeight)) pt cap\(refused.isEmpty ? "" : ": \(refused.sorted())"); \
                    \(unsettled) of \(settles) settles ran out of their \(turns) turns
                    """)
            }
        }
        super.tearDown()
    }

    override func tearDown() {
        AppLanguage.override = nil
        super.tearDown()
    }

    private func requireTheFolder() throws {
        let directory = try StillFrame.directory
        try XCTSkipIf(directory == nil, "a picture only: HELM_FRAMES_DIR is not set")
    }

    // MARK: - One combination of what a page is opened on

    private enum Axis: String, CaseIterable {
        case wire, seed, priming
    }

    /// The four things `ModulePageRender.page(for:…)` is opened on, each at one of
    /// its two fixtures. The default is the harness's own: answering, past the
    /// first run, opened, granted.
    private struct Cell: Hashable {
        var wired = true
        var configured = false
        var primed = true
        var granted = true

        /// `wired.unconfigured.primed.granted` — the form the table is written in.
        var spelling: String { words.joined(separator: ".") }

        var words: [String] {
            [wired ? "wired" : "unwired", configured ? "configured" : "unconfigured",
             primed ? "primed" : "unprimed", granted ? "granted" : "withheld"]
        }

        init() {}

        init(spelling: String) {
            let parts = spelling.split(separator: ".").map(String.init)
            wired = parts[0] == "wired"
            configured = parts[1] == "configured"
            primed = parts[2] == "primed"
            granted = parts[3] == "granted"
        }
    }

    private static func page(_ descriptor: any ModuleDescriptor, _ cell: Cell,
                             in appearance: NSAppearance.Name,
                             width: CGFloat) -> ModulePageRender.Page {
        ModulePageRender.page(
            for: descriptor, in: appearance, width: width,
            seededBy: cell.configured ? ModulePageRender.configured : ModulePageRender.pastFirstRun,
            wiredBy: cell.wired ? ModulePageRender.answering : ModulePageRender.unwired,
            primedBy: cell.primed ? ModulePageRender.opened : ModulePageRender.unprimed,
            granting: cell.granted ? granted : withheld)
    }

    // MARK: - Which combinations are written

    private struct Row {
        /// Axes whose two fixtures are the same value for this module.
        let dead: Set<Axis>
        /// The combinations that are written, in the order the live axes are
        /// enumerated (default first).
        let kept: [String]
        /// Each combination of the live axes that is not written, and the written
        /// one it is the same picture as.
        let same: [String: String]
    }

    /// What `testTheDroppedCombinationsDrawTheSamePage` found, as it printed it.
    /// Sixteen combinations a module; every combination left out is either on an
    /// axis the module leaves dead or is listed under `same`.
    private static let drawn: [String: Row] = [
        "keep-awake": Row(
            dead: [.priming, .wire],
            kept: ["unwired.unconfigured.primed.granted", "unwired.configured.primed.granted",
                   "unwired.configured.primed.withheld"],
            same: ["unwired.unconfigured.primed.withheld": "unwired.unconfigured.primed.granted"]),
        "vpn": Row(
            dead: [.priming],
            kept: ["wired.unconfigured.primed.granted", "wired.configured.primed.granted",
                   "unwired.unconfigured.primed.granted"],
            same: ["unwired.configured.primed.granted": "unwired.unconfigured.primed.granted",
                   "unwired.configured.primed.withheld": "unwired.unconfigured.primed.granted",
                   "unwired.unconfigured.primed.withheld": "unwired.unconfigured.primed.granted",
                   "wired.configured.primed.withheld": "wired.configured.primed.granted",
                   "wired.unconfigured.primed.withheld": "wired.unconfigured.primed.granted"]),
        "uninstaller": Row(
            dead: [.priming, .seed, .wire],
            kept: ["unwired.unconfigured.primed.granted", "unwired.unconfigured.primed.withheld"],
            same: [:]),
        "screenshots": Row(
            dead: [.priming, .seed, .wire],
            kept: ["unwired.unconfigured.primed.granted", "unwired.unconfigured.primed.withheld"],
            same: [:]),
        "homebrew": Row(
            dead: [.priming, .seed],
            kept: ["wired.unconfigured.primed.granted", "unwired.unconfigured.primed.granted"],
            same: ["unwired.unconfigured.primed.withheld": "unwired.unconfigured.primed.granted",
                   "wired.unconfigured.primed.withheld": "wired.unconfigured.primed.granted"]),
        "leftovers": Row(
            dead: [.seed],
            kept: ["wired.unconfigured.primed.granted", "wired.unconfigured.primed.withheld",
                   "wired.unconfigured.unprimed.granted", "wired.unconfigured.unprimed.withheld"],
            same: ["unwired.unconfigured.primed.granted": "wired.unconfigured.unprimed.granted",
                   "unwired.unconfigured.primed.withheld": "wired.unconfigured.unprimed.withheld",
                   "unwired.unconfigured.unprimed.granted": "wired.unconfigured.unprimed.granted",
                   "unwired.unconfigured.unprimed.withheld": "wired.unconfigured.unprimed.withheld"]),
        "disk": Row(
            dead: [.priming, .seed, .wire],
            kept: ["unwired.unconfigured.primed.granted", "unwired.unconfigured.primed.withheld"],
            same: [:]),
        "duplicates": Row(
            dead: [],
            kept: ["wired.unconfigured.primed.granted", "wired.unconfigured.primed.withheld",
                   "wired.configured.primed.granted", "wired.configured.primed.withheld",
                   "wired.configured.unprimed.granted", "wired.configured.unprimed.withheld",
                   "unwired.configured.primed.granted", "unwired.configured.primed.withheld"],
            same: ["unwired.configured.unprimed.granted": "wired.configured.unprimed.granted",
                   "unwired.configured.unprimed.withheld": "wired.configured.unprimed.withheld",
                   "unwired.unconfigured.primed.granted": "wired.unconfigured.primed.granted",
                   "unwired.unconfigured.primed.withheld": "wired.unconfigured.primed.withheld",
                   "unwired.unconfigured.unprimed.granted": "wired.unconfigured.primed.granted",
                   "unwired.unconfigured.unprimed.withheld": "wired.unconfigured.primed.withheld",
                   "wired.unconfigured.unprimed.granted": "wired.unconfigured.primed.granted",
                   "wired.unconfigured.unprimed.withheld": "wired.unconfigured.primed.withheld"]),
        "autopilot": Row(
            dead: [.priming, .seed, .wire],
            kept: ["unwired.unconfigured.primed.granted", "unwired.unconfigured.primed.withheld"],
            same: [:]),
        "layout": Row(
            dead: [.priming, .seed],
            kept: ["wired.unconfigured.primed.granted", "wired.unconfigured.primed.withheld",
                   "unwired.unconfigured.primed.granted", "unwired.unconfigured.primed.withheld"],
            same: [:]),
        "hosts": Row(
            dead: [.priming, .seed, .wire],
            kept: ["unwired.unconfigured.primed.granted"],
            same: ["unwired.unconfigured.primed.withheld": "unwired.unconfigured.primed.granted"]),
    ]

    /// The name a kept state is written under: the words of the axes that differ
    /// among this module's kept states, joined by a full stop, and `unwired`
    /// whether or not it differs — a page drawn with no answers says so.
    private static func stateName(_ spelling: String, among kept: [String]) -> String {
        let words = spelling.split(separator: ".").map(String.init)
        return words.indices.filter { axis in
            (axis == 0 && words[0] == "unwired")
                || Set(kept.map { $0.split(separator: ".").map(String.init)[axis] }).count > 1
        }.map { words[$0] }.joined(separator: ".")
    }

    // MARK: - Telling the dropped combinations

    /// Which axes of a module are told dead by the fixtures' own values, with no
    /// render: nothing on the wire for it, two seeds that write equal stores, no
    /// priming for it.
    private static func liveAxes(of id: String, asking vm: ModuleViewModel) -> Set<Axis> {
        var live: Set<Axis> = []
        let wire = ModulePageRender.answering(id)
        if !wire.replies.isEmpty || !wire.events.isEmpty { live.insert(.wire) }
        let plain = InMemoryKeyValueStore(), seeded = InMemoryKeyValueStore()
        ModulePageRender.pastFirstRun(id, NamespacedStore(namespace: id, backing: plain))
        ModulePageRender.configured(id, NamespacedStore(namespace: id, backing: seeded))
        if !NSDictionary(dictionary: plain.raw).isEqual(to: seeded.raw) { live.insert(.seed) }
        if ModulePageRender.opened(id, vm) != nil { live.insert(.priming) }
        return live
    }

    /// Every combination of the live axes with both grants, default first, the
    /// dead axes held at the harness's default — and a dead wire held `unwired`,
    /// since a module with nothing to answer is drawn over the empty wire.
    private static func candidates(_ live: Set<Axis>) -> [Cell] {
        var out: [Cell] = []
        for wired in live.contains(.wire) ? [true, false] : [false] {
            for configured in live.contains(.seed) ? [false, true] : [false] {
                for primed in live.contains(.priming) ? [true, false] : [true] {
                    for granted in [true, false] {
                        var cell = Cell()
                        cell.wired = wired
                        cell.configured = configured
                        cell.primed = primed
                        cell.granted = granted
                        out.append(cell)
                    }
                }
            }
        }
        return out
    }

    /// What a combination draws at the settings column in light and English, as a
    /// digest: the page as the mount comes, with nothing cropped.
    private func digest(_ descriptor: any ModuleDescriptor, _ cell: Cell) -> String {
        autoreleasepool {
            var out = ""
            AppLanguage.only(.en) {
                let page = Self.page(descriptor, cell, in: .aqua, width: ModulePageRender.pageWidth)
                defer { page.host.window?.contentView = nil }
                if let bytes = RenderedInk.bytes(page.host) {
                    out = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
                }
            }
            return out
        }
    }

    func testTheDroppedCombinationsDrawTheSamePage() throws {
        try requireTheFolder()
        let ids = ModuleRegistry.all.map { type(of: $0).id.rawValue }
        XCTAssertEqual(Set(Self.drawn.keys), Set(ids), """
            the table `drawn` and `ModuleRegistry.all` name different modules — a module with no \
            row is a module nobody has told which of its states draw a different page
            """)
        let vm = ModuleViewModel(transport: FixtureTransport(ModulePageRender.unwired("")))
        for descriptor in ModuleRegistry.all {
            let id = type(of: descriptor).id.rawValue
            let live = Self.liveAxes(of: id, asking: vm)
            var classes: [(digest: String, cells: [String])] = []
            for cell in Self.candidates(live) {
                let seen = digest(descriptor, cell)
                XCTAssertFalse(seen.isEmpty, "\(id) \(cell.spelling): nothing was drawn")
                if let at = classes.firstIndex(where: { $0.digest == seen }) {
                    classes[at].cells.append(cell.spelling)
                } else {
                    classes.append((seen, [cell.spelling]))
                }
            }
            let kept = classes.map { $0.cells[0] }
            var same: [String: String] = [:]
            for found in classes { for other in found.cells.dropFirst() { same[other] = found.cells[0] } }
            let dead = Set(Axis.allCases).subtracting(live)
            print("""
                [told] \(id): dead \(dead.map(\.rawValue).sorted()); \(Self.candidates(live).count) \
                drawn, \(kept.count) different; kept \(kept); same \
                \(same.sorted { $0.key < $1.key }.map { "\($0.key) = \($0.value)" })
                """)
            guard let row = Self.drawn[id] else { continue }
            XCTAssertEqual(row.dead, dead, "\(id): the axes the fixtures leave dead have changed")
            XCTAssertEqual(row.kept, kept, "\(id): the states that draw a different page have changed")
            XCTAssertEqual(row.same, same, "\(id): the dropped states are not the pages the table says")
        }
    }

    // MARK: - Writing

    /// Grows `host` from the pane to what its outermost scroll views hold.
    private static func fit(_ host: NSView, width: CGFloat) -> (height: CGFloat, atCap: Bool) {
        host.frame = NSRect(x: 0, y: 0, width: width, height: pane)
        settle(host)
        for _ in 0..<3 {
            let more = overflow(of: host)
            guard more > 0.5 else { break }
            let height = min(host.frame.height + more, ModulePageRender.pageHeight)
            guard height > host.frame.height else { break }
            host.frame = NSRect(x: 0, y: 0, width: width, height: height)
            settle(host)
        }
        return (host.frame.height, host.frame.height >= ModulePageRender.pageHeight)
    }

    /// Every outermost scroll view: one inside another is the inner page's own
    /// business, and the outer one is what the frame is sized by.
    private static func outermostScrolls(of host: NSView) -> [NSScrollView] {
        host.everyViewWithAncestry.compactMap { entry in
            guard let scroll = entry.view as? NSScrollView,
                  !entry.ancestry.contains(where: { $0 is NSScrollView }) else { return nil }
            return scroll
        }
    }

    /// The largest amount an outermost scroll view's document is taller than what
    /// it shows.
    private static func overflow(of host: NSView) -> CGFloat {
        outermostScrolls(of: host).compactMap { scroll in
            scroll.documentView.map { $0.frame.height - scroll.contentView.bounds.height }
        }.max() ?? 0
    }

    /// Pump until two consecutive readings of the pixels **and of the scroll
    /// overflow** agree. The overflow is part of the reading because `fit` sizes
    /// the frame off it, and a reading that is still moving would size the frame
    /// off a number about to change. **A table that is an outermost scroll view's
    /// document is tiled before it is read**: reframed, the table of Duplicates'
    /// list kept the height its document had before for as long as it was
    /// watched, and that stale height reads as an overflow that nothing draws.
    /// Running out of the bound is not a failure: the `[frames]` line says how
    /// many did.
    private static func settle(_ host: NSView) {
        var previous: (pixels: Data?, overflow: CGFloat)?
        settles += 1
        for _ in 0..<turns {
            host.layoutSubtreeIfNeeded()
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
            for scroll in outermostScrolls(of: host) { (scroll.documentView as? NSTableView)?.tile() }
            let now = (pixels: RenderedInk.bytes(host), overflow: overflow(of: host))
            if let previous, now.pixels != nil, now.pixels == previous.pixels,
               now.overflow == previous.overflow { return }
            previous = now
        }
        unsettled += 1
    }

    private func name(_ page: String, _ state: String, _ appearance: NSAppearance.Name,
                      _ language: AppLanguage, _ width: CGFloat) -> String {
        "\(page)-\(state)-\(RenderedInk.label(of: appearance))-\(language.rawValue)-\(Int(width))"
    }

    /// A frame as tall as the mount is the mount and not a page: the rule that
    /// sizes a frame has run into the cap, and nothing says where the page ends.
    private struct AsTallAsTheMount: Error, CustomStringConvertible {
        let height: CGFloat
        var description: String { "\(Int(height)) pt is the mount's height — the page was not sized" }
    }

    /// Fits `host` and writes it, or throws; an older file of that name is removed first, and the throw says so when it could not be.
    private static func put(_ host: NSView, named name: String, in appearance: NSAppearance.Name,
                            width: CGFloat) throws {
        let fitted = fit(host, width: width)
        guard !fitted.atCap else {
            try StillFrame.clear(named: name)
            throw AsTallAsTheMount(height: fitted.height)
        }
        guard let url = try StillFrame.write(host, in: appearance, named: name) else { return }
        written += 1
        folder = url.deletingLastPathComponent().path
        heights[name] = fitted.height
        if scale == nil, let data = try? Data(contentsOf: url), let rep = NSBitmapImageRep(data: data) {
            scale = CGFloat(rep.pixelsWide) / width
        }
    }

    /// A refusal is a failure naming the frame.
    private func write(_ host: NSView, named name: String, in appearance: NSAppearance.Name,
                       width: CGFloat) {
        do {
            try Self.put(host, named: name, in: appearance, width: width)
        } catch {
            if error is AsTallAsTheMount { Self.refused.append(name) }
            XCTFail("\(name): not written — \(error)")
        }
    }

    /// Both appearances, the three languages and the two widths of one thing.
    private func eachFrame(_ body: (NSAppearance.Name, AppLanguage, CGFloat) -> Void) throws {
        let narrow = try Self.narrowPane()
        Self.narrow = narrow
        XCTAssertLessThan(narrow.width, ModulePageRender.pageWidth,
                          "the narrow pane is not narrower than the settings column")
        for appearance in RenderedInk.bothAppearances {
            for language in Self.languages {
                for width in [ModulePageRender.pageWidth, narrow.width] {
                    body(appearance, language, width)
                }
            }
        }
    }

    /// The module pages in three cases by their place in `ModuleRegistry.all`, so
    /// that a part of them can be written by one command: the last case takes
    /// whatever follows the eighth, so a module added later is written by it.
    func testTheFirstFiveModulePagesAreWritten() throws {
        try writeModulePages(ModuleRegistry.all.prefix(5))
    }

    func testTheNextThreeModulePagesAreWritten() throws {
        try writeModulePages(ModuleRegistry.all.dropFirst(5).prefix(3))
    }

    func testTheRestOfTheModulePagesAreWritten() throws {
        try writeModulePages(ModuleRegistry.all.dropFirst(8))
    }

    private func writeModulePages(_ descriptors: some Sequence<any ModuleDescriptor>) throws {
        try requireTheFolder()
        for descriptor in descriptors {
            let id = type(of: descriptor).id.rawValue
            guard let row = Self.drawn[id], !row.kept.isEmpty else {
                XCTFail("\(id): the table `drawn` names no state to write")
                continue
            }
            let states = row.kept.map { (spelling: $0, name: Self.stateName($0, among: row.kept)) }
            for state in states {
                XCTAssertEqual(
                    state.name.split(separator: ".").contains("unwired"), !Cell(spelling: state.spelling).wired,
                    "\(id) \(state.spelling) is written as `\(state.name)`, which does not say if the wire was empty")
            }
            try eachFrame { appearance, language, width in
                for state in states {
                    autoreleasepool {
                        AppLanguage.only(language) {
                            let page = Self.page(descriptor, Cell(spelling: state.spelling), in: appearance,
                                                 width: width)
                            defer { page.host.window?.contentView = nil }
                            write(page.host,
                                  named: name(id, state.name, appearance, language, width),
                                  in: appearance, width: width)
                        }
                    }
                }
            }
        }
    }

    // MARK: - The Log page and About

    func testTheLogPageIsWrittenWithLinesAndEmpty() throws {
        try requireTheFolder()
        let lines = LogPageUnderHand.log(40).lines
        let states: [(String, [LogEntry], Bool)] = [("lines", lines, true), ("empty", [], false)]
        try eachFrame { appearance, language, width in
            for (state, entries, stored) in states {
                autoreleasepool {
                    AppLanguage.only(language) {
                        let mount = MountedRender(LogView(source: { entries }, storedLog: { stored }),
                                                  width: width, height: Self.pane,
                                                  appearance: appearance)
                        defer { mount.drop() }
                        write(mount.host, named: name("log", state, appearance, language, width),
                              in: appearance, width: width)
                    }
                }
            }
        }
    }

    func testAboutIsWrittenWithTheOfferAndTheRefusal() throws {
        try requireTheFolder()
        let release = UpdateService.Release(
            version: "9.9.9", pageURL: URL(string: "https://example.invalid/releases/9.9.9")!,
            zipURL: URL(string: "https://example.invalid/Helm.zip")!, downloadURL: nil,
            notes: "no digest line here")
        let states = ["offer", "refusal"]
        try eachFrame { appearance, language, width in
            for state in states {
                autoreleasepool {
                    AppLanguage.only(language) {
                        let updater = UpdateService(
                            available: release, store: AppSettings.store.over(InMemoryKeyValueStore()))
                        if state == "refusal" { updater.noteManualInstall() }
                        let mount = MountedRender(AboutHelmView(updater: updater), width: width,
                                                  height: Self.pane, appearance: appearance)
                        defer { mount.drop() }
                        write(mount.host, named: name("about", state, appearance, language, width),
                              in: appearance, width: width)
                    }
                }
            }
        }
    }

    // MARK: - The refusals

    /// A view that fills a rectangle, so a frame of it has ink.
    private final class Swatch: NSView {
        override func draw(_ dirtyRect: NSRect) {
            NSColor.systemRed.setFill()
            bounds.insetBy(dx: 10, dy: 10).fill()
        }
    }

    private func refusalFile(_ name: String) throws -> URL {
        URL(fileURLWithPath: try XCTUnwrap(StillFrame.directory)).appendingPathComponent("\(name).png")
    }

    /// An older file of this name in the folder, so that a refusal has something
    /// to leave behind; removed again whatever the case finds.
    private func olderFile(_ name: String) throws -> URL {
        let file = try refusalFile(name)
        XCTAssertTrue(FileManager.default.createFile(atPath: file.path, contents: Data("older".utf8)),
                      "the older file could not be made, so this case proves nothing")
        addTeardownBlock { try? FileManager.default.removeItem(at: file) }
        return file
    }

    /// **A view that drew nothing is refused and no file is made.** The instrument
    /// first: the same call on a view that does draw writes its file (removed
    /// again, so the folder holds frames only).
    func testAFrameThatDrewNothingIsRefusedAndNothingIsWritten() throws {
        try requireTheFolder()
        let drawing = Swatch(frame: NSRect(x: 0, y: 0, width: 120, height: 80))
        drawing.appearance = NSAppearance(named: .aqua)
        let control = try refusalFile("refusal-control-drew-something")
        defer { try? FileManager.default.removeItem(at: control) }
        XCTAssertNotNil(try StillFrame.write(drawing, in: .aqua, named: "refusal-control-drew-something"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: control.path),
                      "the control drew ink and no file was written, so this case proves nothing")

        let blank = NSView(frame: NSRect(x: 0, y: 0, width: 120, height: 80))
        blank.appearance = NSAppearance(named: .aqua)
        let file = try olderFile("refusal-drew-nothing")
        XCTAssertThrowsError(try StillFrame.write(blank, in: .aqua, named: "refusal-drew-nothing")) {
            XCTAssertEqual($0 as? StillFrame.Refusal, .nothingDrawn)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path),
                       "a frame that drew nothing left a file of its name")
    }

    /// **A light page asked for as a dark one is refused and no file is made** —
    /// the dark frame asked for and the light one written.
    func testADarkFrameAskedForAndALightOneDrawnIsRefused() throws {
        try requireTheFolder()
        let mount = MountedRender(Text("a light page"), width: 200, height: 60, appearance: .aqua)
        defer { mount.drop() }
        mount.settle(10)
        let control = try refusalFile("refusal-control-light")
        defer { try? FileManager.default.removeItem(at: control) }
        XCTAssertNotNil(try StillFrame.write(mount.host, in: .aqua, named: "refusal-control-light"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: control.path),
                      "the light page asked for as light was not written, so this case proves nothing")

        let file = try olderFile("refusal-wrong-appearance")
        XCTAssertThrowsError(try StillFrame.write(mount.host, in: .darkAqua,
                                                  named: "refusal-wrong-appearance")) {
            XCTAssertEqual($0 as? StillFrame.Refusal, .wrongAppearance(asked: "dark", drawn: "light"))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path),
                       "a light frame under a dark request left a file of its name")
    }

    /// **A page over a ground on the other side of the appearance asked is refused
    /// and no file is made.** The instrument first: the page over its own ground
    /// is written (removed again). Then the page painting `fill` to its edges —
    /// the ground that fill composed under the frame would give.
    private func assertTheGroundIsRefused(in appearance: NSAppearance.Name, fill: Color,
                                          control: String, refused: String) throws {
        try requireTheFolder()
        let label = RenderedInk.label(of: appearance)
        let page = Text(verbatim: "a \(label) page").foregroundStyle(.red)
        let own = MountedRender(page, width: 200, height: 60, appearance: appearance)
        defer { own.drop() }
        own.settle(10)
        let controlFile = try refusalFile(control)
        defer { try? FileManager.default.removeItem(at: controlFile) }
        XCTAssertNotNil(try StillFrame.write(own.host, in: appearance, named: control))
        XCTAssertTrue(FileManager.default.fileExists(atPath: controlFile.path),
                      "the \(label) page over its own ground was not written, so this case proves nothing")

        let painted = MountedRender(
            page.frame(maxWidth: .infinity, maxHeight: .infinity).background(fill),
            width: 200, height: 60, appearance: appearance)
        defer { painted.drop() }
        painted.settle(10)
        let file = try olderFile(refused)
        XCTAssertThrowsError(try StillFrame.write(painted.host, in: appearance, named: refused)) {
            guard case .wrongGround(let asked, let luma)? = $0 as? StillFrame.Refusal else {
                return XCTFail("a ground on the other side of \(label) was refused as \($0)")
            }
            XCTAssertEqual(asked, label)
            if appearance == .darkAqua {
                XCTAssertGreaterThan(luma, 0.9)
            } else {
                XCTAssertLessThan(luma, 0.1)
            }
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path),
                       "a \(label) frame over a ground on the other side left a file of its name")
    }

    func testADarkPageOverALightGroundIsRefused() throws {
        try assertTheGroundIsRefused(in: .darkAqua, fill: .white,
                                     control: "refusal-control-dark-ground", refused: "refusal-light-ground")
    }

    func testALightPageOverADarkGroundIsRefused() throws {
        try assertTheGroundIsRefused(in: .aqua, fill: .black,
                                     control: "refusal-control-light-ground", refused: "refusal-dark-ground")
    }

    /// **A frame as tall as the mount is refused and no file is made.** The
    /// instrument first: a page that fits is sized below the cap and written
    /// (removed again). Then a scroll view with more in it than the cap holds,
    /// through the call every frame of the family is written by.
    func testAFrameAsTallAsTheMountIsRefusedAndNothingIsWritten() throws {
        try requireTheFolder()
        let short = MountedRender(Text("a short page"), width: 200, height: Self.pane, appearance: .aqua)
        defer { short.drop() }
        let control = try refusalFile("refusal-control-short")
        defer { try? FileManager.default.removeItem(at: control) }
        XCTAssertFalse(Self.fit(short.host, width: 200).atCap,
                       "a short page was sized to the cap, so this case proves nothing")
        XCTAssertNotNil(try StillFrame.write(short.host, in: .aqua, named: "refusal-control-short"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: control.path),
                      "the short page was not written, so this case proves nothing")

        let tall = MountedRender(ScrollView { Color.red.frame(width: 100, height: 2 * ModulePageRender.pageHeight) },
                                 width: 200, height: Self.pane, appearance: .aqua)
        defer { tall.drop() }
        let file = try olderFile("refusal-as-tall-as-the-mount")
        XCTAssertThrowsError(try Self.put(tall.host, named: "refusal-as-tall-as-the-mount", in: .aqua,
                                          width: 200)) {
            XCTAssertTrue($0 is AsTallAsTheMount, "a frame at the cap was refused as \($0)")
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path),
                       "a frame as tall as the mount left a file of its name")
    }
}
