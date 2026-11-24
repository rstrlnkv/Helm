import XCTest
@testable import Module_Layout_Engine

/// Whether the clipboard can survive being borrowed.
///
/// The paste route saves the clipboard, overwrites it, pastes, and puts the old
/// one back — but it can only put back a string. A clipboard holding an image,
/// RTF or a file promise comes back as plain text or as nothing.
///
/// The gesture has a default key, so this path is reachable by default, and this
/// decision is what contains it.
final class PasteboardSafetyTests: XCTestCase {

    func testAStringOnlyClipboardCanBeBorrowed() {
        XCTAssertTrue(PasteboardSafety.canBorrow(types: ["public.utf8-plain-text"]))
        XCTAssertTrue(PasteboardSafety.canBorrow(types: ["public.utf8-plain-text",
                                                         "public.plain-text"]))
    }

    /// Nothing to lose.
    func testAnEmptyClipboardCanBeBorrowed() {
        XCTAssertTrue(PasteboardSafety.canBorrow(types: []))
    }

    /// Each of these is destroyed by a save-and-restore that only knows about
    /// strings.
    func testAnythingElseIsRefused() {
        XCTAssertFalse(PasteboardSafety.canBorrow(types: ["public.tiff"]))
        XCTAssertFalse(PasteboardSafety.canBorrow(types: ["public.rtf"]))
        XCTAssertFalse(PasteboardSafety.canBorrow(types: ["com.apple.pasteboard.promised-file-url"]))
        XCTAssertFalse(PasteboardSafety.canBorrow(types: ["public.png", "public.utf8-plain-text"]),
                       "a screenshot copied with its text alternative is still a screenshot")
    }

    /// An app that also advertises RTF alongside plain text — Pages, Word, Mail
    /// — is the common case, and losing the formatting is still a loss.
    func testRichTextAlongsidePlainIsStillRefused() {
        XCTAssertFalse(PasteboardSafety.canBorrow(types: ["public.rtf", "public.utf8-plain-text"]))
    }
}
