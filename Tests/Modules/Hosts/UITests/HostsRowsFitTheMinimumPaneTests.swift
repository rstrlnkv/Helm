import AppKit
import HelmContract
import HelmRuntime
import HelmTestSupport
import HelmUI
import SwiftUI
import XCTest
@testable import Module_Hosts_Engine
@testable import Module_Hosts_UI

/// **Nothing in this module may impose a width in points.**
///
/// It did: the hosts table pinned its address column at 220 pt, the keys table
/// pinned a field at 240 and the config table pinned a label column at 96. The
/// settings window's minimum is 860 pt, which leaves the pane about **490** —
/// and no number can be chosen that survives both a 47-character fingerprint
/// and whatever somebody's employer calls a build machine.
///
/// **A scan for `frame(width:` is not this test**, and the design says why: it
/// passes trivially the day somebody spells the same constant another way. So
/// the rows are rendered at the narrowest pane and at the widest, and four
/// things are read off the two drawings:
///
/// - a detail line is **one line** at the narrow pane. A row whose content
///   cannot fit reflows, and the fingerprint that wrapped to two lines was the
///   visible half of the complaint (measured before this change: the trusted
///   line's fingerprint drew 286 × 28 at 490 pt against 340 × 14 at 744 — the
///   same text, twice as tall);
/// - it is **wider at the wider pane**. A line pinned to a number is the same
///   width at both, which is what «imposes a width» means when it is measured
///   rather than read;
/// - the row's **leading edge does not move** between the two. A rigid child
///   too wide for its pane does not overflow to the right: SwiftUI centres the
///   row it is in, so the content walks in from the gutter — measured at 61.5 pt
///   against the 20 pt inset for a 420 pt frame in a 490 pt pane. That is the
///   same defect `TheLogPageStaysInsideItsGutterTests` records, where a
///   `maxX ≤ pane − inset` assertion went green over a row drifting into the
///   middle of the page;
/// - and nothing is drawn **past the gutter**.
///
/// The anchor is the drawn text itself — a `Text` with `textSelection(.enabled)`
/// is an `AppKitTextInteractionView` in the tree, so the fingerprint can be
/// found and measured rather than a decoration standing in for it. That is the
/// lesson recorded beside the log page's measurement the same day: anchor on
/// something that moves with the thing measured.
@MainActor
final class HostsRowsFitTheMinimumPaneTests: XCTestCase {

    /// The pane at `contentMinSize` (860) with the sidebar at its default —
    /// the narrowest a person can make this page without dragging anything.
    private let narrowest: CGFloat = 490
    /// The settings column, where nothing has ever been short of room.
    private let widest = HelmLayout.settingsColumn

    private var renders: [MountedRender] = []

    override func tearDown() {
        renders.forEach { $0.drop() }
        renders = []
        super.tearDown()
    }

    // MARK: - What is on the page

    /// Deliberately long, and every one of these is ordinary: a SHA-256
    /// fingerprint is 47 characters whatever the key, and a corporate host name
    /// is whatever it is. A row measured against `id_rsa` and `box` would fit
    /// at any width and prove nothing.
    private let fingerprint = "SHA256:5Xb9pQ2mK7vN8zR1tY4wA6cE0jH3sL5uD7fG9iO2kM8"
    private let comment = "rstrlnkv@MacBook-Pro-of-Rostislav.local"
    private let alias = "build-runner-eu-west-1"
    private let hostName = "build-runner-eu-west-1.internal.corp.example.com"

    private var config: String {
        """
        Host \(alias)
            HostName \(hostName)
            User rstrlnkv
            Port 2222
            IdentityFile ~/.ssh/id_ed25519_work_laptop

        """
    }

    /// **The key really decodes**, which is not decoration: a base64 blob whose
    /// length is not a multiple of four comes back `nil` from
    /// `Entry.fingerprint`, the row draws no fingerprint at all, and the
    /// readings below would then be taken over a line that is not there. The
    /// first fixture written here had exactly that fault and the render is what
    /// showed it.
    private var known: String {
        "\(hostName) ssh-ed25519 "
            + "AAAAC3NzaC1lZDI1NTE5AAAAIAABAgMEBQYHCAkKCwwNDg8QERITFBUWFxgZGhscHR4f "
            + "\(comment)\n"
    }

    private func state() -> HostsState {
        HostsState(hostsText: "127.0.0.1\tlocalhost example.local\n",
                   sshText: config,
                   keys: [KeyRow(name: "id_ed25519_work_laptop", hasPublicHalf: true,
                                 described: KeyInventory.described(
                                    "256 \(fingerprint) \(comment) (ED25519)"),
                                 modified: Date(timeIntervalSince1970: 1_700_000_000),
                                 permission: .tooOpen(fix: 0o600),
                                 publicText: "ssh-ed25519 AAAA \(comment)\n", inAgent: false)],
                   keysReadable: true, directoryPermission: .ok, agent: .empty,
                   knownHostsText: known, home: "/Users/someone")
    }

    private func model() -> HostsViewModel {
        let model = HostsViewModel(vm: ModuleViewModel(transport: LocalTransport()))
        addTeardownBlock { await MainActor.run { model.stop() } }
        model.adopt(state())
        return model
    }

    // MARK: - The two readings a subject is judged on

    /// One drawing of one view at one pane width.
    private struct Drawing {
        let width: CGFloat
        /// Every layer's frame in the host's own coordinates, containers left
        /// in — `leadingEdge` and `furthest` filter them out themselves.
        let layers: [CGRect]
        /// The drawn text this module lets people select: the fingerprints and
        /// the addresses. Found by AppKit class, because a `Text` leaves no view
        /// of its own unless something makes one.
        let selectable: [CGRect]
    }

    /// The layer frames of a mounted view. Written here rather than borrowed:
    /// the walk `ModulePageRender` uses lives in `HelmAppTests`, which no module
    /// test target can see. (Worth moving to `HelmTestSupport`; said so in the
    /// report rather than done here, because that file is shared.)
    private func layers(of view: NSView) -> [CGRect] {
        guard let root = view.layer else { return [] }
        var out: [CGRect] = []
        func walk(_ layer: CALayer) {
            out.append(root.convert(layer.bounds, from: layer))
            for sub in layer.sublayers ?? [] { walk(sub) }
        }
        walk(root)
        return out
    }

    private func draw(_ view: some View, at width: CGFloat) -> Drawing {
        let render = MountedRender(view, width: width, height: 1200, appearance: .aqua)
        renders.append(render)
        render.settle(20)
        return Drawing(width: width,
                       layers: layers(of: render.host),
                       selectable: render.host
                           .everyView(named: "AppKitTextInteractionView")
                           .map { $0.convert($0.bounds, to: render.host) })
    }

    /// Everything drawn that is not a full-width container: the containers reach
    /// the pane's edge by construction and say nothing about content.
    private func content(_ drawing: Drawing) -> [CGRect] {
        drawing.layers.filter { $0.width > 0 && $0.width < drawing.width - 1 }
    }

    private func leadingEdge(_ drawing: Drawing) -> CGFloat {
        content(drawing).map(\.minX).min() ?? 0
    }

    private func furthest(_ drawing: Drawing) -> CGFloat {
        content(drawing).map(\.maxX).max() ?? 0
    }

    /// One line of the face these details are set in. Two lines of the smallest
    /// of them is 24 pt, so 20 tells one line from two with room to spare and
    /// does not depend on which font a release picks.
    private let oneLine: CGFloat = 20

    // MARK: - The rows

    /// Two selectable lines: the fingerprint, and the `chmod` the verdict
    /// carries. Counted rather than assumed — a row that had stopped drawing
    /// its fingerprint would satisfy every reading below over the figure alone.
    func testTheKeyRowFitsTheNarrowestPane() {
        judge("the key row", atLeast: 2) { KeysTable(hvm: $0) }
    }

    /// Two as well: the address, and the fingerprint of the trust drawn under
    /// the host.
    func testTheHostRowFitsTheNarrowestPane() {
        judge("the host row", atLeast: 2) { SSHHostsTable(hvm: $0, select: { _ in }) }
    }

    /// The `/etc/hosts` editor is off the screen and still in the tree, and its
    /// address column was one of the three widths the complaint named. It has no
    /// selectable text — it is two fields and a switch — so it is judged on the
    /// two readings that do not need any.
    func testTheHostsFileRowFitsTheNarrowestPane() {
        let narrow = draw(HostsTable(hvm: model()), at: narrowest)
        let wide = draw(HostsTable(hvm: model()), at: widest)
        assertTheRowKeepsItsGutter("the hosts file row", narrow: narrow, wide: wide)

        // Both fields grow with the pane. The address field was pinned at
        // 220 pt, which at this pane is half the row — so the check is that
        // neither field is the same width at 490 as at 744.
        let narrowFields = fieldWidths(HostsTable(hvm: model()), at: narrowest)
        let wideFields = fieldWidths(HostsTable(hvm: model()), at: widest)
        XCTAssertEqual(narrowFields.count, wideFields.count)
        XCTAssertGreaterThanOrEqual(narrowFields.count, 2,
                                    "no text fields were found in the hosts row, so the widths "
                                    + "below are read off nothing")
        for (narrowWidth, wideWidth) in zip(narrowFields, wideFields) {
            XCTAssertGreaterThan(wideWidth, narrowWidth + 1, """
                a field in the hosts row is \(narrowWidth) pt at a \(narrowest) pt pane and \
                \(wideWidth) pt at \(widest) — it is pinned to a number, so at the narrowest \
                window it takes a share of the row that nothing gave it back
                """)
        }
    }

    /// In the order the tree draws them, **never sorted.** Sorting was the
    /// first spelling and it made this check unable to fail: with the address
    /// field pinned back at 220 pt the two panes read `[163, 220]` and
    /// `[220, 417]`, and sorted lists pair 163 with 220 and 220 with 417 — both
    /// «grew», with the pinned field's own reading handed to its neighbour.
    /// Proved by putting the 220 back, which is how the fault was found.
    private func fieldWidths(_ view: some View, at width: CGFloat) -> [CGFloat] {
        let render = MountedRender(view, width: width, height: 1200, appearance: .aqua)
        renders.append(render)
        render.settle(20)
        return render.host.everyView(named: "AppKitTextField").map(\.bounds.width)
    }

    /// The four readings, on one subject.
    private func judge(_ what: String, atLeast lines: Int,
                       _ view: (HostsViewModel) -> some View) {
        let narrow = draw(view(model()), at: narrowest)
        let wide = draw(view(model()), at: widest)

        XCTAssertGreaterThanOrEqual(narrow.selectable.count, lines, """
            \(what) drew \(narrow.selectable.count) selectable lines at \(narrowest) pt, not the \
            \(lines) it has. Either the row has stopped drawing one of them, or \
            `AppKitTextInteractionView` is no longer the class a selectable `Text` produces — \
            and every reading below would then be taken off a shorter list than it thinks.
            """)
        XCTAssertEqual(narrow.selectable.count, wide.selectable.count,
                       "\(what) draws a different number of detail lines at the two panes")

        for line in narrow.selectable {
            XCTAssertLessThanOrEqual(line.height, oneLine, """
                a detail line of \(what) is \(line.height) pt tall at the \(narrowest) pt pane, \
                which is more than the one line it has to be: it has wrapped rather than \
                truncated. A fingerprint is 47 characters and this pane is what the window's \
                own minimum leaves — so the line has to lose its middle, not its place.
                """)
        }

        // **The longest line, not every line.** A short figure — `chmod 600` —
        // is its own width at any pane and always will be; what has to grow is
        // the line the pane is actually pressing on, which is the fingerprint.
        let pressed = narrow.selectable.map(\.width).max() ?? 0
        let given = wide.selectable.map(\.width).max() ?? 0
        XCTAssertGreaterThan(given, pressed + 1, """
            the longest detail line of \(what) is \(pressed) pt wide at \(narrowest) pt and \
            \(given) pt at \(widest) — the same width at two panes is what «imposes a width» \
            means once it is measured rather than read, and it is the line holding the \
            fingerprint that pays for it.
            """)

        assertTheRowKeepsItsGutter(what, narrow: narrow, wide: wide)
    }

    /// The two readings that need no text: the row starts where every other row
    /// on the page starts, and ends before the gutter.
    private func assertTheRowKeepsItsGutter(_ what: String, narrow: Drawing, wide: Drawing) {
        XCTAssertGreaterThanOrEqual(content(narrow).count, 5,
                                    "\(what) drew \(content(narrow).count) layers at "
                                    + "\(narrowest) pt — nothing rendered, and every edge below "
                                    + "is then whatever an empty view defaults to")

        XCTAssertEqual(leadingEdge(narrow), leadingEdge(wide), accuracy: 1, """
            \(what) begins at x = \(leadingEdge(narrow)) at the \(narrowest) pt pane and at \
            \(leadingEdge(wide)) at \(widest). A row whose content cannot fit is not drawn past \
            the right edge — SwiftUI centres it — so the row walks in from the gutter, which is \
            what a width in points looks like from the outside.
            """)
        XCTAssertLessThanOrEqual(furthest(narrow), narrowest - HelmLayout.formInset + 1, """
            \(what) draws to x = \(furthest(narrow)) at the \(narrowest) pt pane, past its own \
            \(HelmLayout.formInset) pt inset at \(narrowest - HelmLayout.formInset).
            """)
    }
}
