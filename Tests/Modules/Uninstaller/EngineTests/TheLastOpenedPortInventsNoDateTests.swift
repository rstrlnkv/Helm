import CoreServices
import Foundation
import HelmRuntime
import HelmTestSupport
import XCTest
@testable import Module_Uninstaller_Engine

/// The real last-opened port on a bundle Spotlight has never indexed: the
/// metadata API answers the file's modification date for it, which is no
/// opening. The temporary folder is never indexed, so the case is reproducible
/// without a disk image.
///
/// The precondition asserts that the API really did make the date up, so the
/// case cannot pass where the subject never happened.
final class TheLastOpenedPortInventsNoDateTests: XCTestCase {

    func testABundleSpotlightNeverIndexedHasNoOpeningInvented() throws {
        let root = scratchDirectory("unindexed-bundle")
        let bundle = root.appendingPathComponent("Never Opened.app")
        let info = bundle.appendingPathComponent("Contents/Info.plist")
        try FileManager.default.createDirectory(at: info.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try (["CFBundleIdentifier": "com.x.neveropened", "CFBundleName": "Never Opened"] as NSDictionary)
            .write(to: info)
        let installed = Date(timeIntervalSince1970: 1_577_926_800) // 2020-01-02 01:00 UTC
        try FileManager.default.setAttributes([.modificationDate: installed], ofItemAtPath: bundle.path)

        // The subject: the API itself answers the modification date.
        let item = try XCTUnwrap(MDItemCreate(kCFAllocatorDefault, bundle.path as CFString),
                                 "precondition: Spotlight has no item for the bundle at all")
        let raw = MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date
        XCTAssertEqual(raw, installed,
                       "precondition: the metadata API did not synthesise the modification date, so this case proves nothing")

        let lister = WorkspaceAppLister(home: root, fs: FakeFS(existing: [:]))
        XCTAssertNil(lister.lastOpened(path: bundle.path),
                     "the port answered an opening for a bundle nobody opened — the file's modification date")
    }
}
