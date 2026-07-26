import XCTest
@testable import Module_Layout_Engine

/// What happens at the edge of the buffer, where the buffer stops describing
/// the text field.
///
/// The whole conversion is a blind edit: `SwitchPlan` turns the length of the
/// word the buffer reports into a number of backspaces sent to an app Helm
/// cannot read. That is only correct while the buffer holds **everything**
/// typed since the last boundary. Past `maxLength` it holds a prefix of it, and
/// a prefix is the one thing that must never be reported as a word.
final class TypingBufferLimitTests: XCTestCase {
    /// The trap: the buffer stops accepting at 64 characters, but the *field*
    /// keeps taking them. Type 70 letters and a space and the buffer reports a
    /// 64-letter word, so the plan deletes 65 characters out of the 71 that are
    /// in the field — the first six letters survive, the replacement is typed
    /// after them, and somebody's token is now half English and half Russian.
    ///
    /// A word the buffer could not hold entirely is not a word it may report.
    /// Note that clearing on overflow is not a fix either: the tail of a long
    /// token is just as wrong a thing to convert.
    func testAWordTooLongToHoldIsNotReported() {
        var buffer = TypingBuffer()
        let typed = TypingBuffer.maxLength + 6
        for _ in 0..<typed { _ = buffer.accept(.character("g")) }
        XCTAssertNil(buffer.accept(.space),
                     "the buffer held \(TypingBuffer.maxLength) of \(typed) characters; "
                     + "reporting that prefix as a finished word budgets "
                     + "\(TypingBuffer.maxLength) backspaces for \(typed) characters")
    }

    /// …and the boundary that ended the over-long word must leave the buffer
    /// usable, or one pasted line of base64 kills conversions until relaunch.
    func testTheNextWordAfterAnOverflowStillWorks() {
        var buffer = TypingBuffer()
        for _ in 0..<(TypingBuffer.maxLength + 6) { _ = buffer.accept(.character("g")) }
        _ = buffer.accept(.space)
        for character in "ghbdtn" { _ = buffer.accept(.character(character)) }
        XCTAssertEqual(buffer.accept(.space)?.word, "ghbdtn")
    }

    /// A word of exactly `maxLength` is held in full, so it is a word like any
    /// other — the refusal above must start one character later, not one
    /// earlier.
    func testAWordOfExactlyTheLimitIsStillAWord() {
        var buffer = TypingBuffer()
        for _ in 0..<TypingBuffer.maxLength { _ = buffer.accept(.character("g")) }
        let finished = buffer.accept(.space)
        XCTAssertEqual(finished?.word.count, TypingBuffer.maxLength)
        XCTAssertEqual(finished?.ending, " ")
    }

    /// Backspacing back under the limit leaves a word the buffer does describe
    /// in full again — as long as nothing was dropped on the way up.
    func testDeletingBackUnderTheLimitIsStillAnHonestWord() {
        var buffer = TypingBuffer()
        for _ in 0..<(TypingBuffer.maxLength - 1) { _ = buffer.accept(.character("g")) }
        _ = buffer.accept(.backspace)
        XCTAssertEqual(buffer.word.count, TypingBuffer.maxLength - 2)
        XCTAssertEqual(buffer.accept(.space)?.word.count, TypingBuffer.maxLength - 2)
    }
}
