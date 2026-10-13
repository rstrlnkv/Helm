import AppKit
import CryptoKit
import HelmContract
import HelmRuntime
import HelmTestSupport
import HelmUI
import Module_Disk_Engine
import XCTest
@testable import Module_Disk_UI

/// **The Disk page in the five states a person works in, written out as a
/// picture** — for a person to look at before judging or changing the page.
///
/// `EveryPageIsWrittenAsAPictureTests` has no answering fixture for Disk and
/// draws its page over the empty wire, so Disk shows only its volume list nobody
/// answered. The fixtures that answer for Disk live in this target
/// (`Fakes.swift`), which that family cannot see, so the states are written from
/// here.
///
/// `HELM_FRAMES_DIR=<folder>` writes one PNG per state × appearance × language ×
/// width, named `<page>-<state>-<light|dark>-<lang>-<width>.png` with the page
/// spelled from `DiskDescriptor.id`; without the variable the case skips out
/// loud, and a value that is not an absolute path is refused.
///
/// **The five states** (`State`), each built in `build(_:)` from this target's
/// fixtures and each asserting its own fact before the page is mounted and again
/// once the page has been sized: `volumes` the start screen with its volume cards,
/// `unanswered` the same screen when the volume list got no reply, `scanning`
/// the wait before the first snapshot, `result` the list, and beside it the ring
/// at the settings column only (`DiskLayout.showsRing` drops the ring at the
/// narrow width), `report` the sentence under them after a removal.
///
/// **After a run that reached its frames, a file of a frame's name lies in the
/// folder only if every guard of the file passed for that frame in that run.**
/// A run that fails before its first frame — a number of the pane not found —
/// clears nothing, and a file that cannot be removed stays, as a failure of its
/// own. A fixture that did not take
/// is a failure and writes no file, so a neighbour's picture is never written
/// under the wrong name, and the older file of that name goes; so does the file
/// of any frame refused for another reason. Per appearance, language and width the
/// five pictures are also told apart by their pixels, and per state, appearance
/// and width so are the three languages: two that draw one picture fail the case
/// and both leave the folder, since which of them is wrong is not known.
///
/// **Each state is built inside the language it is drawn in.** The banner is a
/// string composed when the act happens, not when the page is drawn.
///
/// **Known to come from this Mac or this process:** the backing scale of the
/// screen (the `[frames]` line prints it), the system accent colour (the fill bar
/// of a volume card is `Color.accentColor`), the fonts, and the process's own
/// scratch store, where `result` and `report` save the scan they show. The scan's
/// root is `/Volumes/Frames Fixture HD`, which no fixture creates and which is
/// there only on a Mac with a volume of that name, so the tree a previous frame
/// saved is not restored over a later one, and the owner's last scan is never read.
///
/// **The `scanning` page holds a spinner.** A settle it keeps from agreeing is
/// counted among those that ran out of their turns, which the `[frames]` line of a
/// call that wrote a frame prints, rather than hidden.
///
/// The block from "The pane writer: begin" to "The pane writer: end" names no
/// Disk type: the gate, the pane's numbers, the sizing, the writing, the guards
/// on what stays in the folder, and the counters. The five states are below it.
@MainActor
final class TheDiskPageIsWrittenAsAPictureTests: XCTestCase {

    // MARK: - The pane writer: begin

    private let languages: [AppLanguage] = [.en, .ru, .de]

    /// The tallest a frame may grow, and the height a case mounts what it draws
    /// at: tall enough that a scroll view realizes everything it holds. A frame
    /// that grows to it is the mount and not the thing drawn, and is refused.
    private let ceiling: CGFloat = 3000

    /// How many times `settle` pumps the run loop before it gives up agreeing.
    private let turns = 40

    /// A width a frame is drawn at, and where the number comes from.
    private typealias Width = (points: CGFloat, source: String)

    /// Where one picture is drawn besides its state.
    private struct Cell: Hashable {
        let appearance: NSAppearance.Name
        let language: AppLanguage
        let width: CGFloat
    }

    /// A frame that lies in the folder, with a digest of its pixels to be told
    /// apart from the others by.
    private struct Landed {
        let state: String
        let cell: Cell
        let height: CGFloat
        let pixels: SHA256.Digest
    }

    /// What one call of `eachFrame` has done, which its `[frames]` line reports.
    /// A call starts it afresh: a case that calls `eachFrame` twice gets two
    /// lines, each about its own call's frames, and the comparisons of
    /// `tellApart` stay inside the call.
    private struct Tally {
        var page = ""
        var began = Date()
        var ground: CGFloat = 0
        var widths: [Width] = []
        var scale: CGFloat?
        var writtenInto: String?
        var landed: [String: Landed] = [:]
        var refused: Set<String> = []
        var settles = 0
        var unsettled = 0
    }

    private var tally = Tally()

    /// The one `[frames]` line of a call of `eachFrame`: what the call left in the
    /// folder, and every frame refused, whatever refused it. A line with nothing
    /// written says which of three happened: the variable is not set or is empty,
    /// it is set and no frame was reached, or every frame was refused.
    private func printTheLine() {
        let heights = tally.landed.values.map { $0.height }
        guard !heights.isEmpty else {
            let asked = ProcessInfo.processInfo.environment["HELM_FRAMES_DIR"] ?? ""
            let why = asked.isEmpty ? "HELM_FRAMES_DIR is not set or is empty"
                : tally.refused.isEmpty ? """
                    HELM_FRAMES_DIR is `\(asked)` and no frame was reached; the failure the \
                    run reports says why
                    """
                : "HELM_FRAMES_DIR is `\(asked)` and every frame was refused: \(tally.refused.sorted())"
            print("[frames] \(name): none written: \(why)")
            return
        }
        let seconds = Int(Date().timeIntervalSince(tally.began).rounded())
        print("""
            [frames] \(name): \(heights.count) written, \(seconds) s, at scale \
            \(tally.scale.map { "\($0)" } ?? "unread") to \(tally.writtenInto ?? "?"); widths \
            \(tally.widths.map { "\(Int($0.points)) (\($0.source))" }.joined(separator: ", ")); \
            heights \(Int(heights.min() ?? 0))…\(Int(heights.max() ?? 0)) pt; \
            \(tally.refused.count) refused\(tally.refused.isEmpty ? "" : ": \(tally.refused.sorted())"); \
            \(tally.unsettled) of \(tally.settles) settles ran out of their \(turns) turns
            """)
    }

    private func requireTheFolder() throws {
        let directory = try StillFrame.directory
        try XCTSkipIf(directory == nil, "a picture only: HELM_FRAMES_DIR is not set or is empty")
    }

    /// A reading the case needed and did not get.
    private struct Unread: Error, CustomStringConvertible {
        let description: String
    }

    /// The one number a pattern finds in a source file of the app. A pattern that
    /// finds none or several is a failure, not a skip.
    private func number(_ pattern: String, in path: String) throws -> CGFloat {
        let text = try RepoSource.text(of: path)
        let found = try NSRegularExpression(pattern: pattern)
            .matches(in: text, range: NSRange(text.startIndex..., in: text))
        guard found.count == 1, let range = Range(found[0].range(at: 1), in: text),
              let value = Double(text[range]) else {
            throw Unread(description: """
                \(path) has \(found.count) matches for `\(pattern)` where this reads exactly one — \
                the window's numbers have moved and the panes cannot be computed
                """)
        }
        return CGFloat(value)
    }

    /// The ground height frames start from and the widths they are drawn at. The
    /// default is the pane's: the height of the card of a window opened at its
    /// default size, and two widths — the settings column
    /// (`HelmLayout.settingsColumn`) and the card of the narrowest window. The
    /// height and the narrow width are four numbers read from the sources that
    /// hold them, put together by the arithmetic of `ShellGeometry.cardFrame`,
    /// which this target cannot call — the default height less the inset on both
    /// sides, the minimum width less the open sidebar and the inset. A case may
    /// give either or both of its own: what it gives is taken as it is, and when
    /// it gives both nothing is read.
    private func panes(widths: [Width]?, ground: CGFloat?) throws -> (ground: CGFloat, widths: [Width]) {
        if let widths, let ground { return (ground, widths) }
        let window = "Sources/HelmApp/SettingsWindow.swift"
        let geometry = "Sources/HelmApp/ShellGeometry.swift"
        let defaultHeight = try number(#"defaultSize = NSSize\(width: [0-9.]+, height: ([0-9.]+)\)"#,
                                       in: window)
        let minimum = try number(#"minSize = NSSize\(width: ([0-9.]+)"#, in: window)
        let inset = try number(#"inset: CGFloat = ([0-9.]+)"#, in: geometry)
        let sidebar = try number(#"defaultSidebarWidth: CGFloat = ([0-9.]+)"#, in: geometry)
        let narrow = minimum - sidebar - inset
        if widths == nil {
            XCTAssertLessThan(narrow, HelmLayout.settingsColumn,
                              "the narrow pane is not narrower than the settings column")
        }
        let source = "\(Int(minimum)) from minSize in \(window) less the sidebar \(Int(sidebar)) "
            + "and the inset \(Int(inset))"
        return (ground ?? defaultHeight - 2 * inset,
                widths ?? [(HelmLayout.settingsColumn, "the settings column"), (narrow, source)])
    }

    /// Grows `host` from the ground height to what its outermost scroll views hold.
    private func fit(_ host: NSView, width: CGFloat) -> (height: CGFloat, atCap: Bool) {
        host.frame = NSRect(x: 0, y: 0, width: width, height: tally.ground)
        settle(host)
        for _ in 0..<3 {
            let more = overflow(of: host)
            guard more > 0.5 else { break }
            let height = min(host.frame.height + more, ceiling)
            guard height > host.frame.height else { break }
            host.frame = NSRect(x: 0, y: 0, width: width, height: height)
            settle(host)
        }
        return (host.frame.height, host.frame.height >= ceiling)
    }

    /// Every outermost scroll view: one inside another is the inner page's own
    /// business, and the outer one is what the frame is sized by.
    private func outermostScrolls(of host: NSView) -> [NSScrollView] {
        host.everyViewWithAncestry.compactMap { entry in
            guard let scroll = entry.view as? NSScrollView,
                  !entry.ancestry.contains(where: { $0 is NSScrollView }) else { return nil }
            return scroll
        }
    }

    /// The largest amount an outermost scroll view's document is taller than what
    /// it shows.
    private func overflow(of host: NSView) -> CGFloat {
        outermostScrolls(of: host).compactMap { scroll in
            scroll.documentView.map { $0.frame.height - scroll.contentView.bounds.height }
        }.max() ?? 0
    }

    /// Pump until two consecutive readings of the pixels **and of the scroll
    /// overflow** agree: `fit` sizes the frame off the overflow, and a reading
    /// still moving would size it off a number about to change. **A table that is
    /// an outermost scroll view's document is tiled before it is read**: reframed,
    /// the table of Duplicates' list kept the height its document had before for
    /// as long as it was watched (`EveryPageIsWrittenAsAPictureTests`), and that
    /// stale height reads as an overflow nothing draws. Running out of the bound
    /// is not a failure: the `[frames]` line of a call that wrote a frame says how
    /// many did.
    private func settle(_ host: NSView) {
        var previous: (pixels: Data?, overflow: CGFloat)?
        tally.settles += 1
        for _ in 0..<turns {
            host.layoutSubtreeIfNeeded()
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
            for scroll in outermostScrolls(of: host) { (scroll.documentView as? NSTableView)?.tile() }
            let now = (pixels: RenderedInk.bytes(host), overflow: overflow(of: host))
            if let previous, now.pixels != nil, now.pixels == previous.pixels,
               now.overflow == previous.overflow { return }
            previous = now
        }
        tally.unsettled += 1
    }

    private func frameName(_ state: String, _ cell: Cell) -> String {
        "\(tally.page)-\(state)-\(RenderedInk.label(of: cell.appearance))-\(cell.language.rawValue)-\(Int(cell.width))"
    }

    /// A frame as tall as the mount is the mount and not the thing drawn: the rule
    /// that sizes a frame has run into the cap, and nothing says where it ends.
    private struct AsTallAsTheMount: Error, CustomStringConvertible {
        let height: CGFloat
        var description: String { "\(Int(height)) pt is the mount's height — the frame was not sized" }
    }

    /// A frame whose mounted page is not as wide as its cell is refused.
    private struct NotAsWideAsItsCell: Error, CustomStringConvertible {
        let mounted: CGFloat
        let cell: CGFloat
        var description: String { "the page is mounted \(Int(mounted)) pt wide, the frame is named for \(Int(cell)) pt" }
    }

    /// What the case requires of a frame once it is sized does not hold: the state
    /// the frame is named for has gone, or what was mounted never came to show it.
    private struct NotThatAnyMore: Error, CustomStringConvertible {
        var description: String { "what the case requires of the frame once it is sized does not hold" }
    }

    /// A frame refused: the failure names it, the file of its name is removed, an
    /// older one included (a file that cannot be removed is a failure of its own),
    /// and the frame is no longer counted as written.
    private func refuse(_ name: String, because reason: String) {
        XCTFail("\(name): refused — \(reason)")
        do { try StillFrame.clear(named: name) } catch { XCTFail("\(name): \(error)") }
        tally.landed[name] = nil
        tally.refused.insert(name)
    }

    /// The fact a state was built for, asked before anything is mounted: one that
    /// does not hold refuses the frame, and the caller goes on without mounting it.
    private func took(_ state: String, in cell: Cell, holds: @MainActor () -> Bool) -> Bool {
        guard holds() else {
            refuse(frameName(state, cell), because: "the fixture did not take, so the page would be another state")
            return false
        }
        return true
    }

    /// Fits `host` and writes it, or throws. `holds` is asked once the frame has
    /// its height, and the pixels are read for the comparison of `tellApart`
    /// before the file is made: the file is the last thing a frame earns.
    private func put(_ host: NSView, _ state: String, in cell: Cell, named name: String,
                     holds: @MainActor () -> Bool) throws {
        let fitted = fit(host, width: cell.width)
        guard abs(host.fittingSize.width - cell.width) < 1 else {
            throw NotAsWideAsItsCell(mounted: host.fittingSize.width, cell: cell.width)
        }
        guard holds() else { throw NotThatAnyMore() }
        guard !fitted.atCap else { throw AsTallAsTheMount(height: fitted.height) }
        guard let bytes = RenderedInk.bytes(host) else { throw Unread(description: "the frame has no pixels to read") }
        guard let url = try StillFrame.write(host, in: cell.appearance, named: name) else { return }
        tally.writtenInto = url.deletingLastPathComponent().path
        tally.landed[name] = Landed(state: state, cell: cell, height: fitted.height,
                                    pixels: SHA256.hash(data: bytes))
        if tally.scale == nil, let data = try? Data(contentsOf: url), let rep = NSBitmapImageRep(data: data) {
            tally.scale = CGFloat(rep.pixelsWide) / cell.width
        }
    }

    /// Writes a frame, or refuses it: a refusal is a failure naming the frame.
    private func write(_ host: NSView, _ state: String, in cell: Cell, holds: @MainActor () -> Bool) {
        let name = frameName(state, cell)
        do {
            try autoreleasepool {
                try put(host, state, in: cell, named: name, holds: holds)
            }
        } catch {
            refuse(name, because: "\(error)")
        }
    }

    /// Frames that must not draw one picture, as `group` puts them together: two
    /// that do are both refused, since which of them is wrong is not known.
    private func takeBack<Group: Hashable>(_ frames: [String: Landed],
                                           together group: ((key: String, value: Landed)) -> Group,
                                           because rule: String) {
        for same in Dictionary(grouping: frames, by: group).values {
            for (at, first) in same.enumerated() {
                for second in same[(at + 1)...] where first.value.pixels == second.value.pixels {
                    refuse(first.key, because: "it and \(second.key) are one picture: \(rule)")
                    refuse(second.key, because: "it and \(first.key) are one picture: \(rule)")
                }
            }
        }
    }

    /// The states of one cell, and the languages of one state at one appearance
    /// and width, are told apart by their pixels.
    private func tellApart() {
        let frames = tally.landed
        takeBack(frames, together: { $0.value.cell },
                 because: "the states of one appearance, language and width must differ")
        takeBack(frames, together: { entry in
            "\(entry.value.state) \(RenderedInk.label(of: entry.value.cell.appearance)) \(Int(entry.value.cell.width))"
        }, because: "the languages of one state, appearance and width must differ")
    }

    /// A whole call: the gate first, then both appearances, the three languages
    /// and the widths of one thing — the pane's two unless the case gives its own —
    /// each frame starting from the call's ground height — the one the case gives,
    /// or the pane's — unless the case's body has set `tally.ground` for the frame
    /// it is about to write; then the frames that drew one picture are taken out of
    /// the folder, and one `[frames]` line is printed however it ends. A call keeps
    /// its own books, so a second call in one case does not change what the first
    /// one printed.
    private func eachFrame(page: String, widths: [Width]? = nil, ground: CGFloat? = nil,
                           _ body: (Cell) async -> Void) async throws {
        tally = Tally(page: page)
        defer { printTheLine() }
        try requireTheFolder()
        let found = try panes(widths: widths, ground: ground)
        tally.ground = found.ground
        tally.widths = found.widths
        for appearance in RenderedInk.bothAppearances {
            for language in languages {
                for width in found.widths {
                    await body(Cell(appearance: appearance, language: language, width: width.points))
                }
            }
        }
        tellApart()
    }

    // MARK: - The pane writer: end

    // MARK: - The five states

    private enum State: String, CaseIterable {
        case volumes, unanswered, scanning, result, report
    }

    /// A state built and held: the model the page is mounted on, what must be
    /// true of it when it is drawn, and how to let it go.
    private struct Built {
        let vm: ModuleViewModel
        let holds: @MainActor () -> Bool
        let letGo: @MainActor () async -> Void
    }

    /// A volume no fixture creates; it is there only on a Mac that has a volume of
    /// that name. The scan's root must not be a path that is really there: a tree
    /// saved for a root that exists is restored over the next page
    /// (`DiskViewModel.restoreLastScan`), and `volumes` would then draw `result`.
    private static let root = "/Volumes/Frames Fixture HD"
    private static let video = "\(root)/Video Projects"

    private static let volumes = [
        VolumeInfo(name: "Macintosh HD", path: root,
                   totalBytes: 994_662_584_320, freeBytes: 412_000_000_000),
        VolumeInfo(name: "Backup", path: "/Volumes/Frames Fixture Backup",
                   totalBytes: 2_000_398_934_016, freeBytes: 1_300_000_000_000),
    ]

    /// A scan of the first volume: seven folders under the root, one of them with
    /// four of its own, so the ring, where the page draws it, has an inner circle
    /// and an outer one.
    private static let scanned = ScanResult(
        root: folder(root, bytes: 582_000_000_000, children: [
            folder("\(root)/Users", bytes: 340_000_000_000, children: [
                folder("\(root)/Users/Photos", bytes: 160_000_000_000),
                folder("\(root)/Users/Movies", bytes: 96_000_000_000),
                folder("\(root)/Users/Documents", bytes: 52_000_000_000),
                folder("\(root)/Users/Downloads", bytes: 32_000_000_000),
            ]),
            folder("\(root)/Library", bytes: 74_000_000_000),
            folder(video, bytes: 61_000_000_000),
            folder("\(root)/Applications", bytes: 58_000_000_000),
            folder("\(root)/System", bytes: 26_000_000_000),
            folder("\(root)/private", bytes: 17_000_000_000),
            folder("\(root)/opt", bytes: 6_000_000_000),
        ]),
        freeBytes: 412_000_000_000, filesScanned: 1_204_331, seconds: 48)

    /// The scan of `scanned`, finished, on a wire that also answers a removal of
    /// the one folder `report` takes out.
    private func finishedScan() async -> (transport: AnsweringTransport, vm: ModuleViewModel,
                                          dvm: DiskViewModel) {
        let transport = AnsweringTransport(volumes: Self.volumes)
        transport.answer(Self.root, with: Self.scanned)
        transport.answerTrash(with: DiskRemoval(removed: [Self.video], refused: [],
                                                freedBytes: 61_000_000_000))
        let vm = ModuleViewModel(transport: transport)
        let dvm = DiskViewModel.shared(vm: vm)
        await dvm.loadVolumes()
        await dvm.scan(path: Self.root)
        return (transport, vm, dvm)
    }

    private func build(_ state: State) async -> Built {
        switch state {
        case .volumes:
            let vm = ModuleViewModel(transport: AnsweringTransport(volumes: Self.volumes))
            let dvm = DiskViewModel.shared(vm: vm)
            await dvm.loadVolumes()
            return Built(vm: vm, holds: {
                dvm.phase == .start && dvm.volumes.count == Self.volumes.count
                    && !dvm.volumeListLost && !dvm.restored
            }, letGo: {})
        case .unanswered:
            let transport = AnsweringTransport(volumes: Self.volumes)
            transport.answers(.nothing)
            let vm = ModuleViewModel(transport: transport)
            let dvm = DiskViewModel.shared(vm: vm)
            await dvm.loadVolumes()
            return Built(vm: vm, holds: {
                dvm.phase == .start && dvm.volumeListLost && dvm.volumes.isEmpty
            }, letGo: {})
        case .scanning:
            let transport = HeldTransport()
            let vm = ModuleViewModel(transport: transport)
            let dvm = DiskViewModel.shared(vm: vm)
            let walk = Task { await dvm.scan(path: Self.root) }
            await untilParked(transport, count: 1)
            return Built(vm: vm, holds: {
                dvm.phase == .scanning && dvm.live && dvm.result == nil
            }, letGo: {
                transport.release(0, with: nil)
                await walk.value
            })
        case .result:
            let built = await finishedScan()
            return Built(vm: built.vm, holds: {
                built.dvm.phase == .result && !built.dvm.live && !built.dvm.segments.isEmpty
                    && !built.dvm.showsRemovalBar && !built.dvm.restored
            }, letGo: {})
        case .report:
            let built = await finishedScan()
            built.dvm.toggleBasket(Self.scanned.root.children[2])
            await built.dvm.emptyBasket()
            return Built(vm: built.vm, holds: {
                built.dvm.phase == .result && built.dvm.banner != nil && built.dvm.removedCount > 0
                    && built.dvm.basket.isEmpty && !built.dvm.replyLost
                    && built.transport.trashRequests.count == 1
            }, letGo: {})
        }
    }

    func testTheDiskPageIsWrittenInItsFiveStates() async throws {
        try await eachFrame(page: DiskDescriptor.id.rawValue) { cell in
            for state in State.allCases {
                await AppLanguage.only(cell.language) {
                    let built = await build(state)
                    guard took(state.rawValue, in: cell, holds: built.holds) else {
                        await built.letGo()
                        return
                    }
                    let mount = mountedDiskPage(vm: built.vm, width: cell.width, height: ceiling,
                                                appearance: cell.appearance)
                    write(mount.host, state.rawValue, in: cell, holds: built.holds)
                    mount.drop()
                    await built.letGo()
                }
            }
        }
    }
}
