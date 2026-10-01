import AppKit
import HelmContract
import HelmRuntime
import HelmTestSupport
import HelmUI
import SwiftUI
import XCTest
@testable import Module_Hosts_Engine
@testable import Module_Hosts_UI

/// **The SSH tab's plain-text box keeps its inset on all four sides with the
/// file the way people have it: long, editable, scrolled, selected — and
/// reached through the toolbar, not through a test seam.**
///
/// `ThePlainTextBoxIsInsetAtTheTopAndTheLeftTests` reads the box at rest, over a
/// two-line file the page may not write, opened by `init(vm:opensOnSSHText:)`;
/// it measures the top and the left only. What that leaves unread, and what
/// this file reads:
///
/// - **the bottom and the right.** A two-line file never reaches either, so
///   the box is scrolled to its last line with every character selected; the
///   selection is painted to the text container's edge, which is how the right
///   margin becomes something with ink at it. Dropping the trailing or bottom
///   half of the padding (`.padding([.top, .leading], …)`) leaves the other
///   check green and turns this one red;
/// - **the narrowest pane** (490 pt, as `HostsRowsFitTheMinimumPaneTests`
///   derives it) as well as a wide one;
/// - **a writable file**, so the text view is live rather than disabled;
/// - **the platform's own fill inside the well.** With the well drawn and
///   `scrollContentBackground(.hidden)` gone, the slab is back *inside* the
///   box — a box within a box — and the gutter reading beside it stays at zero.
///   So the bottom of a short file's box, ring and interior together, must be
///   one fill;
/// - **the way a person gets there**: Keys, then the SSH tab and the Text
///   view through the page's own toolbar declaration, then Table and Text
///   again — a box that exists only on the seam's first frame is not the fix.
@MainActor
final class ThePlainTextBoxKeepsItsInsetWhereverTheTextGoesTests: XCTestCase {

    /// `~/.ssh/config` as a real file inside a scratch home, so
    /// `SSHFileScope.mayWrite` answers yes and the text view is editable.
    private final class ScratchSSHConfig: SSHConfigPort, @unchecked Sendable {
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

    /// Long enough to scroll several screens, with a line of prose that wraps
    /// and a token with no break in it — and no newline at the end, so the
    /// last line is what sits on the bottom edge once scrolled there.
    private static let longFile: String = {
        var text = ""
        for index in 1...120 { text += "Host h\(index)\n    HostName host-\(index).example.internal\n" }
        text += "# " + String(repeating: "wordy ", count: 120) + "\n"
        text += "# " + String(repeating: "x", count: 600) + "\n"
        text += "Host last\n    HostName the-last-line-of-the-file"
        return text
    }()

    private func model(_ text: String) throws -> ModuleViewModel {
        let home = scratchDirectory("hosts-textbox")
        let ssh = home.appendingPathComponent(".ssh")
        try FileManager.default.createDirectory(at: ssh, withIntermediateDirectories: true)
        let config = ssh.appendingPathComponent("config")
        try text.write(to: config, atomically: true, encoding: .utf8)
        let engine = HostsEngine(file: FixedFile("127.0.0.1\tlocalhost\n"),
                                 privileged: FixedPrivileged(.declined),
                                 backups: MemoryBackups(),
                                 sshConfig: ScratchSSHConfig(config),
                                 knownHosts: WireKnownHosts(), keys: WireKeys(), agent: WireAgent(),
                                 generator: WireKeyGenerator(),
                                 home: home,
                                 now: { Date(timeIntervalSince1970: 0) },
                                 transport: LocalTransport())
        engines.append(engine)
        return ModuleViewModel(transport: engine.transport)
    }

    private func declared(_ channel: HelmWindowToolbarChannel) throws -> HelmPageToolbarContent {
        try XCTUnwrap(channel.content(for: HostsDescriptor.id.rawValue),
                      "the page declared nothing onto the toolbar")
    }

    private func chooseTab(_ id: String, _ channel: HelmWindowToolbarChannel) throws {
        try XCTUnwrap(declared(channel).selectedTab).wrappedValue = id
    }

    private func chooseView(_ id: String, _ channel: HelmWindowToolbarChannel) throws {
        let action = try XCTUnwrap(declared(channel).actions.first { $0.id == "viewMode" })
        guard case let .segmented(options, selection) = action.kind,
              options.contains(where: { $0.id == id }) else {
            return XCTFail("the view switcher does not offer \(id)")
        }
        selection.wrappedValue = id
    }

    /// The page as a person opens it — `init(vm:)`, which lands on Keys — then
    /// the SSH tab and its Text view, both through the toolbar.
    private func open(_ text: String, width: CGFloat, height: CGFloat = 500,
                      _ appearance: NSAppearance.Name) async throws -> (MountedRender, HelmWindowToolbarChannel) {
        let vm = try model(text)
        await HostsViewModel.shared(vm: vm).firstLoad?.value
        let channel = HelmWindowToolbarChannel()
        let mounted = MountedRender(HostsSettingsPage(vm: vm), width: width, height: height,
                                    appearance: appearance, channel: channel)
        renders.append(mounted)
        mounted.settle(20)
        try chooseTab("ssh", channel)
        mounted.settle(20)
        try chooseView("text", channel)
        mounted.settle(40)
        return (mounted, channel)
    }

    /// Every block-sized rounded layer, in points from the top.
    private func wells(_ mounted: MountedRender) -> [CGRect] {
        guard let root = mounted.host.layer else { return [] }
        var found: [CGRect] = []
        func walk(_ layer: CALayer) {
            if layer.cornerRadius > 0.01, layer.bounds.height > 100 {
                found.append(layer.convert(layer.bounds, to: root))
            }
            layer.sublayers?.forEach(walk)
        }
        walk(root)
        return found.map { frame in
            let top = root.isGeometryFlipped ? frame.minY : mounted.host.bounds.height - frame.maxY
            return CGRect(x: frame.minX, y: top, width: frame.width, height: frame.height)
        }
    }

    private func box(_ mounted: MountedRender, _ what: String) throws -> CGRect {
        let found = wells(mounted)
        XCTAssertEqual(found.count, 1, "\(what): \(found.count) block-sized wells drew, the text box is one")
        return try XCTUnwrap(found.first, "\(what): no well around the text")
    }

    private func ink(_ mounted: MountedRender, rows: ClosedRange<CGFloat>,
                     columns: ClosedRange<CGFloat>) throws -> Int {
        try XCTUnwrap(RenderedInk.read(mounted.host,
                                       points: Int(rows.lowerBound.rounded(.up))...Int(rows.upperBound.rounded(.down)),
                                       columns: Int(columns.lowerBound.rounded(.up))...Int(columns.upperBound.rounded(.down))))
    }

    /// Scrolled to the last line with everything selected, at the narrowest
    /// pane and a wide one, in both appearances: the margin on each side holds
    /// nothing, and the band just inside it holds text or selection.
    func testTheMarginHoldsOnEverySideAtTheEndOfALongSelectedFile() async throws {
        let inset = HostsSettingsPage.textBoxInset
        let corner = HelmRadius.card + 2
        for appearance in RenderedInk.bothAppearances {
            for width: CGFloat in [490, 900] {
                let (mounted, _) = try await open(Self.longFile, width: width, appearance)
                let what = "\(RenderedInk.label(of: appearance)), \(Int(width)) pt"
                let textView = try XCTUnwrap(mounted.host.everyView(ofType: NSTextView.self).first,
                                             "\(what): no text view in the Text view")
                XCTAssertTrue(textView.isEditable, "\(what): a writable config drew a text view nobody can type in")
                mounted.window?.makeFirstResponder(textView)
                textView.selectAll(nil)
                textView.scrollToEndOfDocument(nil)
                mounted.settle(20)
                let box = try box(mounted, what)

                let across = (box.minX + corner)...(box.maxX - corner)
                let down = (box.minY + corner)...(box.maxY - corner)
                let margins: [(String, ClosedRange<CGFloat>, ClosedRange<CGFloat>, ClosedRange<CGFloat>, ClosedRange<CGFloat>)] = [
                    ("top", (box.minY + 2)...(box.minY + inset - 1), across,
                     (box.minY + inset + 1)...(box.minY + inset + 12), across),
                    ("bottom", (box.maxY - inset + 1)...(box.maxY - 2), across,
                     (box.maxY - inset - 12)...(box.maxY - inset - 1), across),
                    ("left", down, (box.minX + 2)...(box.minX + inset - 1),
                     down, (box.minX + inset + 1)...(box.minX + inset + 12)),
                    ("right", down, (box.maxX - inset + 1)...(box.maxX - 2),
                     down, (box.maxX - inset - 12)...(box.maxX - inset - 1)),
                ]
                for (edge, marginRows, marginColumns, insideRows, insideColumns) in margins {
                    XCTAssertGreaterThan(try ink(mounted, rows: insideRows, columns: insideColumns), 0,
                                         "\(what): nothing drew just inside the \(edge) margin, so its emptiness says nothing")
                    XCTAssertEqual(try ink(mounted, rows: marginRows, columns: marginColumns), 0,
                                   "\(what): text or selection reaches into the \(inset) pt at the \(edge) edge")
                }
                mounted.drop()
            }
        }
    }

    /// The well is one fill: below a short file, the inset ring and the empty
    /// text area are the same colour. The text view's own fill inside the well
    /// makes the two differ.
    func testTheWellIsOneFillAroundAndBehindTheText() async throws {
        let corner = HelmRadius.card + 2
        for appearance in RenderedInk.bothAppearances {
            let (mounted, _) = try await open("Host a\n    HostName a.example\n", width: 900, appearance)
            let what = RenderedInk.label(of: appearance)
            let box = try box(mounted, what)
            let rows = (box.maxY - 60)...(box.maxY - 2)
            // The subject: the same rows, reaching out past the box into the
            // pane, read the well as ink — so the well is really there to be
            // one fill or two.
            XCTAssertGreaterThan(try ink(mounted, rows: rows, columns: 0...(box.minX + 40)), 0,
                                 "\(what): the well draws nothing distinct from the pane")
            XCTAssertEqual(try ink(mounted, rows: rows, columns: (box.minX + corner)...(box.maxX - corner)), 0,
                           "\(what): the empty text area and the ring around it are two colours — the text view's own fill is inside the well")
            mounted.drop()
        }
    }

    /// Table, then Text again, then Keys and back: every time the Text view is
    /// on screen it is one well with an empty gutter; the Table view draws
    /// none.
    func testTheBoxComesBackTheSameAfterEverySwitch() async throws {
        for appearance in RenderedInk.bothAppearances {
            let (mounted, channel) = try await open("Host a\n    HostName a.example\n", width: 900, appearance)
            let what = RenderedInk.label(of: appearance)
            func textViewIsBoxed(_ step: String) throws {
                let box = try box(mounted, "\(what), \(step)")
                let rows = Int(box.minY.rounded(.up)) + 8...Int(box.maxY.rounded(.down)) - 8
                XCTAssertEqual(try XCTUnwrap(RenderedInk.read(mounted.host, points: rows,
                                                              columns: 0...Int((box.minX - 4).rounded(.down)))),
                               0, "\(what), \(step): the text view's fill shows beside the box")
                XCTAssertFalse(mounted.host.everyView(ofType: NSTextView.self).isEmpty,
                               "\(what), \(step): the Text view drew no text view")
            }
            try textViewIsBoxed("opened through the toolbar")
            try chooseView("table", channel); mounted.settle(40)
            XCTAssertTrue(mounted.host.everyView(ofType: NSTextView.self).isEmpty,
                          "\(what): the Table view still holds the text view")
            try chooseView("text", channel); mounted.settle(40)
            try textViewIsBoxed("Table, then Text")
            try chooseTab("keys", channel); mounted.settle(30)
            try chooseTab("ssh", channel); mounted.settle(40)
            try textViewIsBoxed("Keys, then SSH")
            mounted.drop()
        }
    }
}
