import XCTest
import HelmContract
import HelmUI
@testable import Module_Hosts_UI

@MainActor
final class HostsDescriptorTests: XCTestCase {

    /// The descriptor reads the engine's constant rather than repeating it.
    /// Two spellings of one id do not fail — they read a different store, and
    /// the person's settings are simply gone.
    func testTheDescriptorTakesItsIDFromTheEngine() {
        XCTAssertEqual(HostsDescriptor.id.rawValue, "hosts")
    }

    /// The sidebar column is fixed and truncates mid-word, so a compound name
    /// carries a short form. This fails if someone drops it later.
    func testTheSidebarNameIsShorterThanTheFullName() {
        let m = HostsDescriptor.metadata
        XCTAssertLessThan(m.shortName.count, m.name.count)
    }

    /// **The panel lists this module, it does not draw it.**
    ///
    /// Hosts had a tile of three counts and nothing to press, which is the one
    /// shape `MenuBarContribution.isUtility` exists to name: the panel is for
    /// what can be acted on from the menu bar, and everything this module does
    /// — editing the file, fixing a key's mode, reading a fingerprint — is a
    /// page. Asserted on the contribution rather than on the drawer, because
    /// the drawer is `HelmPanel`'s reading of this value and this is the value.
    func testTheModuleIsAUtilityAndOffersNoTile() {
        let wire = HostsUIWire.make(file: "127.0.0.1\tlocalhost\n", privileged: .declined)
        guard let contribution = HostsDescriptor().menuBar(wire.vm) else {
            return XCTFail("the module contributes nothing to the panel at all, "
                           + "which hides it from the drawer as well as from the grid")
        }
        XCTAssertTrue(contribution.isUtility,
                      "Hosts is drawn as a widget again; the panel's grid is for "
                      + "modules with something to press")
        XCTAssertNil(contribution.panelTile,
                     "a utility carrying a tile is two answers to one question — "
                     + "HelmPanel reads isUtility and the tile is then never drawn")
    }

    /// And the widget sizes follow from it: `panelWidget` defaults to the
    /// tile, so a module with no tile offers no size. Read through the
    /// descriptor rather than restated, so this fails if a size is added
    /// without a decision.
    func testTheModuleOffersNoWidgetAtAnySize() {
        let wire = HostsUIWire.make(file: "127.0.0.1\tlocalhost\n", privileged: .declined)
        let descriptor = HostsDescriptor()
        XCTAssertTrue(descriptor.panelWidgetSizes(wire.vm).isEmpty,
                      "the module offers a widget size, so the composer lists it in the grid")
        for size in PanelWidgetSize.allCases {
            XCTAssertNil(descriptor.panelWidget(size, wire.vm),
                         "\(size) draws something")
        }
    }
}
