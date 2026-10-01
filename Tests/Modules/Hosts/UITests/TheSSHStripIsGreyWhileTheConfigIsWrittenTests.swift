import AppKit
import HelmContract
import HelmRuntime
import HelmTestSupport
import HelmUI
import SwiftUI
import XCTest
@testable import Module_Hosts_Engine
@testable import Module_Hosts_UI

/// **While the config is being written, the strip's two buttons are drawn
/// grey, and a second Apply does not reach the disk.**
///
/// `AnApplyInFlightIsNotRevertedTests` holds the model's half: `revertSSH()`
/// does nothing while `sshApplying` is true. Nothing held the page's half —
/// the two `.disabled(hvm.sshApplying)` on the strip could go and every other
/// check stayed green, leaving a Revert that looks pressable and does nothing,
/// and an Apply that looks pressable and is swallowed by the model's guard.
/// So the buttons are read off the drawing: SwiftUI draws them itself (no
/// `NSButton` is in the tree), and what disabling changes on screen is the
/// label's ink, which is what is measured here, per button.
///
/// The second half: `applySSH()` refuses to start while a write is in flight.
/// Deleted, a second press sends the same text again and its `defer` clears
/// the flag while the first write is still inside the port.
///
/// The config port holds the write on a semaphore, so the test stands inside
/// the write for as long as it likes — a port that answered at once would
/// release the flag before anything could be read.
@MainActor
final class TheSSHStripIsGreyWhileTheConfigIsWrittenTests: XCTestCase {

    private final class GatedConfig: SSHConfigPort, @unchecked Sendable {
        let url: URL
        let gate = DispatchSemaphore(value: 0)
        private let lock = NSLock()
        private var entered = 0
        init(_ url: URL) { self.url = url }
        var writes: Int { lock.lock(); defer { lock.unlock() }; return entered }
        func read() -> String? { try? String(contentsOf: url, encoding: .utf8) }
        func write(_ text: String) -> Bool {
            lock.lock(); entered += 1; lock.unlock()
            _ = gate.wait(timeout: .now() + 5)
            return (try? text.write(to: url, atomically: true, encoding: .utf8)) != nil
        }
    }

    private var engines: [HostsEngine] = []
    private var mounts: [MountedRender] = []

    override func tearDown() async throws {
        await MainActor.run { mounts.forEach { $0.drop() }; mounts = []; engines = [] }
    }

    private func model(_ label: String) async throws -> (HostsViewModel, GatedConfig, ModuleViewModel) {
        let home = scratchDirectory(label)
        let ssh = home.appendingPathComponent(".ssh")
        try FileManager.default.createDirectory(at: ssh, withIntermediateDirectories: true)
        let url = ssh.appendingPathComponent("config")
        try "Host a\n    HostName a.example\n".write(to: url, atomically: true, encoding: .utf8)
        let config = GatedConfig(url)
        let engine = HostsEngine(file: FixedFile("127.0.0.1\tlocalhost\n"),
                                 privileged: FixedPrivileged(.declined),
                                 backups: MemoryBackups(),
                                 sshConfig: config, knownHosts: WireKnownHosts(),
                                 keys: WireKeys(), agent: WireAgent(),
                                 generator: WireKeyGenerator(),
                                 home: home,
                                 now: { Date(timeIntervalSince1970: 0) },
                                 transport: LocalTransport())
        engines.append(engine)
        let vm = ModuleViewModel(transport: engine.transport)
        let hvm = HostsViewModel.shared(vm: vm)
        await hvm.firstLoad?.value
        return (hvm, config, vm)
    }

    private func waitInside(_ config: GatedConfig, count: Int = 1) async throws {
        let deadline = Date().addingTimeInterval(3)
        while config.writes < count, Date() < deadline { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertEqual(config.writes, count, "precondition — the engine never reached the write")
    }

    /// The text box's top in the host's top-left points: the rounded layer
    /// over 100 pt tall.
    private func boxTop(_ host: NSView) -> CGFloat? {
        guard let root = host.layer else { return nil }
        var found: [CGFloat] = []
        func walk(_ layer: CALayer) {
            if layer.cornerRadius > 0.01, layer.bounds.height > 100, layer.bounds.width >= 300 {
                let frame = layer.convert(layer.bounds, to: root)
                found.append(root.isGeometryFlipped ? frame.minY : host.bounds.height - frame.maxY)
            }
            layer.sublayers?.forEach(walk)
        }
        walk(root)
        return found.min()
    }

    /// One button on the strip: its columns in points, and the strongest ink
    /// inside them — the label, since the bezel is a faint fill.
    private struct Drawn { let left: CGFloat; let right: CGFloat; let pixels: ClosedRange<Int>; let ink: Int }

    /// The strip's buttons, read off the pixels of `rows` (points from the
    /// top) right of the middle, where the strip draws nothing else when
    /// `known_hosts` is readable. A column belongs to a button when any pixel
    /// in it differs from the page; a run of such columns is one button.
    private func buttons(_ host: NSView, rows: ClosedRange<Int>,
                         columns: [ClosedRange<Int>]? = nil) -> [Drawn] {
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return [] }
        host.cacheDisplay(in: host.bounds, to: rep)
        guard let data = rep.bitmapData, rep.samplesPerPixel == 4, rep.bitsPerSample == 8 else { return [] }
        let scale = max(1, rep.pixelsHigh / max(1, Int(host.bounds.height)))
        let y0 = rows.lowerBound * scale, y1 = min(rep.pixelsHigh, (rows.upperBound + 1) * scale)
        // All four channels: the page is transparent in this mount, so black
        // ink on it differs from the background in alpha alone.
        func distance(_ x: Int, _ y: Int) -> Int {
            let o = y * rep.bytesPerRow + x * 4, b = y * rep.bytesPerRow
            return (0..<4).map { abs(Int(data[o + $0]) - Int(data[b + $0])) }.max() ?? 0
        }
        func inkIn(_ span: ClosedRange<Int>) -> Int {
            var best = 0
            for y in y0..<y1 { for x in span { best = max(best, distance(x, y)) } }
            return best
        }
        let spans: [ClosedRange<Int>]
        if let columns {
            spans = columns
        } else {
            var found: [ClosedRange<Int>] = []
            var start: Int?
            for x in (rep.pixelsWide / 2)..<rep.pixelsWide {
                let marked = (y0..<y1).contains { distance(x, $0) > 4 }
                if marked, start == nil { start = x }
                if !marked, let s = start { found.append(s...(x - 1)); start = nil }
            }
            if let s = start { found.append(s...(rep.pixelsWide - 1)) }
            spans = found.filter { $0.count > 20 * scale }
        }
        return spans.map { Drawn(left: CGFloat($0.lowerBound) / CGFloat(scale),
                                 right: CGFloat($0.upperBound + 1) / CGFloat(scale), pixels: $0, ink: inkIn($0)) }
    }

    func testBothButtonsAreDrawnGreyWhileTheWriteIsInFlightAndLiveAgainAfter() async throws {
        for appearance in RenderedInk.bothAppearances {
            let what = RenderedInk.label(of: appearance)
            let (hvm, config, vm) = try await model("hosts-grey-\(what)")
            let mounted = MountedRender(HostsSettingsPage(vm: vm, opensOnSSHText: true), width: 900, height: 500,
                                        appearance: appearance, channel: HelmWindowToolbarChannel())
            mounts.append(mounted)
            mounted.settle(20)
            XCTAssertTrue(hvm.knownHostsReadable, "\(what): precondition — a note would share the strip")
            hvm.setSSHText(hvm.sshText + "# typed\n")
            mounted.settle(40)
            // The strip's rows: above its divider, which stands one margin
            // over the box — the one rounded layer taller than 100 pt.
            let boxTop = try XCTUnwrap(boxTop(mounted.host), "\(what): no text box drawn")
            let rows = 0...Int(boxTop - HostsSettingsPage.textBoxMargin - 2)
            XCTAssertGreaterThan(rows.upperBound, 20, "\(what): precondition — the strip did not open (box at \(boxTop))")

            let idle = buttons(mounted.host, rows: rows)
            XCTAssertEqual(idle.count, 2, "\(what): precondition — the strip does not draw Revert and Apply as two buttons: \(idle)")
            let columns = idle.map(\.pixels)

            let apply = Task { await hvm.applySSH() }
            try await waitInside(config)
            mounted.settle(20)
            XCTAssertTrue(hvm.sshApplying, "\(what): precondition — the model does not know a write is in flight")
            let writing = buttons(mounted.host, rows: rows, columns: columns)
            for (name, (before, during)) in zip(["Revert", "Apply"], zip(idle, writing)) {
                XCTAssertLessThan(Double(during.ink), Double(before.ink) * 0.7,
                                  "\(what): \(name) is drawn with ink \(during.ink) while the config is written, against \(before.ink) at rest — it looks pressable")
            }

            config.gate.signal()
            await apply.value
            // The control: the same reading, after the answer, on an edit made
            // after it — the buttons are live again, so the grey above was the
            // write's and not the harness's.
            hvm.setSSHText(hvm.sshText + "# again\n")
            mounted.settle(40)
            XCTAssertFalse(hvm.sshApplying)
            let after = buttons(mounted.host, rows: rows, columns: columns)
            for (name, (before, again)) in zip(["Revert", "Apply"], zip(idle, after)) {
                XCTAssertEqual(Double(again.ink), Double(before.ink), accuracy: Double(before.ink) * 0.1,
                               "\(what): \(name) did not come back live after the answer (\(again.ink) against \(before.ink))")
            }
            mounted.drop()
        }
    }

    func testASecondApplyDuringTheWriteDoesNotReachTheDisk() async throws {
        let (hvm, config, _) = try await model("hosts-second-apply")
        hvm.setSSHText(hvm.sshText + "# typed\n")
        let first = Task { await hvm.applySSH() }
        try await waitInside(config)
        let second = Task { await hvm.applySSH() }
        await second.value
        XCTAssertTrue(hvm.sshApplying,
                      "the second Apply returned and cleared the flag while the first write is still inside the port")
        config.gate.signal()
        await first.value
        // Room for a second request to arrive at the port, had one been sent;
        // the gate is signalled again so such a request would not hang.
        config.gate.signal()
        await grace(0.3)
        XCTAssertEqual(config.writes, 1, "a second Apply pressed during the write reached the disk again")
        XCTAssertFalse(hvm.sshApplying)
        XCTAssertEqual(hvm.sshOutcome, .applied)
    }
}
