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
/// the objects pen, marker, pencil and the themes light, dark. The eraser and the ruler have a body and no tip: no
/// ink reaches them, and a tip layer there would be a layer nothing draws.
final class ThePaletteArtworkCarriesNoFilterTests: XCTestCase {

    static let catalog = "Sources/Modules/Screenshots/UI/PaletteObjects.xcassets"
    /// The objects whose tip takes the ink: three layers each.
    static let tipped = ["pen", "marker", "pencil"]
    /// The objects with a body and nothing else.
    static let bodyOnly = ["eraser", "ruler"]
    static var objects: [String] { tipped + bodyOnly }
    static let themes = ["light", "dark"]
    static let layers = ["body", "tip", "shade"]

    /// The layers an object's artwork has.
    static func layers(of object: String) -> [String] { tipped.contains(object) ? layers : ["body"] }

    /// Every image set the catalog is to hold.
    static var expectedNames: Set<String> {
        Set(objects.flatMap { object in themes.flatMap { theme in layers(of: object).map { "\(object)-\(theme)-\($0)" } } })
    }

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

    /// Positive control: the catalog is found and holds the five objects in
    /// both themes, every layer each has and no other — so the scans below read something.
    func testTheCatalogHoldsEveryObjectInBothThemes() throws {
        let sets = try Self.imageSets()
        let names = Set(sets.map(\.name))
        for object in Self.objects { for theme in Self.themes { for layer in Self.layers(of: object) {
            XCTAssertTrue(names.contains("\(object)-\(theme)-\(layer)"), "\(object)-\(theme)-\(layer) missing")
        } } }
        let expected = Self.expectedNames
        XCTAssertEqual(names, expected, "the catalog holds a layer no object of the list has, or lacks one")
        XCTAssertEqual(sets.filter { $0.name.hasSuffix("-body") }.count, Self.objects.count * Self.themes.count,
                       "one body for each object in each theme")
        for set in sets { XCTAssertEqual(set.svgs.count, 1, "\(set.name) holds exactly one SVG") }
    }

    func testNoSVGCarriesAFilterOrText() throws {
        let sets = try Self.imageSets()
        XCTAssertEqual(sets.count, Self.expectedNames.count, "the catalog was not found, nothing was scanned")
        for set in sets { for svg in set.svgs {
            let text = try String(contentsOf: svg, encoding: .utf8)
            XCTAssertFalse(text.contains("<filter"), "\(set.name): <filter")
            XCTAssertFalse(text.contains("filter="), "\(set.name): filter=")
            XCTAssertFalse(text.contains("<text"), "\(set.name): <text")
        } }
    }

    func testEveryImageSetKeepsItsVectorAndTheTipIsATemplate() throws {
        let sets = try Self.imageSets()
        XCTAssertEqual(sets.count, Self.expectedNames.count, "the catalog was not found, nothing was scanned")
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
