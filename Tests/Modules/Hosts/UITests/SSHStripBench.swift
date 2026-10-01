import AppKit
import HelmContract
import HelmRuntime
import HelmTestSupport
import HelmUI
import SwiftUI
import XCTest
@testable import Module_Hosts_Engine
@testable import Module_Hosts_UI

/// The SSH tab of the Hosts page mounted offscreen, with the ports the strip
/// over it reads — the config, and a `known_hosts` that can be missing or
/// refuse a write — and the readings the strip's checks take off it: where the
/// text box's top is, where the caret sits, and the pixels above the box.
///
/// Used by the checks that drive the strip from the outside — how it grows
/// and goes, what it leaves still, where its edges stand, what a Revert leaves
/// of a refusal. Older checks in this directory build their own engine and
/// their own walk over the layer tree; they are not on it, and this doc does
/// not claim them.
@MainActor
final class SSHStripBench {

    final class Config: SSHConfigPort, @unchecked Sendable {
        let url: URL
        init(_ url: URL) { self.url = url }
        func read() -> String? { try? String(contentsOf: url, encoding: .utf8) }
        func write(_ text: String) -> Bool {
            (try? text.write(to: url, atomically: true, encoding: .utf8)) != nil
        }
    }

    /// `known_hosts` as a value the test sets: `nil` is a missing file, and a
    /// refused write is what makes a Forget come back as something other than
    /// `.applied`.
    final class Known: KnownHostsPort, @unchecked Sendable {
        let url: URL
        var text: String?
        var writes: Bool
        init(url: URL, text: String?, writes: Bool) {
            self.url = url; self.text = text; self.writes = writes
        }
        func read() -> String? { text }
        func write(_ text: String) -> Bool { writes }
    }

    static let trusted = "github.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5 me@mac\n"

    let mounted: MountedRender
    let channel: HelmWindowToolbarChannel
    let hvm: HostsViewModel
    let known: Known
    private let engine: HostsEngine

    /// Mounts the page and brings it to the SSH tab the way a person does —
    /// the toolbar's tab, then its view switcher — unless `seam` is set, in
    /// which case the page is built already on the text box
    /// (`HostsSettingsPage(vm:opensOnSSHText:)`). `onFirstLayout` runs on the
    /// turn the SSH tab is first asked for, before anything settles, so a
    /// caller can sample from the very first frame the tab draws.
    init(_ appearance: NSAppearance.Name, directory: URL, known: String? = SSHStripBench.trusted,
         knownWrites: Bool = true, mode: String = "text", seam: Bool = false,
         configDirectory: URL? = nil,
         onFirstLayout: ((MountedRender) -> Void)? = nil) async throws {
        let ssh = directory.appendingPathComponent(".ssh")
        try FileManager.default.createDirectory(at: ssh, withIntermediateDirectories: true)
        // `configDirectory` puts the config outside the home, which the engine's
        // gate refuses to write: the page then says so in a banner.
        let configURL = (configDirectory ?? ssh).appendingPathComponent("config")
        try "Host a\n    HostName a.example\n".write(to: configURL, atomically: true, encoding: .utf8)
        let knownPort = Known(url: ssh.appendingPathComponent("known_hosts"), text: known, writes: knownWrites)
        engine = HostsEngine(file: FixedFile("127.0.0.1\tlocalhost\n"),
                             privileged: FixedPrivileged(.declined),
                             backups: MemoryBackups(),
                             sshConfig: Config(configURL), knownHosts: knownPort,
                             keys: WireKeys(), agent: WireAgent(),
                             generator: WireKeyGenerator(),
                             home: directory,
                             now: { Date(timeIntervalSince1970: 0) },
                             transport: LocalTransport())
        self.known = knownPort
        let vm = ModuleViewModel(transport: engine.transport)
        hvm = HostsViewModel.shared(vm: vm)
        await hvm.firstLoad?.value
        channel = HelmWindowToolbarChannel()
        mounted = MountedRender(HostsSettingsPage(vm: vm, opensOnSSHText: seam), width: 900, height: 500,
                                appearance: appearance, channel: channel)
        if seam {
            onFirstLayout?(mounted)
            mounted.settle(20)
            return
        }
        mounted.settle(20)
        try select(tab: "ssh")
        onFirstLayout?(mounted)
        mounted.settle(20)
        try select(mode: mode)
        mounted.settle(40)
    }

    func select(tab: String) throws {
        try XCTUnwrap(try XCTUnwrap(channel.content(for: HostsDescriptor.id.rawValue)).selectedTab)
            .wrappedValue = tab
    }

    func select(mode: String) throws {
        let action = try XCTUnwrap(try XCTUnwrap(channel.content(for: HostsDescriptor.id.rawValue))
            .actions.first { $0.id == "viewMode" })
        guard case let .segmented(_, selection) = action.kind else {
            XCTFail("the view switcher is not a segmented choice any more"); return
        }
        selection.wrappedValue = mode
    }

    var textView: NSTextView? { mounted.host.everyView(ofType: NSTextView.self).first }

    /// Rounded layers at least 300 pt wide, in the host's top-left points:
    /// the text box is the one over 100 pt tall, a table card or a banner the
    /// shorter ones.
    func rounded(minHeight: CGFloat = 0) -> [CGRect] {
        guard let root = mounted.host.layer else { return [] }
        var found: [CGRect] = []
        func walk(_ layer: CALayer) {
            if layer.cornerRadius > 0.01, layer.bounds.height > minHeight, layer.bounds.width >= 300 {
                let frame = layer.convert(layer.bounds, to: root)
                let top = root.isGeometryFlipped ? frame.minY : mounted.host.bounds.height - frame.maxY
                found.append(CGRect(x: frame.minX, y: top, width: frame.width, height: frame.height))
            }
            layer.sublayers?.forEach(walk)
        }
        walk(root)
        return found
    }

    /// The text box's top, or nil when no box is drawn.
    var boxTop: CGFloat? { rounded(minHeight: 100).first?.minY }

    /// The top of whatever rounded surface is highest — the box in the text
    /// view, the first card in the table.
    var firstSurfaceTop: CGFloat? { rounded().map(\.minY).min() }

    /// The top of the line the caret is on, in the host's top-left points.
    var caretTop: CGFloat? {
        guard let tv = textView, let lm = tv.layoutManager, let tc = tv.textContainer else { return nil }
        let length = (tv.string as NSString).length
        guard length > 0 else { return nil }
        let at = min(tv.selectedRange().location, length - 1)
        var rect = lm.boundingRect(forGlyphRange: NSRange(location: lm.glyphIndexForCharacter(at: at), length: 1),
                                   in: tc)
        rect.origin.x += tv.textContainerOrigin.x
        rect.origin.y += tv.textContainerOrigin.y
        let inHost = mounted.host.convert(rect, from: tv)
        return mounted.host.isFlipped ? inHost.minY : mounted.host.bounds.height - inHost.maxY
    }

    /// The leftmost and rightmost columns, in points, at which the rows
    /// `rows` (points from the top) differ from the page's own background —
    /// which is what the row's leftmost pixel is, since nothing on this page
    /// draws to the edge. nil when the bitmap cannot be read, and never a
    /// guess: a band that ran off the image would otherwise read as empty.
    func inkSpan(rows: ClosedRange<Int>) -> (left: CGFloat, right: CGFloat)? {
        let view = mounted.host
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let data = rep.bitmapData, rep.samplesPerPixel == 4, rep.bitsPerSample == 8,
              rep.pixelsWide > 0, rep.pixelsHigh > 0 else { return nil }
        let scale = max(1, rep.pixelsHigh / max(1, Int(view.bounds.height)))
        guard rows.lowerBound >= 0, rows.upperBound * scale <= rep.pixelsHigh else { return nil }
        var left = Int.max, right = -1
        for y in (rows.lowerBound * scale)..<(rows.upperBound * scale) {
            let row = y * rep.bytesPerRow
            for x in 0..<rep.pixelsWide {
                var far = 0
                for channel in 0..<4 { far = max(far, abs(Int(data[row + x * 4 + channel]) - Int(data[row + channel]))) }
                if far > 3 { left = min(left, x); right = max(right, x) }
            }
        }
        guard right >= 0 else { return nil }
        return (CGFloat(left) / CGFloat(scale), CGFloat(right + 1) / CGFloat(scale))
    }

    /// One turn of the run loop and a reading, repeated for `seconds`, with
    /// the clock: `act` runs before each turn with the sample's index.
    func sample<T>(seconds: Double, step: Double = 0.005, act: ((Int) -> Void)? = nil,
                   _ read: () -> T) -> [(ms: Int, value: T)] {
        var out: [(ms: Int, value: T)] = []
        let start = Date()
        var index = 0
        while Date().timeIntervalSince(start) < seconds {
            act?(index)
            mounted.host.layoutSubtreeIfNeeded()
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(step))
            out.append((Int(Date().timeIntervalSince(start) * 1000), read()))
            index += 1
        }
        return out
    }

    /// Positions strictly between two ends, at half-point resolution.
    static func between(_ values: [CGFloat], _ low: CGFloat, _ high: CGFloat) -> [CGFloat] {
        values.filter { $0 > low + 1 && $0 < high - 1 }
    }

    func drop() { mounted.drop() }
}
