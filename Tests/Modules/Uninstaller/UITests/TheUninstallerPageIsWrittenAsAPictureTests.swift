import AppKit
import CryptoKit
import HelmContract
import HelmRuntime
import HelmTestSupport
import HelmUI
import Module_Uninstaller_Engine
import SwiftUI
import XCTest
@testable import Module_Uninstaller_UI

/// **The Uninstaller page in the three states a person works in, and the Trash
/// offer, written out as pictures** — for a person to look at before judging or
/// changing them.
///
/// `EveryPageIsWrittenAsAPictureTests` has no answering fixture for the
/// Uninstaller and draws its page over the empty wire, so for the Uninstaller it
/// shows only the list nobody answered. The wire that answers for this module
/// (`UninstallerWire`) lives in this target, which that family cannot see, so the
/// pictures are written from here.
///
/// `HELM_FRAMES_DIR=<folder>` writes one PNG per frame, named
/// `<page>-<state>-<light|dark>-<lang>-<width>.png` with the page spelled from
/// `UninstallerDescriptor.id`; without the variable both cases skip out loud, and a
/// value that is not an absolute path is refused.
///
/// **Case one, the page in the pane** (`PageState`): `list`, `review` and `removed`,
/// each in light and dark, en, ru and de, at the pane's two widths. The three states
/// are three points of one round, each on a wire of its own that `build(_:)` makes
/// the same way: `list` the eight applications with their sizes and last-opened
/// dates, `review` one of them ticked
/// and its scan read (six leftovers, one of them found only by the application's
/// name), `removed` that removal sent and answered, the page back on the picker with
/// the sentence the removal left above the bar.
///
/// **In `removed` the list above that sentence still holds the application that was
/// removed.** The wire's list is fixed when the wire is built, and
/// `UninstallerViewModel.removeSelection` ends by asking for the list again, so the
/// page says "Moved to the Trash" under a list that has not changed.
///
/// **Case two, the Trash offer** (`offer`): not a page in the pane but the content of
/// a window of its own, so it is written at that window's one width,
/// `TrashedLeftoversView.windowWidth`, and not at the pane's two. It is made the way
/// the host makes it, by `TrashedAppOffer.sweep`, and drawn at the height its content
/// asks for — the mounted host's fitting height once the list has measured itself.
/// The block's `ground` argument is one number for a whole call, so the case gives
/// it the mount's own height and sets `tally.ground` itself for each frame, from the
/// host it has just mounted. A frame whose height was never set that way starts as
/// tall as the mount, which is not the host's fitting height, and is refused. The
/// frame holds the window's content and not its title bar.
///
/// **What a state asserts, and on what.** Before the mount, a model that has been
/// taken through the state must show it: the picker's list answered with its eight
/// applications, the sizes and the dates in; the review open on one group holding
/// the six leftovers; the removal's sentence, spelled from the bytes the fixture's
/// removal frees, with no failure and the wire having been asked to trash. The offer
/// is read the same way from a second model on a twin wire. Once the page is sized,
/// the same facts must still hold, the wire must have been asked for the list, and
/// the table in the mounted tree must hold the rows the state is named for: one per
/// application in `list` and `removed`, and in `review` the group's header, the
/// application's own row and one row per leftover. For the offer, the wire must have
/// been asked for the Trash's leftovers, the tree must hold a scroll view whose
/// whole content shows, and the frame must be as tall as the host's fitting height.
///
/// **After a run that reached its frames, a file of a frame's name lies in the
/// folder only if every guard of the file passed for that frame in that run.**
/// A run that fails before its first frame — a number of the pane not found —
/// clears nothing, and a file that cannot be removed stays, as a failure of its
/// own. A fixture that did not take
/// is a failure and writes no file, so a neighbour's picture is never written
/// under the wrong name, and the older file of that name goes; so does the file
/// of any frame refused for another reason. Per appearance, language and width the
/// states of the page are also told apart by their pixels, and per state,
/// appearance and width so are the three languages: two that draw one picture
/// fail the case and both leave the folder, since which of them is wrong is not
/// known.
///
/// **Each state is built inside the language it is drawn in.** The sentence a
/// removal leaves is a string composed when the removal happens, not when the page
/// is drawn.
///
/// **Known to come from this Mac:** the backing scale of the screen (the `[frames]`
/// line prints it), the fonts, and the icon of each application, read by its path
/// (`AppInfo.icon(forFile:)`). The paths are literals no fixture creates, under
/// `/Applications`, `/Users/frames-fixture` and `/Users/frames-fixture/.Trash`, so
/// none is a path of the person's account; what is drawn for one is what this Mac
/// gives a path that is not there, or the application's own icon on a Mac that has
/// one at that path. The "opened" line of each row is the fixture's date counted
/// back from the moment the state is built, in hours and days, and written by the
/// formatter as hours, days, weeks, months or years: a frame written on another day
/// may read another count in the older lines.
///
/// **Not in a frame:** the page hands its tab switcher, its sort menu, Refresh and
/// its search field to the settings window's own toolbar (`.helmWindowToolbar`),
/// and a mount gives it no channel to declare them to.
///
/// **Left out: the Orphans tab with results.** `UninstallerWire` answers
/// `scanOrphans` with an empty list, so the tab cannot be drawn with groups in it
/// from this target's fixtures.
///
/// The block from "The pane writer: begin" to "The pane writer: end" is the one
/// `TheDiskPageIsWrittenAsAPictureTests` holds, and names no Uninstaller type: the
/// gate, the pane's numbers, the sizing, the writing, the guards on what stays in
/// the folder, and the counters. The states and the offer are below it.
@MainActor
final class TheUninstallerPageIsWrittenAsAPictureTests: XCTestCase {

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

    // MARK: - The three states

    private enum PageState: String, CaseIterable {
        case list, review, removed
    }

    /// A state built and held: the model the page is mounted on, what must be true
    /// of it before anything is mounted, and what must be true of the mounted page
    /// once it is sized.
    private struct Built {
        let vm: ModuleViewModel
        let fixtureHolds: @MainActor () -> Bool
        let shows: @MainActor (NSView) -> Bool
    }

    /// Eight applications at paths no fixture creates (a Mac may still have one
    /// of these names installed; its icon is then what the frame shows).
    private static let applications = [
        application("Fable Reader", id: "fable", megabytes: 184),
        application("Tarn", id: "tarn", megabytes: 421),
        application("Quillwork", id: "quillwork", megabytes: 96),
        application("Lumen Draft", id: "lumen", megabytes: 1_870),
        application("Cobalt Notes", id: "cobalt", megabytes: 63),
        application("Sundial Clock", id: "sundial", megabytes: 12),
        application("Harbor Sync", id: "harbor", megabytes: 238),
        application("Loom Studio", id: "loom", megabytes: 2_410),
    ]

    private static func application(_ name: String, id: String, megabytes: Int) -> InstalledApp {
        InstalledApp(name: name, bundleID: "com.frames-fixture.\(id)",
                     path: "/Applications/\(name).app", sizeBytes: megabytes * 1_000_000)
    }

    /// The one that is ticked.
    private static let tarn = applications[1]

    /// How many hours before the state is built each application was last opened:
    /// 3, 12, 40, 200 and 400 days, each and an hour over, and 2 and a half hours.
    /// `Quillwork` and `Sundial Clock` are left out, so the page says it has no
    /// record of them.
    private static let openedHoursAgo: [String: Double] = [
        "Fable Reader": 73, "Tarn": 289, "Lumen Draft": 2.5,
        "Cobalt Notes": 961, "Harbor Sync": 4_801, "Loom Studio": 9_601,
    ]

    private static func opened() -> [String: Date] {
        let now = Date()
        return Dictionary(uniqueKeysWithValues: openedHoursAgo.map { name, hours in
            ("/Applications/\(name).app", now.addingTimeInterval(-hours * 3_600))
        })
    }

    private static let library = "/Users/frames-fixture/Library"

    /// What the scan of `tarn` finds: the last one is found by the name alone, so
    /// it arrives unticked and carries a badge.
    private static let leftovers = [
        Leftover(path: "\(library)/Application Support/Tarn", kind: .appSupport,
                 sizeBytes: 183_000_000, matchedByName: false),
        Leftover(path: "\(library)/Caches/com.frames-fixture.tarn", kind: .caches,
                 sizeBytes: 96_000_000, matchedByName: false),
        Leftover(path: "\(library)/Containers/com.frames-fixture.tarn", kind: .containers,
                 sizeBytes: 41_000_000, matchedByName: false),
        Leftover(path: "\(library)/Preferences/com.frames-fixture.tarn.plist", kind: .preferences,
                 sizeBytes: 12_288, matchedByName: false),
        Leftover(path: "\(library)/Logs/Tarn", kind: .logs, sizeBytes: 1_400_000, matchedByName: false),
        Leftover(path: "\(library)/Application Support/Tarn Backups", kind: .appSupport,
                 sizeBytes: 740_000, matchedByName: true),
    ]

    private static let scan = ScanResult(bundleID: tarn.bundleID, appPath: tarn.path,
                                         appSizeBytes: tarn.sizeBytes, leftovers: leftovers,
                                         runningNow: false)

    /// The removal of the application and the five leftovers that arrive ticked.
    private static let removal: UninstallResult = {
        let ticked = leftovers.filter { !$0.matchedByName }
        return UninstallResult(trashed: [tarn.path] + ticked.map(\.path),
                               freedBytes: tarn.sizeBytes + ticked.reduce(0) { $0 + $1.sizeBytes })
    }()

    private func wire() -> UninstallerWire {
        let wire = UninstallerWire(apps: Self.applications,
                                   scans: [Self.tarn.bundleID: Self.scan],
                                   removal: Self.removal)
        wire.setOpened(Self.opened())
        return wire
    }

    private func build(_ state: PageState) async -> Built {
        let wire = wire()
        let vm = ModuleViewModel(transport: wire)
        let uvm = UninstallerViewModel.shared(vm: vm)
        await uvm.loadAppsIfNeeded()
        if state != .list {
            uvm.setChecked(Self.tarn.bundleID, true)
            await uvm.prepareReview()
        }
        if state == .removed { await uvm.removeSelection() }
        let holds: @MainActor () -> Bool = {
            switch state {
            case .list:
                uvm.listAnswered && uvm.apps.count == Self.applications.count
                    && uvm.measuredSizes.count == Self.applications.count
                    && uvm.lastOpened?.count == Self.openedHoursAgo.count
                    && uvm.step == .pick && uvm.resultBanner == nil
            case .review:
                uvm.step == .review && uvm.groups.count == 1
                    && uvm.groups.first?.leftovers == Self.leftovers && uvm.reviewBytes != nil
                    && wire.commands.contains(.scan)
            case .removed:
                uvm.resultBanner == UnStr.movedToTrash(Bytes(Self.removal.freedBytes))
                    && uvm.failures.isEmpty && uvm.step == .pick && !uvm.replyLost
                    && wire.commands.contains(.trashPaths)
            }
        }
        return Built(vm: vm, fixtureHolds: holds, shows: { host in
            let rows = state == .review ? 2 + Self.leftovers.count : Self.applications.count
            return holds() && wire.commands.contains(.listApps) && StripedListEnd.table(in: host)?.numberOfRows == rows
        })
    }

    /// `UninstallerSettingsPage` over `vm` in a window, with its grants named and
    /// animations off, at this case's width and height.
    private func mounted(_ vm: ModuleViewModel, width: CGFloat,
                         appearance: NSAppearance.Name) -> MountedRender {
        let page = UninstallerSettingsPage(vm: vm)
            .environment(\.helmGrants, HelmGrants(accessibility: .granted, fullDisk: .granted))
            .transaction { $0.disablesAnimations = true; $0.animation = nil }
        return MountedRender(page, width: width, height: ceiling, appearance: appearance)
    }

    func testTheUninstallerPageIsWrittenInItsThreeStates() async throws {
        try await eachFrame(page: UninstallerDescriptor.id.rawValue) { cell in
            for state in PageState.allCases {
                await AppLanguage.only(cell.language) {
                    let built = await build(state)
                    guard took(state.rawValue, in: cell, holds: built.fixtureHolds) else { return }
                    let mount = mounted(built.vm, width: cell.width, appearance: cell.appearance)
                    write(mount.host, state.rawValue, in: cell, holds: { built.shows(mount.host) })
                    mount.drop()
                }
            }
        }
    }

    // MARK: - The Trash offer

    private static let offerState = "offer"

    private static let trash = "/Users/frames-fixture/.Trash"

    /// Two applications dragged to the Trash and what they left: five files of the
    /// first (two of them in Caches and two in Application Support, which makes the
    /// rows name their leaf, and the last found by the name alone), three of the second.
    private static let offers = [
        TrashedAppLeftovers(
            bundleID: "com.frames-fixture.tarn", name: "Tarn", appPath: "\(trash)/Tarn.app",
            leftovers: [
                Leftover(path: "\(library)/Application Support/Tarn", kind: .appSupport,
                         sizeBytes: 183_000_000, matchedByName: false),
                Leftover(path: "\(library)/Caches/com.frames-fixture.tarn", kind: .caches,
                         sizeBytes: 96_000_000, matchedByName: false),
                Leftover(path: "\(library)/Caches/com.frames-fixture.tarn.updater", kind: .caches,
                         sizeBytes: 31_000_000, matchedByName: false),
                Leftover(path: "\(library)/Preferences/com.frames-fixture.tarn.plist",
                         kind: .preferences, sizeBytes: 12_288, matchedByName: false),
                Leftover(path: "\(library)/Application Support/Tarn Backups", kind: .appSupport,
                         sizeBytes: 740_000, matchedByName: true),
            ]),
        TrashedAppLeftovers(
            bundleID: "com.frames-fixture.lumen", name: "Lumen Draft", appPath: "\(trash)/Lumen Draft.app",
            leftovers: [
                Leftover(path: "\(library)/Containers/com.frames-fixture.lumen", kind: .containers,
                         sizeBytes: 520_000_000, matchedByName: false),
                Leftover(path: "\(library)/Saved Application State/com.frames-fixture.lumen.savedState",
                         kind: .savedState, sizeBytes: 3_400_000, matchedByName: false),
                Leftover(path: "\(library)/Logs/Lumen Draft", kind: .logs,
                         sizeBytes: 880_000, matchedByName: false),
            ]),
    ]

    /// The offer as the host makes it, on a wire of its own, and a second model on
    /// a twin wire that is loaded the same way, so what the view asked of its wire
    /// is not mixed with what the second model asked of the other.
    private struct Offer {
        let vm: ModuleViewModel
        let wire: UninstallerWire
        let fixtureHolds: @MainActor () -> Bool
        let shows: @MainActor (NSView) -> Bool
    }

    private func buildOffer() async -> Offer {
        let proof = TrashedLeftoversModel(vm: ModuleViewModel(transport: UninstallerWire(offers: Self.offers)))
        await proof.load()
        let wire = UninstallerWire(offers: Self.offers)
        return Offer(vm: ModuleViewModel(transport: wire), wire: wire, fixtureHolds: {
            proof.groups == Self.offers && !proof.selected.isEmpty && proof.outcome == nil
                && !proof.replyLost && proof.failures.isEmpty
        }, shows: { host in
            wire.commands.contains(.trashedAppLeftovers)
                && !host.everyView(ofType: NSScrollView.self).isEmpty
                && self.overflow(of: host) <= 0.5
                && abs(host.frame.height - host.fittingSize.height) < 1
        })
    }

    func testTheTrashOfferIsWrittenAtItsWindowsWidth() async throws {
        try await eachFrame(
            page: UninstallerDescriptor.id.rawValue,
            widths: [(TrashedLeftoversView.windowWidth, "TrashedLeftoversView.windowWidth")],
            ground: ceiling) { cell in
            await AppLanguage.only(cell.language) {
                let offer = await buildOffer()
                guard took(Self.offerState, in: cell, holds: offer.fixtureHolds) else { return }
                guard let view = await TrashedAppOffer.sweep(vm: offer.vm, onClose: {}) else {
                    refuse(frameName(Self.offerState, cell), because: "the offer found nothing to offer")
                    return
                }
                let mount = MountedRender(view.transaction { $0.disablesAnimations = true; $0.animation = nil },
                                          width: cell.width, height: ceiling, appearance: cell.appearance)
                mount.settle()
                tally.ground = mount.fittingHeight
                write(mount.host, Self.offerState, in: cell, holds: { offer.shows(mount.host) })
                mount.drop()
            }
        }
    }
}
