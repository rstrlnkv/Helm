import XCTest
@testable import HelmRuntime

/// One folder, one spelling.
///
/// `HelmTrash` answers once per path and `SystemFolderNames` looks a folder up
/// by its last component; both had written the same trailing-separator strip by
/// hand, and the trash loop's copy took one separator off where a path joined
/// onto a root that already ended in one carries two. They share the rule now,
/// so it is stated here rather than only through what each caller does with it.
final class PathSpellingTests: XCTestCase {

    /// Every spelling of one folder answers the same string. Asserted as "how
    /// many distinct answers", which is the property — a comparison against one
    /// expected spelling passes for a function that strips too much as easily
    /// as for one that strips enough.
    func testEverySpellingOfOneFolderAnswersTheSameString() {
        let spellings = ["/Users/x/Ghost", "/Users/x/Ghost/", "/Users/x/Ghost//",
                         "/Users/x/Ghost///"]
        let answers = Set(spellings.map(PathCanonical.withoutTrailingSeparators))

        XCTAssertEqual(answers, ["/Users/x/Ghost"],
                       "\(spellings.count) spellings of one folder answered \(answers.sorted())")
    }

    /// The root is the one path that is nothing but a separator, and a rule that
    /// strips them all would leave it empty — which names nothing at all.
    func testTheRootKeepsItsOwnSeparator() {
        XCTAssertEqual(PathCanonical.withoutTrailingSeparators("/"), "/")
        XCTAssertEqual(PathCanonical.withoutTrailingSeparators("//"), "/")
    }

    /// A separator anywhere but the end is part of the path, and a name that
    /// merely ends in something separator-shaped is a name.
    func testNothingButTheEndIsTouched() {
        for path in ["/Users/x/Ghost/inside.bin", "/Users/x/two words.bin",
                     "/Users/x/trailing dot.", "relative/path"] {
            XCTAssertEqual(PathCanonical.withoutTrailingSeparators(path), path)
        }
    }
}
