import XCTest
@testable import HelmRuntime

extension XCTestCase {
    /// A scan entry of `bytes` at `path`, the one line the scan tests each wrote for themselves.
    func item(_ path: String, _ bytes: Int) -> ScanItem {
        ScanItem(path: path, bytes: bytes)
    }
}
