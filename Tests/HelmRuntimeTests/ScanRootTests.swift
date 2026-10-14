import XCTest
@testable import HelmRuntime

final class ScanRootTests: XCTestCase {

    private var home: String { FileManager.default.homeDirectoryForCurrentUser.path }

    private var made: [URL] = []

    override func tearDown() {
        for url in made.reversed() { try? FileManager.default.removeItem(at: url) }
        made = []
        super.tearDown()
    }

    /// A real directory in the home, named as asked, or inside `parent` when
    /// one is given; the ones made directly in the home are removed in
    /// `tearDown`. The root has to exist on disk: `resolve` refuses what is not
    /// there, which would make every refusal below pass for the wrong reason.
    private func directoryInHome(named name: String, under parent: URL? = nil) throws -> URL {
        let base = parent ?? URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        let url = base.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        if parent == nil { made.append(url) }
        return url
    }

    /// The commonest root there is, and the one `UserFileScope.isRemovable`
    /// refuses — which is why this gate exists separately.
    func testTheHomeItselfIsAllowed() {
        XCTAssertNotNil(ScanRoot.resolve(home))
    }

    func testAFolderInsideTheHomeIsAllowed() {
        XCTAssertNotNil(ScanRoot.resolve(home + "/Downloads"))
        XCTAssertNotNil(ScanRoot.resolve(home + "/Documents"))
    }

    /// The whole point. A rewritten plist naming the volume root would send an
    /// unattended reader across every file on the machine.
    func testTheVolumeRootIsRefused() {
        XCTAssertNil(ScanRoot.resolve("/"))
        XCTAssertNil(ScanRoot.resolve("/System"))
        XCTAssertNil(ScanRoot.resolve("/usr/bin"))
        XCTAssertNil(ScanRoot.resolve("/Library"))
    }

    /// Somebody else's home is not this person's to read, even unattended and
    /// even if the filesystem would allow it.
    func testAnotherUsersHomeIsRefused() {
        XCTAssertNil(ScanRoot.resolve("/Users"))
        XCTAssertNil(ScanRoot.resolve("/Users/somebody-else"))
    }

    /// A relative path resolves against the process's working directory, which
    /// is not a place anybody chose to scan.
    func testARelativePathIsRefused() {
        XCTAssertNil(ScanRoot.resolve("Downloads"))
        XCTAssertNil(ScanRoot.resolve(""))
        XCTAssertNil(ScanRoot.resolve("../.."))
    }

    /// The spelling is not the path. A gate that tests strings must resolve
    /// before it tests.
    func testTraversalOutOfTheHomeIsRefused() {
        XCTAssertNil(ScanRoot.resolve(home + "/../.."))
        XCTAssertNil(ScanRoot.resolve(home + "/Documents/../../../System"))
    }

    /// `standardizingPath` resolves `..` and `~` and never case, and the boot
    /// volume is case-insensitive — so a prefix test alone is fooled by the
    /// home's own name in another case.
    func testTheHomeIsMatchedRegardlessOfCase() {
        XCTAssertNotNil(ScanRoot.resolve(home.uppercased()))
    }

    /// A path that is not there is not a root. The scan would walk nothing and
    /// report a clean folder, which is the failure that must not look like an
    /// answer.
    func testAPathThatDoesNotExistIsRefused() {
        XCTAssertNil(ScanRoot.resolve(home + "/definitely-not-here-\(UUID().uuidString)"))
    }

    /// A file is not a folder to scan.
    func testAFileIsRefused() throws {
        let file = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("scan-root-\(UUID().uuidString).txt")
        try Data("x".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        XCTAssertNil(ScanRoot.resolve(file.path))
    }

    // MARK: - An application's database is not a root

    /// An existing `X.photoslibrary` in the home is the directory the walk
    /// refuses to descend into; a root that is one begins the walk inside it.
    func testAnExistingApplicationLibraryIsRefusedAsARoot() throws {
        let library = try directoryInHome(named: "helm-root-\(UUID().uuidString).photoslibrary")
        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: library.path, isDirectory: &isDirectory)
                      && isDirectory.boolValue, "the premise: the library exists")
        let answer = ScanRoot.resolve(library.path)
        XCTAssertNil(answer, "resolve answered \(String(describing: answer)) for \(library.path)")
    }

    /// The same, for every extension the descent gate names, and in upper case.
    func testEveryApplicationLibraryExtensionIsRefusedAsARootInAnyCase() throws {
        for ext in ScanRoot.applicationLibraryExtensions.sorted() {
            for spelled in [ext, ext.uppercased()] {
                let library = try directoryInHome(named: "helm-root-\(UUID().uuidString).\(spelled)")
                let answer = ScanRoot.resolve(library.path)
                XCTAssertNil(answer, "resolve answered \(String(describing: answer)) for .\(spelled)")
            }
        }
    }

    /// A folder inside a library is as much inside it as the library's own
    /// children are: the walk would never have got there.
    func testAFolderInsideAnApplicationLibraryIsRefusedAsARoot() throws {
        let library = try directoryInHome(named: "helm-root-\(UUID().uuidString).photoslibrary")
        let inside = try directoryInHome(named: "originals", under: library)
        let deeper = try directoryInHome(named: "0", under: inside)
        for root in [inside, deeper] {
            let answer = ScanRoot.resolve(root.path)
            XCTAssertNil(answer, "resolve answered \(String(describing: answer)) for \(root.path)")
        }
    }

    /// A link in the home is resolved to its end, so a link to a library is the
    /// library.
    func testALinkToAnApplicationLibraryIsRefusedAsARoot() throws {
        let library = try directoryInHome(named: "helm-root-\(UUID().uuidString).photoslibrary")
        let link = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .appendingPathComponent("helm-root-link-\(UUID().uuidString)")
        try FileManager.default.createSymbolicLink(atPath: link.path,
                                                  withDestinationPath: library.path)
        made.append(link)
        let answer = ScanRoot.resolve(link.path)
        XCTAssertNil(answer, "resolve answered \(String(describing: answer)) for the link \(link.path)")
    }

    /// Held, green before and after: a name that only resembles a library is
    /// an ordinary folder. It pins a repair that matches by substring.
    func testAFolderWhoseNameOnlyResemblesALibraryIsStillAllowed() throws {
        for name in ["helm-root-\(UUID().uuidString).photoslibrary.old",
                     "helm-root-\(UUID().uuidString) photoslibrary backups",
                     "helm-root-\(UUID().uuidString)photoslibrary"] {
            let folder = try directoryInHome(named: name)
            let answer = ScanRoot.resolve(folder.path)
            XCTAssertNotNil(answer, "resolve refused \(folder.path)")
        }
    }
}
