import AppKit
import HelmContract
import HelmRuntime
import HelmTestSupport
import HelmUI
import SwiftUI
import XCTest
@testable import HelmApp
@testable import Module_Homebrew_Engine
@testable import Module_Homebrew_UI
@testable import Module_Hosts_Engine
@testable import Module_Hosts_UI

/// **The SSH tab's plain-text box sits as far from the page's edges as the
/// Homebrew console does — measured off both pages, not read off a constant.**
///
/// The owner named the console as the model for the box. The two pages spell
/// their margins in two files (`HostsSettingsPage.textBoxMargin`, the
/// console stack's own padding in `HomebrewSettingsPage`), so a check that
/// compared either to a number would pass with the other one moved. This one
/// draws both pages in one bench at one size, finds each well — the one
/// rounded layer taller than a control — and compares what drew:
///
/// - the console's left, right and bottom gaps to the page's edges are one
///   step (the reference is a single number, or it is not a reference);
/// - the text box's gap on **all four** sides equals that step, the top
///   included, since nothing is drawn above the box while the SSH tab has
///   nothing to say (`TheSSHHeaderComesAndGoesWithWhatItSaysTests`).
///
/// The Hosts page is opened as a person opens it: Keys, then SSH and Text
/// through the page's own toolbar declaration. Both appearances are read.
@MainActor
final class TheSSHTextBoxSitsWhereTheHomebrewConsoleSitsTests: XCTestCase {

    // MARK: Homebrew — installed, one line of output, so the console is up.

    private final class Brew: EngineTransport, @unchecked Sendable {
        let stream = AsyncStream<EngineEvent>.makeStream()
        var events: AsyncStream<EngineEvent> { stream.stream }
        func send(_ command: EngineCommand) async throws -> Data {
            switch HomebrewCommand(rawValue: command.name) {
            case .status:
                return try JSONEncoder().encode(BrewStatus(installed: true, brewPath: "/opt/fixture/bin/brew"))
            case .listInstalled:
                return try JSONEncoder().encode((0..<20).map {
                    BrewPackage(name: "pkg-\($0)", version: "1.\($0)", isCask: false)
                })
            case .outdated: return try JSONEncoder().encode([OutdatedPackage]())
            case .descriptions: return try JSONEncoder().encode([String: String]())
            case .doctor: return try JSONEncoder().encode([DoctorIssue]())
            default: return Data()
            }
        }
        func say(_ line: String) {
            stream.continuation.yield(EngineEvent(name: HomebrewEvent.opLog.rawValue, payload: Data(line.utf8)))
        }
    }

    // MARK: Hosts — every port named; the config is a real file in a scratch
    // home, so the page may write it and draws no refusal banner over the box.

    private struct File: HostsFilePort { func read() -> String? { "127.0.0.1\tlocalhost\n" } }
    private struct Root: PrivilegedPort { func run(_ command: String) -> PrivilegedOutcome { .declined } }
    private struct NoBackups: BackupPort {
        func save(_ text: String, name: String) -> Bool { false }
        func list() -> [String] { [] }
        func read(_ name: String) -> String? { nil }
        func delete(_ names: [String]) {}
    }
    private final class Config: SSHConfigPort, @unchecked Sendable {
        let url: URL
        init(_ url: URL) { self.url = url }
        func read() -> String? { try? String(contentsOf: url, encoding: .utf8) }
        func write(_ text: String) -> Bool {
            (try? text.write(to: url, atomically: true, encoding: .utf8)) != nil
        }
    }
    private struct Known: KnownHostsPort {
        let url: URL
        func read() -> String? { "github.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5 me@mac\n" }
        func write(_ text: String) -> Bool { true }
    }
    private struct Keys: SSHKeysPort {
        let directory: URL
        func names() -> KeyInventory.Listing? { [] }
        func facts(for pair: KeyInventory.Pair) -> KeyFacts {
            KeyFacts(pair: pair, describeLine: "", mode: 0o600,
                     modified: Date(timeIntervalSince1970: 0), publicText: "", isDirectory: false)
        }
        func directoryMode() -> mode_t? { 0o700 }
        func chmod(_ name: String, to mode: mode_t) -> Bool { false }
        func chmodDirectory(to mode: mode_t) -> Bool { false }
    }
    private struct Agent: SSHAgentPort {
        func list() -> AgentList { .empty }
        func load(_ name: String, answering secret: inout Data) -> AgentLoad {
            secret = Data(); return .needsPassphrase
        }
        func unload(_ name: String) -> Bool { false }
    }
    private struct Generator: KeyGeneratorPort {
        func generate(_ arguments: [String], answering secret: inout Data) -> Int32 {
            secret = Data(); return 1
        }
    }

    private static let width: CGFloat = 900
    private static let height: CGFloat = 700

    private var renders: [MountedRender] = []
    private var engines: [HostsEngine] = []

    override func tearDown() async throws {
        await MainActor.run { renders.forEach { $0.drop() }; renders = []; engines = [] }
    }

    /// Every block-sized rounded layer, in points from the top.
    private func wells(_ mounted: MountedRender) -> [CGRect] {
        guard let root = mounted.host.layer else { return [] }
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
        return found
    }

    private func console(_ appearance: NSAppearance.Name) async throws -> CGRect {
        let brew = Brew()
        let mvm = ModuleViewModel(transport: brew)
        let hb = HomebrewViewModel.shared(vm: mvm)
        hb.clearConsole()
        let mounted = MountedRender(HomebrewSettingsPage(vm: mvm), width: Self.width, height: Self.height,
                                    appearance: appearance)
        renders.append(mounted)
        mounted.settle(20)
        await hb.loadIfNeeded()
        brew.say("==> Pouring wget--1.25.0.arm64_tahoe.bottle.tar.gz")
        await waitUntil("the console's first line") { !hb.consoleLines.isEmpty }
        mounted.settle(60)
        let found = wells(mounted)
        XCTAssertEqual(found.count, 1, "Homebrew: \(found.count) block-sized wells drew, the console is one")
        return try XCTUnwrap(found.first, "Homebrew: the console drew no well — there is nothing to measure against")
    }

    private func textBox(_ appearance: NSAppearance.Name) async throws -> CGRect {
        let home = scratchDirectory("hosts-beside-console")
        let ssh = home.appendingPathComponent(".ssh")
        try FileManager.default.createDirectory(at: ssh, withIntermediateDirectories: true)
        let config = ssh.appendingPathComponent("config")
        try "Host a\n    HostName a.example\n".write(to: config, atomically: true, encoding: .utf8)
        let engine = HostsEngine(file: File(), privileged: Root(), backups: NoBackups(),
                                 sshConfig: Config(config),
                                 knownHosts: Known(url: ssh.appendingPathComponent("known_hosts")),
                                 keys: Keys(directory: ssh), agent: Agent(), generator: Generator(),
                                 home: home, now: { Date(timeIntervalSince1970: 0) },
                                 transport: LocalTransport())
        engines.append(engine)
        let vm = ModuleViewModel(transport: engine.transport)
        await HostsViewModel.shared(vm: vm).firstLoad?.value
        let channel = HelmWindowToolbarChannel()
        let mounted = MountedRender(HostsSettingsPage(vm: vm), width: Self.width, height: Self.height,
                                    appearance: appearance, channel: channel)
        renders.append(mounted)
        mounted.settle(20)
        let onKeys = try XCTUnwrap(channel.content(for: HostsDescriptor.id.rawValue),
                                   "Hosts declared nothing onto the toolbar")
        try XCTUnwrap(onKeys.selectedTab, "Hosts declared no tabs").wrappedValue = "ssh"
        mounted.settle(20)
        let onSSH = try XCTUnwrap(channel.content(for: HostsDescriptor.id.rawValue))
        let viewMode = try XCTUnwrap(onSSH.actions.first { $0.id == "viewMode" }, "no view switcher")
        guard case let .segmented(_, selection) = viewMode.kind else {
            throw XCTSkip("the view switcher is not segmented")
        }
        selection.wrappedValue = "text"
        mounted.settle(40)
        XCTAssertFalse(mounted.host.everyView(ofType: NSTextView.self).isEmpty,
                       "precondition: the Text view drew no text view")
        let found = wells(mounted)
        XCTAssertEqual(found.count, 1, "Hosts: \(found.count) block-sized wells drew, the text box is one")
        return try XCTUnwrap(found.first, "Hosts: the Text view drew no well")
    }

    func testTheBoxKeepsTheConsolesMarginOnAllFourSides() async throws {
        for appearance in RenderedInk.bothAppearances {
            let what = RenderedInk.label(of: appearance)
            let brew = try await console(appearance)
            let step = brew.minX
            // The reference is one number: the console's own sides and bottom
            // agree, and it is a margin at all.
            XCTAssertGreaterThan(step, 0, "\(what): the console touches the page's leading edge")
            XCTAssertEqual(Self.width - brew.maxX, step, accuracy: 0.5,
                           "\(what): the console's right gap is not its left gap")
            XCTAssertEqual(Self.height - brew.maxY, step, accuracy: 0.5,
                           "\(what): the console's bottom gap is not its side gap")

            let box = try await textBox(appearance)
            let gaps: [(String, CGFloat)] = [
                ("top", box.minY),
                ("left", box.minX),
                ("right", Self.width - box.maxX),
                ("bottom", Self.height - box.maxY),
            ]
            for (edge, gap) in gaps {
                XCTAssertEqual(gap, step, accuracy: 0.5, """
                    \(what): the SSH text box is \(gap) pt from the page's \(edge) edge; \
                    the Homebrew console is \(step) pt from its page's edges
                    """)
            }
        }
    }
}
