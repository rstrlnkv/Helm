import AppKit
import CryptoKit
import HelmContract
import HelmRuntime
import HelmTestSupport
import HelmUI
import SwiftUI
import XCTest
@testable import Module_Hosts_Engine
@testable import Module_Hosts_UI

/// **The Hosts page in the five states a person works in, written out as a
/// picture** — for a person to look at before judging or changing the page.
///
/// `EveryPageIsWrittenAsAPictureTests` has no answering fixture for Hosts and draws
/// its page over the empty wire, so for Hosts it shows the empty key list. The wire
/// that answers for Hosts (`HostsUIWire`) and the ports of the SSH tab's checks
/// (`SSHStripBench`) live in this target, which that family cannot see, so the
/// pictures are written from here.
///
/// `HELM_FRAMES_DIR=<folder>` writes one PNG per state × appearance × language ×
/// width, named `<page>-<state>-<light|dark>-<lang>-<width>.png` with the page
/// spelled from `HostsDescriptor.id`; without the variable the case skips out loud,
/// and a value that is not an absolute path is refused.
///
/// **The five states** (`PageState`), each built in `build(_:)` from this target's
/// fixtures: `keys` the page's opening tab, with the one key `HostsUIWire` gives it;
/// `ssh` the SSH tab, whose table is its default view, over a config of three hosts
/// and a `known_hosts` that trusts one of them; `ssh.noknownhosts` the same tab with
/// `known_hosts` missing; `ssh.forget.refused` the same tab after a Forget of that
/// trust that `known_hosts` refused to write; `ssh.outside` the same tab with the
/// config outside the home folder, which the engine reads and will not write.
///
/// **What a state asserts, and on what.** Before the mount, the model the page reads
/// must show the state: for `keys` one key and a readable key folder; for the SSH
/// states the three hosts, and then per state the writable config and a `known_hosts`
/// that is read and may be written (`ssh`), the unreadable `known_hosts`
/// (`ssh.noknownhosts`), an outcome of the Forget that is `failed`, which is what a
/// `known_hosts` that takes no write gives (`ssh.forget.refused`), a config that
/// reads and is not writable (`ssh.outside`). Once the page is sized the same facts
/// must still hold, the tab the mounted page reports as selected must be the one the
/// state is named for, and the tree must hold a scroll view, which both tabs draw
/// their tables in.
///
/// **After a run that reached its frames, a file of a frame's name lies in the
/// folder only if every guard of the file passed for that frame in that run.**
/// A run that fails before its first frame — a number of the pane not found —
/// clears nothing, and a file that cannot be removed stays, as a failure of its
/// own. A fixture that did not take
/// is a failure and writes no file, so a neighbour's picture is never written
/// under the wrong name, and the older file of that name goes; so does the file
/// of any frame refused for another reason. Per appearance, language and width the
/// five states are also told apart by their pixels, and per state, appearance and
/// width so are the three languages: two that draw one picture fail the case and
/// both leave the folder, since which of them is wrong is not known.
///
/// **Each state is built inside the language it is drawn in.**
///
/// **What lies on this Mac's disk, and what does not.** The SSH config and
/// `known_hosts` are real files under a folder made by `scratchDirectory` in this
/// process's temporary directory: its `home` stands in for the home. The config is read
/// through `SSHStripBench.Config`. `known_hosts` is written there for each state that
/// has one and taken away for the state that has none, because the gate that judges a
/// write asks whether the file is there (`SSHFileScope.mayWrite`): over a `known_hosts`
/// that only the port holds, a Forget is refused as outside the home, and the page
/// says so. The port itself (`SSHStripBench.Known`) answers from memory and takes a
/// write or refuses it as the state says. A second config, in a folder beside the
/// home, is the one of `ssh.outside`. The hosts file (`FixedFile`), the backups
/// (`MemoryBackups`), the key folder and the agent (`WireKeys`, `WireAgent`) are
/// values in memory, and the privileged write (`FixedPrivileged`) only records what it
/// was asked to run. Nothing in this file reads this account's home directory.
///
/// **Known to come from this Mac:** the backing scale of the screen (the `[frames]`
/// line prints it), the fonts, and the day. The key's modification date is fixed in
/// `WireKeys` and the key's row draws it as an age counted from the moment it is drawn
/// (`HelmDates.age`), so a `keys` frame written on another day may read another count.
/// The scratch folder is named with a UUID made again in each run, and no frame draws it.
///
/// **Not in a frame:** the page hands its tab switcher, its view switcher and New
/// key to the settings window's own toolbar (`.helmWindowToolbar`); a mount gives
/// it a channel that records what the page declared and no bar to draw it.
///
/// **Not written:** the SSH tab's plain-text view, and the hosts file, which the page
/// does not offer as a tab.
///
/// The block from "The pane writer: begin" to "The pane writer: end" is the one
/// `TheDiskPageIsWrittenAsAPictureTests` holds, and names no Hosts type: the gate,
/// the pane's numbers, the sizing, the writing, the guards on what stays in the
/// folder, and the counters. The five states are below it.
@MainActor
final class TheHostsPageIsWrittenAsAPictureTests: XCTestCase {

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

    /// The states, spelled as the file names spell them.
    private enum PageState: String, CaseIterable {
        case keys
        case ssh
        case noKnownHosts = "ssh.noknownhosts"
        case forgetRefused = "ssh.forget.refused"
        case outside = "ssh.outside"

        /// The tab the page has to be on to draw it: its opening tab, or the SSH tab.
        var tab: String { self == .keys ? "keys" : "ssh" }
    }

    /// A state built and held: the model the page is mounted on, what must be true
    /// of it before anything is mounted, and what must be true of the mounted page
    /// once it is sized.
    private struct Built {
        /// Held until the mount is dropped: the wire's handler holds the engine
        /// weakly, and once the engine has gone it answers every request with empty
        /// data.
        let engine: HostsEngine
        let hvm: HostsViewModel
        let vm: ModuleViewModel
        let channel: HelmWindowToolbarChannel
        let tab: String
        let fixtureHolds: @MainActor () -> Bool
        let shows: @MainActor (NSView) -> Bool
    }

    private static let hostsFile = "127.0.0.1\tlocalhost\n"

    /// Three hosts, the first the one `SSHStripBench.trusted` is a line for.
    private static let sshConfig = """
        Host github.com
            HostName github.com
            User git

        Host build
            HostName build.example.com
            User deploy
            Port 2222

        Host a
            HostName a.example

        """

    /// Where the SSH states' files are: a home with its `.ssh`, and a folder outside
    /// it, each holding the config.
    private struct Files {
        let home: URL
        let config: URL
        let outsideConfig: URL
        let knownHosts: URL
    }

    private var made: Files?

    /// Made by the first frame that asks, so a run that is skipped makes nothing.
    private func files() throws -> Files {
        if let made { return made }
        let root = scratchDirectory("frames-hosts")
        let home = root.appendingPathComponent("home")
        let ssh = home.appendingPathComponent(".ssh")
        let elsewhere = root.appendingPathComponent("elsewhere")
        for directory in [ssh, elsewhere] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Self.sshConfig.write(to: directory.appendingPathComponent("config"),
                                     atomically: true, encoding: .utf8)
        }
        let found = Files(home: home, config: ssh.appendingPathComponent("config"),
                          outsideConfig: elsewhere.appendingPathComponent("config"),
                          knownHosts: ssh.appendingPathComponent("known_hosts"))
        made = found
        return found
    }

    /// What the model the page reads must show for a state to be that state.
    private static func holds(_ state: PageState, _ hvm: HostsViewModel) -> Bool {
        switch state {
        case .keys:
            return hvm.keys.count == 1 && hvm.keysReadable
        case .ssh:
            return hvm.hostRows.count == 3 && hvm.sshWritable && hvm.knownHostsReadable
                && hvm.knownHostsWritable && hvm.knownHostsOutcome == nil
        case .noKnownHosts:
            return hvm.hostRows.count == 3 && !hvm.knownHostsReadable
        case .forgetRefused:
            guard let outcome = hvm.knownHostsOutcome else { return false }
            return hvm.hostRows.count == 3 && outcome == .failed
        case .outside:
            return hvm.hostRows.count == 3 && hvm.sshReadable && !hvm.sshWritable
        }
    }

    /// The model on `vm` with its first load over, taken to its state: for the
    /// refused Forget, a Forget of the trusted host once the hosts are in.
    private func ready(_ state: PageState, engine: HostsEngine, vm: ModuleViewModel) async -> Built {
        let hvm = HostsViewModel.shared(vm: vm)
        await hvm.firstLoad?.value
        if state == .forgetRefused {
            for _ in 0..<200 where hvm.hostRows.isEmpty { try? await Task.sleep(nanoseconds: 10_000_000) }
            if let entry = KnownHostsFile.parse(SSHStripBench.trusted).entries.first {
                await hvm.forget(entry)
            }
        }
        let holds: @MainActor () -> Bool = { Self.holds(state, hvm) }
        for _ in 0..<200 where !holds() { try? await Task.sleep(nanoseconds: 10_000_000) }
        let channel = HelmWindowToolbarChannel()
        let tab = state.tab
        return Built(engine: engine, hvm: hvm, vm: vm, channel: channel, tab: tab,
                     fixtureHolds: holds, shows: { host in
            holds() && channel.content(for: HostsDescriptor.id.rawValue)?.selectedTab?.wrappedValue == tab
                && !host.everyView(ofType: NSScrollView.self).isEmpty
        })
    }

    /// An engine over the SSH config in the home's `.ssh` or outside the home, and
    /// a `known_hosts` that is `known` and does or does not take a write. The file
    /// of that name in the home's `.ssh` is made to say what the port says, or is
    /// taken away when the port says nothing: the gate that judges a write asks
    /// whether the file is there (`SSHFileScope.mayWrite`), and a Forget over a
    /// `known_hosts` that is only in memory is refused as outside the home.
    private func ssh(_ state: PageState, inside: Bool, known: String?, writes: Bool) async throws -> Built {
        let found = try files()
        if let known {
            try known.write(to: found.knownHosts, atomically: true, encoding: .utf8)
        } else if FileManager.default.fileExists(atPath: found.knownHosts.path) {
            try FileManager.default.removeItem(at: found.knownHosts)
        }
        let engine = HostsEngine(file: FixedFile(Self.hostsFile),
                                 privileged: FixedPrivileged(.declined),
                                 backups: MemoryBackups(),
                                 sshConfig: SSHStripBench.Config(inside ? found.config : found.outsideConfig),
                                 knownHosts: SSHStripBench.Known(url: found.knownHosts, text: known, writes: writes),
                                 keys: WireKeys(), agent: WireAgent(),
                                 generator: WireKeyGenerator(),
                                 home: found.home,
                                 now: { Date(timeIntervalSince1970: 0) },
                                 transport: LocalTransport())
        return await ready(state, engine: engine, vm: ModuleViewModel(transport: engine.transport))
    }

    private func build(_ state: PageState) async throws -> Built {
        switch state {
        case .keys:
            let wire = HostsUIWire.make(file: Self.hostsFile, privileged: .declined)
            return await ready(state, engine: wire.engine, vm: wire.vm)
        case .ssh:
            return try await ssh(state, inside: true, known: SSHStripBench.trusted, writes: true)
        case .noKnownHosts:
            return try await ssh(state, inside: true, known: nil, writes: true)
        case .forgetRefused:
            return try await ssh(state, inside: true, known: SSHStripBench.trusted, writes: false)
        case .outside:
            return try await ssh(state, inside: false, known: SSHStripBench.trusted, writes: true)
        }
    }

    /// `HostsSettingsPage` over the state's model in a window, animations off, at
    /// this case's width and height, taken to the tab the state is named for the way
    /// a person does: through the toolbar's tab binding the page declared.
    private func mounted(_ built: Built, width: CGFloat, appearance: NSAppearance.Name) -> MountedRender {
        let page = HostsSettingsPage(vm: built.vm)
            .transaction { $0.disablesAnimations = true; $0.animation = nil }
        let mount = MountedRender(page, width: width, height: ceiling, appearance: appearance,
                                  channel: built.channel)
        mount.settle(20)
        built.channel.content(for: HostsDescriptor.id.rawValue)?.selectedTab?.wrappedValue = built.tab
        mount.settle(40)
        return mount
    }

    func testTheHostsPageIsWrittenInItsFiveStates() async throws {
        try await eachFrame(page: HostsDescriptor.id.rawValue) { cell in
            for state in PageState.allCases {
                await AppLanguage.only(cell.language) {
                    do {
                        let built = try await build(state)
                        guard took(state.rawValue, in: cell, holds: built.fixtureHolds) else { return }
                        withExtendedLifetime(built) {
                            let mount = mounted(built, width: cell.width, appearance: cell.appearance)
                            write(mount.host, state.rawValue, in: cell, holds: { built.shows(mount.host) })
                            mount.drop()
                            built.hvm.stop()
                        }
                    } catch {
                        refuse(frameName(state.rawValue, cell), because: "\(error)")
                    }
                }
            }
        }
    }
}
