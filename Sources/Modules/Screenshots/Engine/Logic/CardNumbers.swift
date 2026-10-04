import Foundation

/// Helm's own rule for a payment card's number, because the system finds none: its data detector knows a payment
/// identifier of one kind only (UPI), never a card.
///
/// **The rule.** Thirteen to nineteen ASCII digits, in groups with a gap between one group and the next, whose
/// digits pass the Luhn check. A gap is a run of one or two spaces (the plain space, the no-break, narrow no-break,
/// thin, figure and ideographic ones) or a single hyphen, non-breaking hyphen or en dash. A group is a run of digits no separator interrupts, and a card is a
/// run of whole groups: `4111 1111 1111 1111 123` holds the card `4111 1111 1111 1111` and a security code after
/// it, and the code is not part of the number. The longest run of whole groups that passes is taken, from the
/// first group that starts one, and the scan goes on after it.
///
/// **What it does not find, and says so.**
/// - Digits **inside a longer number** — a group of more than nineteen digits, or a card with other digits glued
///   to either end of it, with no separator — are no card: the number is something else and the rule does not guess.
/// - **A number split across two lines** is two readings of one line each, and the rule sees one line at a time.
///   A card whose digits wrap is not found, and nothing here says it is.
/// - **Digits that are not ASCII** (Arabic-Indic, full-width) are not digits to it.
/// - A number that passes the Luhn check by chance is found — the rule errs toward the blur — and a card with a
///   misread digit fails it and is missed.
enum CardNumbers {
    static let digitCounts = 13...19

    /// Where the cards are in `text`, in order.
    static func ranges(in text: String) -> [Range<String.Index>] {
        let groups = digitGroups(in: text)
        var found: [Range<String.Index>] = []
        var first = 0
        while first < groups.count {
            var best: Int?
            var digits = ""
            var last = first
            while last < groups.count {
                if last > first, !joined(groups[last - 1], groups[last], in: text) { break }
                digits += text[groups[last]]
                if digits.count > digitCounts.upperBound { break }
                if digitCounts.contains(digits.count), passesLuhn(digits) { best = last }
                last += 1
            }
            if let best {
                found.append(groups[first].lowerBound..<groups[best].upperBound)
                first = best + 1
            } else {
                first += 1
            }
        }
        return found
    }

    /// The runs of ASCII digits in `text`, each by its range.
    private static func digitGroups(in text: String) -> [Range<String.Index>] {
        var groups: [Range<String.Index>] = []
        var start: String.Index?
        var index = text.startIndex
        while index < text.endIndex {
            let isDigit = text[index].isASCII && text[index].isNumber
            if isDigit, start == nil { start = index }
            if !isDigit, let from = start { groups.append(from..<index); start = nil }
            index = text.index(after: index)
        }
        if let from = start { groups.append(from..<text.endIndex) }
        return groups
    }

    private static let spaces: Set<Character> = [" ", "\u{00A0}", "\u{202F}", "\u{2009}", "\u{2007}", "\u{3000}"]
    private static let dashes: Set<Character> = ["-", "\u{2011}", "\u{2013}"]

    /// Whether a gap of the kinds the rule names (one or two spaces, or one dash) lies between the two groups.
    private static func joined(_ left: Range<String.Index>, _ right: Range<String.Index>, in text: String) -> Bool {
        let between = text[left.upperBound..<right.lowerBound]
        if between.count == 1, let only = between.first { return spaces.contains(only) || dashes.contains(only) }
        return between.count == 2 && between.allSatisfy { spaces.contains($0) }
    }

    static func passesLuhn(_ digits: String) -> Bool {
        var sum = 0
        for (offset, character) in digits.reversed().enumerated() {
            guard let value = character.wholeNumberValue else { return false }
            if offset % 2 == 1 {
                let doubled = value * 2
                sum += doubled > 9 ? doubled - 9 : doubled
            } else {
                sum += value
            }
        }
        return !digits.isEmpty && sum % 10 == 0
    }
}
