import AppKit
import HelmContract
import HelmTestSupport
import SwiftUI
import XCTest
import Module_Uninstaller_Engine
@testable import HelmApp
@testable import HelmUI
@testable import Module_Hosts_UI
@testable import Module_Uninstaller_UI

/// **The owner's fifth report on this toolbar (2026-09-25): the `+` and the
/// mode toggle in Hosts sit too close to the window's trailing edge.**
///
/// **Isolated first against a bare `NSToolbar`**, one 36×36 custom view, all
/// else equal (`BareToolbarEdgeIsolationTests` below): `isBordered = false`
/// left the view's own trailing edge 4.0 pt from the window's at 1060 pt;
/// `isBordered = true` left it 8.0 pt. The same 4.0 pt shortfall showed on
/// the real bar: Hosts' `helm.actions`, the last item on that page, measured
/// 4.0 pt from the window's trailing edge at 1060 pt, where Uninstaller's
/// `helm.search` — AppKit's own `NSSearchToolbarItem`, resting wide at the
/// same width — measured 8.0 pt.
///
/// `HelmToolbarActionsCapsule` stays `isBordered = false` regardless — a
/// bordered item wraps it in a second glass (`makeActionsItem`'s own header)
/// — so the fix is a `trailingInset` on the capsule's own content, spent only
/// where nothing follows it in the bar (`content.search == nil`): Hosts and
/// Leftovers. Homebrew and Uninstaller, where search follows the capsule,
/// read `trailingInset: 0` and must be unaffected —
/// `testTheCapsuleAheadOfSearchIsUnaffected` is what proves that.
///
/// **The measurement never assumes the fix ran.** `insetApplied` below is
/// read back off the *live* hosted view's own width against its declared
/// button count, not derived from `HelmToolbarActionsCapsule.edgeMargin`
/// itself — a formula that bakes the fix's own constant into its
/// expectation cannot go red on the code the fix replaces, which is exactly
/// the kind of check `CLAUDE.md` calls litter.
@MainActor
final class TheLastItemsGlassSitsAsFarFromTheEdgeTests: XCTestCase {

    private final class Mute: EngineTransport, @unchecked Sendable {
        var events: AsyncStream<EngineEvent> { AsyncStream { _ in } }
        func send(_ command: EngineCommand) async throws -> Data {
            guard UninstallerCommand(rawValue: command.name) == .listApps else { return Data() }
            return (try? JSONEncoder().encode([InstalledApp]())) ?? Data()
        }
    }

    private var fixture: LivePageToolbarFixture?

    override func tearDown() {
        fixture?.drop()
        fixture = nil
        super.tearDown()
    }

    private struct ActionsMeasurement {
        /// The hosted view's own trailing edge, in window coordinates — the
        /// padded content box AppKit lays the item out by, not necessarily
        /// where the visible glass ends.
        let boxTrailingX: CGFloat
        /// The hosted view's own width, minus what its declared buttons
        /// actually need (`HelmToolbarActionsCapsule.side` each) — zero on
        /// unfixed code, and on any page where the capsule is not the bar's
        /// last item.
        let insetApplied: CGFloat
    }

    /// Reads the actions item's own hosted view and its live model — never a
    /// number this fix itself introduced — so a build that dropped the fix
    /// entirely (`insetApplied` staying `0`) is exactly what turns this red.
    private func measureActions(_ toolbar: NSToolbar) -> ActionsMeasurement? {
        guard let item = toolbar.items.first(where: { $0.itemIdentifier.rawValue == "helm.actions" }),
              let hosting = item.view as? NSHostingView<HelmToolbarActionsCapsule>
        else { return nil }
        let declaredWidth = CGFloat(hosting.rootView.model.declared.count) * HelmToolbarActionsCapsule.side
        let boxTrailingX = hosting.convert(NSPoint(x: hosting.bounds.width, y: 0), to: nil).x
        return ActionsMeasurement(boxTrailingX: boxTrailingX, insetApplied: hosting.bounds.width - declaredWidth)
    }

    /// **Hosts ends its bar on `helm.actions` — no search follows it —** at
    /// every width the switcher may fold or not fold at (`TheGapBeforeSearch-
    /// IsFixedNotFlexibleTests`' own three widths). `boxMargin` (window's
    /// trailing edge to the padded box) is AppKit's own outer margin, read
    /// fresh every time rather than assumed constant; `glassGap` adds back
    /// `insetApplied`, which is where the fix actually lives.
    func testHostsCapsuleGapMatchesAppKitsOwnAtEveryWidth() async throws {
        for width: CGFloat in [860, 1060, 1400] {
            let vm = ModuleViewModel(transport: Mute())
            let hosts = LivePageToolbarFixture(HostsSettingsPage(vm: vm),
                                               selection: .module(HostsDescriptor.id.rawValue),
                                               width: width, height: 700)
            hosts.settle(30)
            fixture = hosts
            let toolbar = try XCTUnwrap(hosts.mount.window?.toolbar, "\(width) pt: no toolbar")
            let measured = try XCTUnwrap(measureActions(toolbar),
                                         "\(width) pt: no hosted view for helm.actions")
            let boxMargin = width - measured.boxTrailingX
            let glassGap = boxMargin + measured.insetApplied
            XCTAssertEqual(glassGap, 8, accuracy: 0.5, """
                \(width) pt: Hosts' actions capsule sits \(glassGap) pt from the window's \
                trailing edge (box margin \(boxMargin) + applied inset \(measured.insetApplied)) — \
                AppKit's own last item (a bordered button, a resting search field) sits 8 pt from \
                it; the `+` and the mode toggle must match
                """)
            hosts.drop()
        }
        fixture = nil
    }

    /// **Uninstaller ends its bar on `helm.search` — the capsule is not
    /// last, so `trailingInset` must read 0 and the capsule must sit exactly
    /// where it always has.**
    func testTheCapsuleAheadOfSearchIsUnaffected() async throws {
        let vm = ModuleViewModel(transport: Mute())
        let fx = LivePageToolbarFixture(UninstallerSettingsPage(vm: vm),
                                        selection: .module(UninstallerDescriptor.id.rawValue),
                                        width: 1060, height: 700)
        fx.settle(30)
        fixture = fx
        let toolbar = try XCTUnwrap(fx.mount.window?.toolbar, "no toolbar")
        let measured = try XCTUnwrap(measureActions(toolbar), "no hosted view for helm.actions")
        XCTAssertEqual(measured.insetApplied, 0, accuracy: 0.5, """
            Uninstaller's actions capsule carries a trailing inset of \(measured.insetApplied) pt \
            — search follows it in the bar, so `trailingInset` must read 0 and this capsule's own \
            geometry must not move
            """)
        let searchItem = toolbar.items.first { $0.itemIdentifier.rawValue == "helm.search" }
            as? NSSearchToolbarItem
        let field = try XCTUnwrap(searchItem?.searchField, "no search field")
        let searchLeading = field.convert(NSPoint.zero, to: nil).x
        XCTAssertGreaterThan(searchLeading, measured.boxTrailingX, """
            helm.search's own leading edge (\(searchLeading)) is not ahead of helm.actions' \
            trailing edge (\(measured.boxTrailingX)) — the two have swapped order or overlapped
            """)
    }
}

/// **The bare-toolbar isolation this file's own header cites.** Kept as a
/// standing fixture rather than a one-off scratch probe: the next person
/// doubting whether `isBordered` alone moves AppKit's own outer margin can
/// re-run this rather than re-deriving it.
@MainActor
private final class BareToolbarEdgeProbeDelegate: NSObject, NSToolbarDelegate {
    static let itemID = NSToolbarItem.Identifier("probe.item")
    let bordered: Bool
    init(bordered: Bool) { self.bordered = bordered }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier,
                willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.view = NSView(frame: NSRect(x: 0, y: 0, width: 36, height: 36))
        item.isBordered = bordered
        return item
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { [Self.itemID] }
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }
}

@MainActor
final class BareToolbarEdgeIsolationTests: XCTestCase {

    private func margin(isBordered: Bool, width: CGFloat = 1060) -> CGFloat? {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: 200),
                              styleMask: [.titled], backing: .buffered, defer: false)
        let delegate = BareToolbarEdgeProbeDelegate(bordered: isBordered)
        let toolbar = NSToolbar(identifier: NSToolbar.Identifier("probe.\(isBordered)"))
        toolbar.delegate = delegate
        toolbar.displayMode = .iconOnly
        window.toolbar = toolbar
        window.layoutIfNeeded()
        guard let view = toolbar.items.first?.view else { return nil }
        let trailing = view.convert(NSPoint(x: view.bounds.width, y: 0), to: nil).x
        withExtendedLifetime(delegate) {}
        return width - trailing
    }

    /// **The measurement this whole fix rests on.** `4` and `8`: not "some
    /// difference" — the exact two numbers `HelmToolbarActionsCapsule
    /// .edgeMargin`'s own header states, from this same probe.
    func testUnborderedSitsFourPointsClearOfWhereBorderedDoes() throws {
        let plain = try XCTUnwrap(margin(isBordered: false), "no plain item view")
        let bordered = try XCTUnwrap(margin(isBordered: true), "no bordered item view")
        XCTAssertEqual(plain, 4, accuracy: 0.5, "isBordered = false margin drifted off the measured 4 pt")
        XCTAssertEqual(bordered, 8, accuracy: 0.5, "isBordered = true margin drifted off the measured 8 pt")
    }
}
