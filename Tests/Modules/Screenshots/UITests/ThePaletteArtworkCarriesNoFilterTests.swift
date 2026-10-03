import AppKit
import HelmTestSupport
import XCTest

/// **The palette's objects are vector artwork macOS can actually draw.** macOS
/// drops SVG filters without a word, so a filter left in a file is a shadow
/// nobody sees and a dead weight; text left in a file is a thickness label
/// that must not be on the object. The catalog is
/// `Sources/Modules/Screenshots/UI/PaletteObjects.xcassets`, one image set per
/// object, theme and layer, named `<object>-<theme>-<layer>` — `pen-light-body`,
/// `pen-light-tip` (the tip's silhouette, a template), `pen-light-shade` — for
/// the objects pen, marker, pencil and the themes light, dark.
final class ThePaletteArtworkCarriesNoFilterTests: XCTestCase {

    static let catalog = "Sources/Modules/Screenshots/UI/PaletteObjects.xcassets"
    static let objects = ["pen", "marker", "pencil"]
    static let themes = ["light", "dark"]
    static let layers = ["body", "tip", "shade"]

    struct ImageSet { let name: String; let contents: [String: Any]; let svgs: [URL] }

    static func imageSets() throws -> [ImageSet] {
        let root = RepoSource.root.appendingPathComponent(catalog)
        let entries = (try? FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: nil)) ?? []
        return try entries.filter { $0.pathExtension == "imageset" }.sorted { $0.path < $1.path }.map { dir in
            let data = try Data(contentsOf: dir.appendingPathComponent("Contents.json"))
            let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
            let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            return ImageSet(name: dir.deletingPathExtension().lastPathComponent, contents: json,
                            svgs: files.filter { $0.pathExtension == "svg" })
        }
    }

    /// Positive control: the catalog is found and holds the three objects in
    /// both themes, every layer — so the scans below read something.
    func testTheCatalogHoldsEveryObjectInBothThemes() throws {
        let sets = try Self.imageSets()
        let names = Set(sets.map(\.name))
        for object in Self.objects { for theme in Self.themes { for layer in Self.layers {
            XCTAssertTrue(names.contains("\(object)-\(theme)-\(layer)"), "\(object)-\(theme)-\(layer) missing")
        } } }
        XCTAssertGreaterThanOrEqual(sets.filter { $0.name.hasSuffix("-body") }.count, 6,
                                    "at least 3 objects x 2 themes of bodies")
        for set in sets { XCTAssertEqual(set.svgs.count, 1, "\(set.name) holds exactly one SVG") }
    }

    func testNoSVGCarriesAFilterOrText() throws {
        let sets = try Self.imageSets()
        XCTAssertGreaterThanOrEqual(sets.count, 18, "the catalog was not found, nothing was scanned")
        for set in sets { for svg in set.svgs {
            let text = try String(contentsOf: svg, encoding: .utf8)
            XCTAssertFalse(text.contains("<filter"), "\(set.name): <filter")
            XCTAssertFalse(text.contains("filter="), "\(set.name): filter=")
            XCTAssertFalse(text.contains("<text"), "\(set.name): <text")
        } }
    }

    func testEveryImageSetKeepsItsVectorAndTheTipIsATemplate() throws {
        let sets = try Self.imageSets()
        XCTAssertGreaterThanOrEqual(sets.count, 18, "the catalog was not found, nothing was scanned")
        for set in sets {
            let props = set.contents["properties"] as? [String: Any]
            XCTAssertEqual(props?["preserves-vector-representation"] as? Bool, true,
                           "\(set.name): preserves-vector-representation")
            let intent = props?["template-rendering-intent"] as? String
            if set.name.hasSuffix("-tip") {
                XCTAssertEqual(intent, "template", "\(set.name): the tip silhouette is a template")
            } else {
                XCTAssertNotEqual(intent, "template", "\(set.name): body and shade are not templates")
            }
        }
    }
}
