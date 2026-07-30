import XCTest
@testable import Module_Uninstaller_Engine

/// Reading an app bundle that is sitting in the Trash.
///
/// This is where the offer starts, so everything downstream inherits whatever it
/// gets wrong: the bundle id decides which leftovers are claimed, and the name is
/// what the window puts above them. The plist read itself stays outside — this is
/// the fallback chain and the refusals, which is the part with judgement in it.
final class TrashedAppTests: XCTestCase {

    private let path = "/Users/ann/.Trash/Some App.app"

    // MARK: - The name

    /// `CFBundleDisplayName` is what Finder shows and what the person recognises,
    /// so it wins where an app ships both.
    func testTheDisplayNameWins() {
        let app = TrashedAppIdentity.of(path: path, info: [
            "CFBundleIdentifier": "com.example.some",
            "CFBundleDisplayName": "Some App Pro",
            "CFBundleName": "SomeApp",
        ])
        XCTAssertEqual(app?.name, "Some App Pro")
    }

    func testCFBundleNameIsTheFallback() {
        let app = TrashedAppIdentity.of(path: path, info: [
            "CFBundleIdentifier": "com.example.some",
            "CFBundleName": "SomeApp",
        ])
        XCTAssertEqual(app?.name, "SomeApp")
    }

    /// A bundle with an id and no name at all is still worth offering — the file
    /// name is what the person dragged, so it is the name they will recognise.
    func testTheFileNameIsTheLastResort() {
        let app = TrashedAppIdentity.of(path: path, info: ["CFBundleIdentifier": "com.example.some"])
        XCTAssertEqual(app?.name, "Some App")
    }

    // MARK: - The refusals

    /// No id, no offer. Every leftover this feature proposes to delete is derived
    /// from the bundle id, so without one there is nothing to derive and nothing
    /// that could be justified.
    func testWithoutABundleIDThereIsNothingToOffer() {
        XCTAssertNil(TrashedAppIdentity.of(path: path, info: ["CFBundleName": "SomeApp"]))
        XCTAssertNil(TrashedAppIdentity.of(path: path, info: [:]))
    }

    /// An unreadable or absent `Info.plist` — a broken bundle, or a folder someone
    /// named `.app`. Not an error to report, just nothing to offer.
    func testAnUnreadableBundleIsSkipped() {
        XCTAssertNil(TrashedAppIdentity.of(path: path, info: nil))
    }

    /// An id that is present but empty is the same as absent, and it would
    /// otherwise produce globs matching everything.
    func testAnEmptyBundleIDIsNoBundleID() {
        XCTAssertNil(TrashedAppIdentity.of(path: path, info: ["CFBundleIdentifier": ""]))
        XCTAssertNil(TrashedAppIdentity.of(path: path, info: ["CFBundleIdentifier": "   "]))
    }

    /// A name that is present but blank falls through to the next candidate rather
    /// than putting an empty heading above a list of files.
    func testABlankNameFallsThrough() {
        let app = TrashedAppIdentity.of(path: path, info: [
            "CFBundleIdentifier": "com.example.some",
            "CFBundleDisplayName": "  ",
            "CFBundleName": "SomeApp",
        ])
        XCTAssertEqual(app?.name, "SomeApp")
    }

    /// The values are read from a plist, which is a file anyone can write. A
    /// number where a string belongs must not become the name `1234` or crash the
    /// read — it is simply not a name.
    func testAValueOfTheWrongTypeIsNotAName() {
        let app = TrashedAppIdentity.of(path: path, info: [
            "CFBundleIdentifier": "com.example.some",
            "CFBundleDisplayName": 1234,
        ])
        XCTAssertEqual(app?.name, "Some App", "a non-string name was used")
    }

    func testAnIdentifierOfTheWrongTypeIsNoIdentifier() {
        XCTAssertNil(TrashedAppIdentity.of(path: path, info: ["CFBundleIdentifier": 42]))
    }

    // MARK: - What comes out

    func testThePathIsKeptAsGiven() {
        let app = TrashedAppIdentity.of(path: path, info: ["CFBundleIdentifier": "com.example.some"])
        XCTAssertEqual(app?.path, path)
        XCTAssertEqual(app?.bundleID, "com.example.some")
    }
}
