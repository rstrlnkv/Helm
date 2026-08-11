import Foundation

/// Converting a selection when nobody knows which way round it was typed.
///
/// The last-word path does not need this: the word was typed a moment ago, with
/// the current input source active, so the conversion goes from that one to the
/// other and there is nothing to guess.
///
/// A selection is different in kind. It may have been typed yesterday, pasted
/// from somewhere, or written by somebody else, and the input source that
/// happens to be active now says nothing about it. Deciding by the active one
/// is why selecting `ghbdtn` with Russian on and pressing the key did nothing:
/// Helm asked for Russian → English, `g` is not on the Russian keyboard, the
/// translation declined, and the app had no way to say so.
///
/// So both directions are asked, the current one first. A direction that hands
/// back what it was given has converted nothing and is not an answer.
enum TwoWayConversion {
    static func result(for text: String,
                       forward: (String) -> String?,
                       backward: (String) -> String?) -> String? {
        if let out = forward(text), out != text { return out }
        if let out = backward(text), out != text { return out }
        return nil
    }
}
