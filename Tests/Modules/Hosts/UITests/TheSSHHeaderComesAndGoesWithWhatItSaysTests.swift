import AppKit
import HelmContract
import HelmRuntime
import HelmTestSupport
import HelmUI
import SwiftUI
import XCTest
@testable import Module_Hosts_Engine
@testable import Module_Hosts_UI

/// **Every reason the SSH tab's strip has to speak draws it, and it goes again
/// once the reason has gone.**
///
/// `HostsSettingsPage.sshHeaderHasSomethingToSay` restates, as one predicate,
/// the four conditions the strip's body reads. A condition the body reads and
/// the predicate forgets is a note that never reaches the screen, and a
/// condition that stays true after the act that answers it is the empty band
/// back again. This reads the quiet case, a typed change and each of the
/// other reasons, and the way back:
///
/// - `known_hosts` that cannot be read — the strip is drawn;
/// - a Forget that did not go through — the strip is drawn;
/// - a change typed, then Apply — drawn, then gone once the engine's snapshot
///   says the file on disk is the text on screen;
/// - a change typed, then Revert — drawn, then gone.
///
/// «Drawn» is read off the page: the text box moves down from the margin and
/// the rows above it carry ink. «Gone» is the box back on the margin with no
/// ink above it. Both appearances are read.
@MainActor
final class TheSSHHeaderComesAndGoesWithWhatItSaysTests: XCTestCase {

    private final class ScratchSSHConfig: SSHConfigPort, @unchecked Sendable {
        let url: URL
        init(_ url: URL) { self.url = url }
        func read() -> String? { try? String(contentsOf: url, encoding: .utf8) }
        func write(_ text: String) -> Bool {
            (try? text.write(to: url, atomically: true, encoding: .utf8)) != nil
        }
    }

    /// `known_hosts` in the states the real file can be in: missing (`nil`),
    /// readable, and readable but refusing a write.
    private struct ScratchKnownHosts: KnownHostsPort {
        let url: URL
        let text: String?
        let writes: Bool
        func read() -> String? { text }
        func write(_ text: String) -> Bool { writes }
    }

    private static let trusted = "github.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5 me@mac\n"

    private var renders: [MountedRender] = []
    private var engines: [HostsEngine] = []

    override func tearDown() async throws {
        await MainActor.run {
            renders.forEach { $0.drop() }
            renders = []
            engines = []
        }
    }

    private struct Opened {
        let mounted: MountedRender
        let hvm: HostsViewModel
    }

    private func open(_ appearance: NSAppearance.Name, known: String? = trusted,
                      knownWrites: Bool = true) async throws -> Opened {
        let home = scratchDirectory("hosts-sshheader-states")
        let ssh = home.appendingPathComponent(".ssh")
        try FileManager.default.createDirectory(at: ssh, withIntermediateDirectories: true)
        let config = ssh.appendingPathComponent("config")
        try "Host a\n    HostName a.example\n".write(to: config, atomically: true, encoding: .utf8)
        let engine = HostsEngine(file: FixedFile("127.0.0.1\tlocalhost\n"),
                                 privileged: FixedPrivileged(.declined),
                                 backups: MemoryBackups(),
                                 sshConfig: ScratchSSHConfig(config),
                                 knownHosts: ScratchKnownHosts(url: ssh.appendingPathComponent("known_hosts"),
                                                               text: known, writes: knownWrites),
                                 keys: WireKeys(), agent: WireAgent(),
                                 generator: WireKeyGenerator(),
                                 home: home,
                                 now: { Date(timeIntervalSince1970: 0) },
                                 transport: LocalTransport())
        engines.append(engine)
        let vm = ModuleViewModel(transport: engine.transport)
        let hvm = HostsViewModel.shared(vm: vm)
        await hvm.firstLoad?.value
        let channel = HelmWindowToolbarChannel()
        let mounted = MountedRender(HostsSettingsPage(vm: vm), width: 900, height: 500,
                                    appearance: appearance, channel: channel)
        renders.append(mounted)
        mounted.settle(20)
        let declared = try XCTUnwrap(channel.content(for: HostsDescriptor.id.rawValue))
        try XCTUnwrap(declared.selectedTab).wrappedValue = "ssh"
        mounted.settle(20)
        let action = try XCTUnwrap(try XCTUnwrap(channel.content(for: HostsDescriptor.id.rawValue))
            .actions.first { $0.id == "viewMode" })
        guard case let .segmented(_, selection) = action.kind else { throw XCTSkip("no view switcher") }
        selection.wrappedValue = "text"
        mounted.settle(40)
        return Opened(mounted: mounted, hvm: hvm)
    }

    private func box(_ mounted: MountedRender, _ what: String) throws -> CGRect {
        guard let root = mounted.host.layer else { throw XCTSkip("no layer tree") }
        var found: [CGRect] = []
        func walk(_ layer: CALayer) {
            if layer.cornerRadius > 0.01, layer.bounds.height > 100 {
                let frame = layer.convert(layer.bounds, to: root)
                let top = root.isGeometryFlipped ? frame.minY : mounted.host.bounds.height - frame.maxY
                found.append(CGRect(x: frame.minX, y: top, width: frame.width, height: frame.height))
            }
            layer.sublayers?.forEach(walk)
        }
        walk(root)
        XCTAssertEqual(found.count, 1, "\(what): \(found.count) block-sized wells drew, the text box is one")
        return try XCTUnwrap(found.first, "\(what): no text box")
    }

    private func inkAbove(_ mounted: MountedRender, _ box: CGRect) throws -> Int {
        try XCTUnwrap(RenderedInk.read(mounted.host, points: 0...Int((box.minY - 2).rounded(.down)),
                                       columns: 0...Int(mounted.host.bounds.width) - 1))
    }

    private func assertDrawn(_ mounted: MountedRender, _ what: String,
                             file: StaticString = #filePath, line: UInt = #line) throws {
        let box = try box(mounted, what)
        XCTAssertGreaterThan(box.minY, HostsSettingsPage.textBoxMargin + 10,
                             "\(what): the box is still on the page's top margin — no strip above it",
                             file: file, line: line)
        XCTAssertGreaterThan(try inkAbove(mounted, box), 0,
                             "\(what): nothing drew above the box", file: file, line: line)
    }

    private func assertGone(_ mounted: MountedRender, _ what: String,
                            file: StaticString = #filePath, line: UInt = #line) throws {
        let box = try box(mounted, what)
        XCTAssertEqual(box.minY, HostsSettingsPage.textBoxMargin, accuracy: 0.5,
                       "\(what): the box sits \(box.minY) pt down — the strip is still there",
                       file: file, line: line)
        XCTAssertEqual(try inkAbove(mounted, box), 0,
                       "\(what): something drew above the box with nothing to say", file: file, line: line)
    }

    func testAKnownHostsFileThatCannotBeReadIsSaid() async throws {
        for appearance in RenderedInk.bothAppearances {
            let opened = try await open(appearance, known: nil)
            XCTAssertFalse(opened.hvm.knownHostsReadable, "precondition: known_hosts read as readable")
            try assertDrawn(opened.mounted, "\(RenderedInk.label(of: appearance)), known_hosts unreadable")
            opened.mounted.drop()
        }
    }

    func testAForgetThatDidNotGoThroughIsSaid() async throws {
        for appearance in RenderedInk.bothAppearances {
            let what = "\(RenderedInk.label(of: appearance)), Forget refused"
            let opened = try await open(appearance, knownWrites: false)
            try assertGone(opened.mounted, "\(what), before the press")
            let entry = try XCTUnwrap(KnownHostsFile.parse(Self.trusted).entries.first)
            await opened.hvm.forget(entry)
            opened.mounted.settle(40)
            let outcome = try XCTUnwrap(opened.hvm.knownHostsOutcome, "precondition: Forget came back with nothing")
            XCTAssertNotEqual(outcome, .applied, "precondition: the refusing file took the Forget")
            try assertDrawn(opened.mounted, what)
            opened.mounted.drop()
        }
    }

    func testTheStripGoesOnceTheChangeIsApplied() async throws {
        for appearance in RenderedInk.bothAppearances {
            let what = "\(RenderedInk.label(of: appearance)), Apply"
            let opened = try await open(appearance)
            let textView = try XCTUnwrap(opened.mounted.host.everyView(ofType: NSTextView.self).first)
            opened.mounted.window?.makeFirstResponder(textView)
            textView.insertText("# typed\n", replacementRange: NSRange(location: 0, length: 0))
            opened.mounted.settle(40)
            try assertDrawn(opened.mounted, "\(what), typed")
            await opened.hvm.applySSH()
            XCTAssertEqual(opened.hvm.sshOutcome, .applied, "precondition: the write did not go through")
            for _ in 0..<100 where opened.hvm.sshHasUnsavedChanges { await grace(0.02) }
            XCTAssertFalse(opened.hvm.sshHasUnsavedChanges,
                           "precondition: the engine's snapshot never reached the page")
            opened.mounted.settle(40)
            try assertGone(opened.mounted, "\(what), applied")
            opened.mounted.drop()
        }
    }

    func testTheStripGoesOnceTheChangeIsReverted() async throws {
        for appearance in RenderedInk.bothAppearances {
            let what = "\(RenderedInk.label(of: appearance)), Revert"
            let opened = try await open(appearance)
            let textView = try XCTUnwrap(opened.mounted.host.everyView(ofType: NSTextView.self).first)
            opened.mounted.window?.makeFirstResponder(textView)
            textView.insertText("# typed\n", replacementRange: NSRange(location: 0, length: 0))
            opened.mounted.settle(40)
            try assertDrawn(opened.mounted, "\(what), typed")
            opened.hvm.revertSSH()
            opened.mounted.settle(40)
            XCTAssertFalse(opened.hvm.sshHasUnsavedChanges, "precondition: Revert left a change")
            try assertGone(opened.mounted, "\(what), reverted")
            opened.mounted.drop()
        }
    }
}
