import XCTest
@testable import Module_Layout_Engine

/// The buffer decides what a "word" is, and everything downstream trusts it. A
/// boundary it misses is a conversion applied to half of something.
final class TypingBufferTests: XCTestCase {
    private func feed(_ events: [TypingBuffer.Event]) -> TypingBuffer {
        var buffer = TypingBuffer()
        for event in events { _ = buffer.accept(event) }
        return buffer
    }

    func testCharactersAccumulate() {
        XCTAssertEqual(feed([.character("g"), .character("h"), .character("b")]).word, "ghb")
    }

    /// Every boundary returns the finished word exactly once, and clears.
    func testEachBoundaryCompletesTheWord() {
        for boundary in [TypingBuffer.Event.space, .newline, .punctuation("."),
                         .navigation, .click, .focusChange] {
            var buffer = TypingBuffer()
            for character in "ghbdtn" { _ = buffer.accept(.character(character)) }
            XCTAssertEqual(buffer.accept(boundary)?.word, "ghbdtn", "\(boundary)")
            XCTAssertEqual(buffer.word, "")
        }
    }

    /// A boundary with nothing before it must not report an empty word:
    /// downstream would spell-check "".
    func testABoundaryOnAnEmptyBufferCompletesNothing() {
        var buffer = TypingBuffer()
        XCTAssertNil(buffer.accept(.space))
    }

    func testBackspaceRemovesTheLastCharacter() {
        var buffer = feed([.character("a"), .character("b")])
        _ = buffer.accept(.backspace)
        XCTAssertEqual(buffer.word, "a")
        _ = buffer.accept(.backspace)
        _ = buffer.accept(.backspace)
        XCTAssertEqual(buffer.word, "", "past the start it stops rather than going negative")
    }

    /// Losing focus mid-word abandons it: by the time focus returns, the text
    /// underneath may be anywhere.
    func testFocusChangeLeavesNothingBehind() {
        var buffer = feed([.character("x")])
        _ = buffer.accept(.focusChange)
        XCTAssertEqual(buffer.word, "")
    }

    /// The character that ended the word is reported with it: it is already in
    /// the field, and a replacement that ignores it deletes one too few.
    func testTheEndingCharacterComesBackWithTheWord() {
        var buffer = TypingBuffer()
        for character in "abc" { _ = buffer.accept(.character(character)) }
        XCTAssertEqual(buffer.accept(.space)?.ending, " ")

        for character in "abc" { _ = buffer.accept(.character(character)) }
        XCTAssertEqual(buffer.accept(.punctuation("!"))?.ending, "!")

        // Leaving types nothing, so there is nothing extra to delete.
        for character in "abc" { _ = buffer.accept(.character(character)) }
        XCTAssertNil(buffer.accept(.click)?.ending)
    }

    /// A tap that never sees a boundary must not become a leak.
    func testTheBufferIsBounded() {
        var buffer = TypingBuffer()
        for _ in 0..<(TypingBuffer.maxLength + 50) { _ = buffer.accept(.character("a")) }
        XCTAssertLessThanOrEqual(buffer.word.count, TypingBuffer.maxLength)
    }
}
