import AppKit
import HelmTestSupport
import XCTest
@testable import Module_Screenshots_UI

/// **The compiled catalog gives the palette its objects, with an SVG
/// representation, and the tip is the template layer.** Reads the Screenshots
/// UI target's own `Bundle.module`, the bundle `PaletteObject` draws from, through `@testable`.
final class ThePaletteObjectsLoadFromTheBundleTests: XCTestCase {

    private func resourceBundle() -> Bundle { Bundle.module }

    private func isSVG(_ image: NSImage) -> Bool {
        image.representations.contains { String(describing: type(of: $0)).contains("SVG") }
    }

    func testEveryNamedImageIsThereAndVector() throws {
        let bundle = resourceBundle()
        for object in ThePaletteArtworkCarriesNoFilterTests.objects {
            for theme in ThePaletteArtworkCarriesNoFilterTests.themes {
                for layer in ThePaletteArtworkCarriesNoFilterTests.layers {
                    let name = "\(object)-\(theme)-\(layer)"
                    let image = try XCTUnwrap(bundle.image(forResource: NSImage.Name(name)), "\(name) not in the bundle")
                    XCTAssertTrue(isSVG(image), "\(name) has no SVG representation: \(image.representations)")
                }
            }
        }
    }

    func testTheTipIsATemplateAndTheBodyIsNot() throws {
        let bundle = resourceBundle()
        for object in ThePaletteArtworkCarriesNoFilterTests.objects {
            for theme in ThePaletteArtworkCarriesNoFilterTests.themes {
                let tip = try XCTUnwrap(bundle.image(forResource: NSImage.Name("\(object)-\(theme)-tip")), "\(object) \(theme) tip")
                let body = try XCTUnwrap(bundle.image(forResource: NSImage.Name("\(object)-\(theme)-body")), "\(object) \(theme) body")
                XCTAssertTrue(tip.isTemplate, "\(object) \(theme) tip must be a template")
                XCTAssertFalse(body.isTemplate, "\(object) \(theme) body must not be a template")
            }
        }
    }
}
