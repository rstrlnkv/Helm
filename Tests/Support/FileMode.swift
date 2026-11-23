import Foundation
import XCTest

public extension XCTestCase {

    /// The POSIX permission bits of the file at `url`, as `0o600` and the like.
    ///
    /// A missing attribute fails the test rather than reading as `0`: a mode of
    /// zero is a real answer to the question these tests ask, and a read that
    /// cannot tell the two apart passes `0o000` assertions for the wrong reason.
    func mode(of url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return try XCTUnwrap(attributes[.posixPermissions] as? Int)
    }
}
