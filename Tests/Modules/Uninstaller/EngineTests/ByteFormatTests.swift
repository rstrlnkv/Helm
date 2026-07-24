import XCTest
@testable import Module_Uninstaller_Engine

final class ByteFormatTests: XCTestCase {
    func testUnits() {
        XCTAssertEqual(ByteFormat.string(0), "0 B")
        XCTAssertEqual(ByteFormat.string(512), "512 B")
        XCTAssertEqual(ByteFormat.string(2048), "2.0 KB")
        XCTAssertEqual(ByteFormat.string(5 * 1024 * 1024), "5.0 MB")
    }
}
