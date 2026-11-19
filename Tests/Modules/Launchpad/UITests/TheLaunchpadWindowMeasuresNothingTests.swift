import HelmTestSupport
import XCTest

/// Pass 3's page asked its views how big they were and laid out again on the answer: the log showed the system
/// switching the keyboard tap off and memory up 559 MB. The window's sizes come once from the screen (`LaunchpadGeometry`); this reads the window's source
/// and fails on anything that measures, and on the drag and drop that pass 3 carried, which the window does not have.
final class TheLaunchpadWindowMeasuresNothingTests: XCTestCase {
    private static let banned = ["GeometryReader", "onGeometryChange", "PreferenceKey", "preference(key", "onPreferenceChange",
                                 "onDrag", "onDrop", "draggable", "dropDestination", "LazyVGrid", "LazyHGrid", "LazyVStack", "ScrollViewReader",
                                 "matchedGeometryEffect", "visualEffect", "containerRelativeFrame", "onScrollGeometryChange", "TimelineView"]

    func testNothingInTheLaunchpadUIMeasuresOrDrags() throws {
        let files = try RepoSource.swiftFiles(under: "Sources/Modules/Launchpad/UI")
        XCTAssertTrue(files.contains { $0.hasSuffix("LaunchpadScreen.swift") }, "the scan reads the window's own file")
        var found: [String] = []
        for file in files {
            for (number, line) in try RepoSource.lines(of: file).enumerated() {
                let code = RepoSource.code(line)
                for word in Self.banned where code.contains(word) { found.append("\(file):\(number + 1) \(word)") }
            }
        }
        XCTAssertEqual(found, [], "a window that measures is a layout loop: take the size from LaunchpadGeometry")
    }

    func testTheWindowsHostingViewKeepsNoSizingOfItsOwn() throws {
        let window = try RepoSource.text(of: "Sources/Modules/Launchpad/UI/LaunchpadWindow.swift")
            .components(separatedBy: "\n").map(RepoSource.code).joined(separator: "\n")
        XCTAssertTrue(window.contains("sizingOptions = []"), "the hosting view does not size the window from its content")
    }
}
