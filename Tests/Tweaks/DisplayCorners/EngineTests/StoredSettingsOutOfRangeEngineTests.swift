import CoreGraphics
import XCTest
import HelmRuntime
import HelmTestSupport
@testable import Tweak_DisplayCorners_Engine

/// **What a file hands Helm as a setting is not always what the engine wrote.**
///
/// A number can be NaN, infinite or far out of range, and a value can be of another type altogether: a hand
/// edit, an older build, a damaged plist. The radius and scale tests plant such a value under the radius or the
/// remembered scale, activate over fakes, and assert that nothing trapped and that the radius and the scale the
/// engine says, and the radius a step writes, are numbers inside their bounds. The scale test also plants it with
/// the built-in display attached and with only an external one. The switch test asserts the switches take their
/// defaults; the missing-radius test plants nothing and asserts the default; one test plants what the display
/// reports, and one the store of a real `UserDefaults`.
/// A boolean is a number to a property list, so `true` under a numeric key is read as 1 and bounded.
@MainActor
final class StoredSettingsOutOfRangeEngineTests: XCTestCase {

    private let numbers: [Any] = [Double.nan, Double.infinity, -Double.infinity, 1e300, -5.0, 0.0]
    private let notNumbers: [Any] = ["text", [1.0, 2.0], true]

    private func radiusBounded(_ rig: Rig, _ planted: Any) {
        XCTAssertTrue(RadiusMath.bounds.contains(rig.engine.state.radiusPixels), "\(planted): radius \(rig.engine.state.radiusPixels)")
        rig.engine.stepRadius(direction: 1)
        let stored = rig.store.object("radiusPixels") as? Double
        XCTAssertNotNil(stored, "\(planted): a step wrote no number")
        XCTAssertTrue(RadiusMath.bounds.contains(stored ?? .nan), "\(planted): stored \(stored ?? .nan)")
    }

    func testARadiusOutOfRangeOrOfAnotherTypeIsBoundedAtTheBuiltInDisplay() {
        for planted in numbers + notNumbers {
            let rig = Rig()
            rig.store.set(planted, for: "radiusPixels")
            rig.engine.activate()
            XCTAssertFalse(rig.masks.shows.isEmpty, "\(planted): the subject did not happen: no mask was asked for")
            radiusBounded(rig, planted)
        }
    }

    func testARememberedScaleOutOfRangeNeverStandsAsItWasStored() {
        for planted in numbers + notNumbers {
            for lidClosed in [false, true] {
                let rig = Rig(displays: lidClosed ? [Rig.external] : [Rig.builtIn])
                rig.store.set(planted, for: "builtInScale")
                rig.store.set(true, for: "external")
                rig.engine.activate()
                let state = rig.engine.state
                XCTAssertFalse(rig.masks.shows.isEmpty, "\(planted): the subject did not happen: no mask was asked for")
                XCTAssertTrue(state.referenceScale.isFinite && state.referenceScale > 0, "\(planted): scale \(state.referenceScale)")
                XCTAssertTrue(StoredCornerSettings.scaleBounds.contains(Double(state.referenceScale)),
                              "\(planted): scale \(state.referenceScale) outside what is remembered")
                if let number = planted as? Double { XCTAssertNotEqual(Double(state.referenceScale), number, "\(planted) was taken as it stood") }
                radiusBounded(rig, planted)
                if !lidClosed {
                    XCTAssertEqual(rig.store.object("builtInScale") as? Double, 2, "\(planted): the live scale was not remembered over it")
                }
            }
        }
    }

    func testASwitchOfAnotherTypeTakesItsDefault() {
        for planted in ["text", [1.0], 5.5] as [Any] {
            let rig = Rig()
            rig.store.set(planted, for: "builtIn")
            rig.store.set(planted, for: "external")
            rig.engine.activate()
            XCTAssertNotEqual(rig.engine.state, CornerState(), "\(planted): the subject did not happen")
            XCTAssertTrue(rig.engine.state.builtIn, "\(planted): the built-in switch did not take its default, on")
            XCTAssertFalse(rig.engine.state.external, "\(planted): the external switch did not take its default, off")
            XCTAssertFalse(rig.masks.shows.isEmpty)
        }
    }

    func testAMissingRadiusIsFourteenPointsAtTheReferenceScale() {
        let rig = Rig()
        rig.engine.activate()
        XCTAssertEqual(rig.engine.state.referenceScale, 2, "the subject did not happen: no reference scale")
        XCTAssertEqual(rig.engine.state.radiusPixels, 28)
    }

    /// The family of the stored scale: the same number arriving from the display, to be remembered.
    func testAScaleTheDisplayReportsOutOfRangeIsNotRememberedAsItStands() {
        for reported in [Double.nan, .infinity, -.infinity, 1e300, -5, 0] {
            let sane = Rig.builtIn
            let odd = DisplayDescriptor(id: sane.id, frame: sane.frame, quartzBounds: sane.quartzBounds, backingScale: sane.backingScale,
                                        pixelsPerPoint: CGFloat(reported), isBuiltIn: true, isMirrored: false, maxFPS: sane.maxFPS)
            let rig = Rig(displays: [odd])
            rig.engine.activate()
            XCTAssertGreaterThan(rig.displays.reads, 0, "\(reported): the displays were not read")
            if let stored = rig.store.object("builtInScale") as? Double {
                XCTAssertTrue(StoredCornerSettings.scaleBounds.contains(stored), "\(reported): remembered \(stored)")
            }
            XCTAssertTrue(RadiusMath.bounds.contains(rig.engine.state.radiusPixels), "\(reported): radius \(rig.engine.state.radiusPixels)")
            XCTAssertTrue(rig.engine.state.referenceScale.isFinite, "\(reported): reference \(rig.engine.state.referenceScale)")
        }
        // A control: the same display with a sane scale is remembered, so "nothing stored" above is not the engine idle.
        let rig = Rig()
        rig.engine.activate()
        XCTAssertEqual(rig.store.object("builtInScale") as? Double, 2)
    }

    /// The store the app really hands over: `UserDefaults` bridges every number and boolean to one `NSNumber`.
    func testAValueThroughARealUserDefaultsIsReadAsAPropertyListHoldsIt() throws {
        // A suite named by an absolute path keeps its file there, in a scratch directory that is swept, and not under
        // ~/Library/Preferences: cfprefsd wrote a named suite's (empty) plist there late, after any teardown of ours.
        let folder = scratchDirectory("display-corners-defaults")
        let suite = folder.appendingPathComponent("suite").path
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let rig = Rig(store: Rig.store(over: defaults))
        rig.store.set(true, for: "radiusPixels")
        rig.store.set(1, for: "external")
        rig.store.set("text", for: "builtIn")
        rig.engine.activate()
        XCTAssertFalse(rig.masks.shows.isEmpty, "the subject did not happen: no mask was asked for")
        XCTAssertTrue(rig.engine.state.external, "a stored 1 is a boolean to a property list")
        XCTAssertTrue(rig.engine.state.builtIn, "a string under a switch takes the default")
        XCTAssertEqual(rig.engine.state.radiusPixels, 1, "a stored boolean is the number 1")
        radiusBounded(rig, "true")
    }
}
