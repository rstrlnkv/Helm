import AppKit
import HelmContract
import HelmRuntime
import HelmTestSupport
import HelmUI
import SwiftUI
import XCTest
@testable import Module_Hosts_Engine
@testable import Module_Hosts_UI

/// **The strip over the SSH text box grows in, and the banner over it stands
/// where the box stands.**
///
/// - The strip is drawn only while it has something to say
///   (`TheSSHHeaderComesAndGoesWithWhatItSaysTests`), so the first
///   typed letter puts it there. Put in by `if`, the box and the caret under it
///   moved 37 pt in one frame. It is revealed as every other block here is —
///   `helmAccordion`, a measured height under a clip on `HelmMotion.disclosure`
///   — and the box's top is sampled against the clock until it rests: it has to
///   pass through heights between the two ends, not land on the far one.
/// - The «not writable» banner sat in the page's 20 pt column while the box sat
///   at 12, a step of 8 pt on each side. Its edges are read off the layer tree
///   and must be the box's.
@MainActor
final class TheSSHHeaderRevealsAndTheBannerAlignsTests: XCTestCase {

    private final class Config: SSHConfigPort, @unchecked Sendable {
        let url: URL
        init(_ url: URL) { self.url = url }
        func read() -> String? { try? String(contentsOf: url, encoding: .utf8) }
        func write(_ text: String) -> Bool {
            (try? text.write(to: url, atomically: true, encoding: .utf8)) != nil
        }
    }

    private var renders: [MountedRender] = []
    private var engines: [HostsEngine] = []

    override func tearDown() async throws {
        await MainActor.run {
            renders.forEach { $0.drop() }
            renders = []
            engines = []
        }
    }

    private func open(_ appearance: NSAppearance.Name, outsideHome: Bool = false,
                      mode: String = "text") async throws -> (mounted: MountedRender, hvm: HostsViewModel) {
        let home = scratchDirectory("hosts-sshreveal-home")
        let ssh = home.appendingPathComponent(".ssh")
        try FileManager.default.createDirectory(at: ssh, withIntermediateDirectories: true)
        let configURL = (outsideHome ? scratchDirectory("hosts-sshreveal-elsewhere") : ssh)
            .appendingPathComponent("config")
        try "Host a\n    HostName a.example\n".write(to: configURL, atomically: true, encoding: .utf8)
        let engine = HostsEngine(file: FixedFile("127.0.0.1\tlocalhost\n"),
                                 privileged: FixedPrivileged(.declined),
                                 backups: MemoryBackups(),
                                 sshConfig: Config(configURL), knownHosts: WireKnownHosts(),
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
        try XCTUnwrap(try XCTUnwrap(channel.content(for: HostsDescriptor.id.rawValue)).selectedTab)
            .wrappedValue = "ssh"
        mounted.settle(20)
        let action = try XCTUnwrap(try XCTUnwrap(channel.content(for: HostsDescriptor.id.rawValue))
            .actions.first { $0.id == "viewMode" })
        guard case let .segmented(_, selection) = action.kind else { throw XCTSkip("no view switcher") }
        selection.wrappedValue = mode
        mounted.settle(40)
        return (mounted, hvm)
    }

    /// Every rounded layer of at least `minWidth` and at most `maxHeight`
    /// points tall, in the host's top-left coordinates.
    private func rounded(_ mounted: MountedRender, minHeight: CGFloat = 0, maxHeight: CGFloat = .infinity,
                         minWidth: CGFloat = 300) -> [CGRect] {
        guard let root = mounted.host.layer else { return [] }
        var found: [CGRect] = []
        func walk(_ layer: CALayer) {
            if layer.cornerRadius > 0.01, layer.bounds.height > minHeight,
               layer.bounds.height <= maxHeight, layer.bounds.width >= minWidth {
                let frame = layer.convert(layer.bounds, to: root)
                let top = root.isGeometryFlipped ? frame.minY : mounted.host.bounds.height - frame.maxY
                found.append(CGRect(x: frame.minX, y: top, width: frame.width, height: frame.height))
            }
            layer.sublayers?.forEach(walk)
        }
        walk(root)
        return found
    }

    private func boxTop(_ mounted: MountedRender) throws -> CGFloat {
        let wells = rounded(mounted, minHeight: 100)
        XCTAssertEqual(wells.count, 1, "\(wells.count) block-sized wells drew, the text box is one")
        return try XCTUnwrap(wells.first).minY
    }

    /// The box's top, read every ~10 ms for `seconds`, with the clock.
    private func trace(_ mounted: MountedRender, seconds: Double) throws -> [CGFloat] {
        var tops: [CGFloat] = []
        let end = Date().addingTimeInterval(seconds)
        while Date() < end {
            mounted.host.layoutSubtreeIfNeeded()
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
            tops.append(try boxTop(mounted))
        }
        return tops
    }

    private func distinctBetween(_ tops: [CGFloat], _ low: CGFloat, _ high: CGFloat) -> Int {
        Set(tops.filter { $0 > low + 1 && $0 < high - 1 }.map { ($0 * 2).rounded() }).count
    }

    func testTheStripGrowsInAndGoesOutInsteadOfJumping() async throws {
        try XCTSkipIf(HelmMotion.reduceMotion, "Reduce Motion is on: the reveal is meant to be instant")
        for appearance in RenderedInk.bothAppearances {
            let what = RenderedInk.label(of: appearance)
            let (mounted, hvm) = try await open(appearance)
            let rest = try boxTop(mounted)
            XCTAssertEqual(rest, HostsSettingsPage.textBoxMargin, accuracy: 0.5, "\(what): precondition")

            let textView = try XCTUnwrap(mounted.host.everyView(ofType: NSTextView.self).first)
            mounted.window?.makeFirstResponder(textView)
            textView.insertText("# typed\n", replacementRange: NSRange(location: 0, length: 0))
            let down = try trace(mounted, seconds: 0.8)
            let open = try XCTUnwrap(down.last)
            XCTAssertGreaterThan(open, rest + 20, "\(what): precondition — the strip never opened")
            XCTAssertGreaterThanOrEqual(distinctBetween(down, rest, open), 4,
                                        "\(what): the box went from \(rest) to \(open) in \(Set(down).count) distinct positions — a jump, not a reveal")

            hvm.revertSSH()
            let up = try trace(mounted, seconds: 0.8)
            XCTAssertEqual(try XCTUnwrap(up.last), rest, accuracy: 0.5, "\(what): the strip did not go")
            XCTAssertGreaterThanOrEqual(distinctBetween(up, rest, open), 4,
                                        "\(what): the box came back from \(open) to \(rest) in a jump, not a reveal")
            mounted.drop()
        }
    }

    func testTheNotWritableBannerStandsWhereTheBoxStands() async throws {
        for appearance in RenderedInk.bothAppearances {
            let what = RenderedInk.label(of: appearance)
            let (mounted, hvm) = try await open(appearance, outsideHome: true)
            XCTAssertFalse(hvm.sshWritable, "\(what): precondition — the file was writable")
            let wells = rounded(mounted, minHeight: 100)
            let banners = rounded(mounted, maxHeight: 100)
            XCTAssertEqual(wells.count, 1, "\(what): \(wells.count) wells")
            XCTAssertEqual(banners.count, 1, "\(what): \(banners.count) banner-sized rounded layers")
            let box = try XCTUnwrap(wells.first)
            let banner = try XCTUnwrap(banners.first)
            XCTAssertEqual(banner.minX, box.minX, accuracy: 0.5, "\(what): banner and box left edges differ")
            XCTAssertEqual(banner.maxX, box.maxX, accuracy: 0.5, "\(what): banner and box right edges differ")
            XCTAssertEqual(banner.minY, HostsSettingsPage.textBoxMargin, accuracy: 0.5,
                           "\(what): the banner is not on the page's top margin")
            XCTAssertEqual(box.minY - banner.maxY, HostsSettingsPage.textBoxMargin, accuracy: 0.5,
                           "\(what): the banner-to-box gap is not the margin")
            mounted.drop()
        }
    }

    /// Over the table the banner stands on the same edges and the same steps it
    /// stands on over the box: the margin from the page's edges and from the
    /// toolbar, and the margin to the first card — it was 20, 6 and 26.
    func testTheBannerOverTheTableStandsOnTheSameEdgeAndSteps() async throws {
        for appearance in RenderedInk.bothAppearances {
            let what = RenderedInk.label(of: appearance)
            let (mounted, hvm) = try await open(appearance, outsideHome: true, mode: "table")
            XCTAssertFalse(hvm.sshWritable, "\(what): precondition — the file was writable")
            let surfaces = rounded(mounted).sorted { $0.minY < $1.minY }
            XCTAssertGreaterThanOrEqual(surfaces.count, 2, "\(what): precondition — a banner and a card were not both drawn")
            let banner = try XCTUnwrap(surfaces.first)
            let card = surfaces[1]
            let margin = HostsSettingsPage.textBoxMargin
            XCTAssertEqual(banner.minX, margin, accuracy: 0.5, "\(what): banner left edge")
            XCTAssertEqual(banner.minY, margin, accuracy: 0.5, "\(what): banner is not on the top margin")
            XCTAssertEqual(card.minY - banner.maxY, margin, accuracy: 0.5, "\(what): banner-to-card gap is not the margin")
            XCTAssertEqual(card.minX, margin, accuracy: 0.5, "\(what): card left edge")
            mounted.drop()
        }
    }
}
