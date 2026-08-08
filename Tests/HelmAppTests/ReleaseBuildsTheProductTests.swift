import XCTest

/// The release build builds the app, not the package.
///
/// `HelmTestSupport` is a plain target — it has to be, because a test target
/// cannot be depended on — and it imports XCTest. XCTest is not in the
/// toolchain: it resolves out of the Xcode-only framework path. So
/// `swift build -c release`, which builds every target in the manifest, made a
/// full Xcode install a requirement of packaging Helm where a Swift toolchain
/// had been enough, and left `HelmTestSupport.swiftmodule` in Release beside
/// `HelmApp`. It never reached the bundle — `package-app.sh` copies one binary
/// and the resource bundles — so nothing about the shipped app was wrong, and
/// nothing about the shipped app would ever have said so.
///
/// **Naming the product is the half that works.** Measured on a cleaned
/// `Release`: a bare build is 466 steps and writes the harness; `--product
/// HelmApp` is 187 and does not. Declaring `products:` does *not* prune a bare
/// build — it is here so the flag names something the manifest says exists,
/// rather than the product SwiftPM synthesises for an executable target, which
/// a rename would take away without a word.
final class ReleaseBuildsTheProductTests: XCTestCase {

    private func read(_ path: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // HelmAppTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo
            .appendingPathComponent(path)
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// Assert the hazard is real before asserting it is fenced off. A test that
    /// says «the release build excludes the target that imports XCTest» passes
    /// on its own when nothing imports XCTest any more — and then the fence
    /// stands guarding nothing, with the reason for it lost.
    func testTheHarnessReallyDoesImportXCTest() throws {
        let sources = ["Tests/Support/ScratchDirectory.swift", "Tests/Support/TrashScratch.swift"]
        let importers = try sources.filter { try read($0).contains("import XCTest") }
        XCTAssertFalse(importers.isEmpty,
                       "no file in HelmTestSupport imports XCTest any more, so the reason "
                       + "the release build names a product needs deciding again "
                       + "rather than inheriting")
    }

    /// The half that prunes the graph.
    func testThePackagingScriptBuildsTheProduct() throws {
        let script = try read("Scripts/package-app.sh")
        let builds = script.components(separatedBy: "\n")
            .filter { $0.hasPrefix("swift build") }
        XCTAssertEqual(builds.count, 1, "expected one release build line, found \(builds)")
        XCTAssertTrue(builds.first?.contains("--product HelmApp") == true,
                      "the packaging script builds the whole package, which builds "
                      + "HelmTestSupport and its `import XCTest`: \(builds)")
    }

    /// The half that makes the flag name something declared.
    func testTheManifestDeclaresTheAppAsItsOnlyProduct() throws {
        let manifest = try read("Package.swift")
        XCTAssertTrue(manifest.contains(#".executable(name: "HelmApp", targets: ["HelmApp"])"#),
                      "the manifest declares no HelmApp product, so `--product HelmApp` "
                      + "resolves to a synthesised one and a renamed target breaks "
                      + "packaging with nothing to catch it")
        XCTAssertFalse(manifest.contains(#"targets: ["HelmTestSupport"]"#),
                       "the harness is in a product")
    }
}
