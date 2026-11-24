import XCTest
import HelmTestSupport
import HelmRuntime
@testable import Module_Disk_Engine
@testable import Module_Disk_UI

/// The one row on the ring whose path names no file.
///
/// `…` is the per-directory aggregate the scan invents, and also a name a
/// person can type. The gate judges no names, so the `isFolded` flag keeps the
/// aggregate out, at `toggleBasket`, where every press, menu item and keyboard
/// action arrives.
@MainActor
final class TheBucketCannotBePickedTests: XCTestCase {

    private func model() -> DiskViewModel {
        DiskViewModel(work: AnsweringWork(volumes: []),
                      store: ScanStore(directory: scratchDirectory("disk-bucket-pick")))
    }

    private func entry(_ path: String, isFolded: Bool) -> DiskEntry {
        DiskEntry(name: (path as NSString).lastPathComponent, path: path, bytes: 400_000_000,
                  isDirectory: false, noAccess: false, children: [], isFolded: isFolded)
    }

    func testTheFoldedBucketDoesNotGoInTheBasket() {
        let dvm = model()
        let bucket = entry("/Users/test/Movies/…", isFolded: true)

        dvm.toggleBasket(bucket)

        // The row draws its basket button from the same predicate, so a bucket
        // that cannot be picked is also a bucket with nothing to press.
        XCTAssertFalse(dvm.canBasket(bucket))
        XCTAssertEqual(dvm.basket.map(\.path), [], """
            the scan's own aggregate was picked. Its path is the path a real file called `…` \
            would have, and everything past `DiskRemovalPlan` is strings — so a bucket that \
            gets this far is a removal aimed at a file that may not exist, or at somebody \
            else's.
            """)
    }

    /// The control: the same path and name without the flag is an ordinary file
    /// and goes in.
    func testAFileTheUserNamedLikeTheBucketGoesIn() {
        let dvm = model()
        let real = entry("/Users/test/Movies/…", isFolded: false)

        dvm.toggleBasket(real)

        XCTAssertTrue(dvm.canBasket(real), "and its row draws a basket button")
        XCTAssertEqual(dvm.basket.map(\.path), ["/Users/test/Movies/…"],
                       "a file the person made and can see on the ring cannot be picked")
    }
}
