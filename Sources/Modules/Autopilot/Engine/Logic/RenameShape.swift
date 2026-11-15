import Foundation

/// The names one rename pattern can produce for one file: the pattern with
/// `{date}` already resolved and `{name}` and `{counter}` left as holes.
///
/// It exists to answer whether a rename has already happened. `RuleStamp` is the
/// general answer to that, and `RuleRunner.note` tolerates a stamp that will not
/// stick — a volume that refuses extended attributes, or an AppleDouble `._name`
/// sidecar that something along the way dropped. `WatchScope` admits `/Volumes`
/// on purpose, so those volumes are reachable. Unstamped, the sweep an hour
/// later asks the pattern again, `{name}` takes the previous run's output as its
/// input, and a pattern that adds anything at all adds it once an hour until the
/// name passes the 255-byte limit on a path component and the rule fails on that
/// file for good.
///
/// A prefix test would cover `{date}-{name}` and miss `{name} {date}`,
/// `{name}{counter}` and anything that puts the file's name in the middle. The
/// question is not what the name starts with; it is whether the name is one this
/// pattern could have produced.
struct RenameShape {

    private enum Part: Equatable {
        case literal(String)
        /// At least one character.
        case name
        /// Three or more digits: what `%03d` writes, whichever number it was.
        case counter
    }

    private let parts: [Part]
    private let ignoringCase: Bool

    /// Trimmed, because `RenamePattern` trims what it produces: the name that
    /// lands from `"  {name}  "` carries no padding, so its shape must not
    /// expect any. `{counter}` stays a hole here too: which number a file wears
    /// is the first-free search's business, so `photo-002` is as much
    /// `photo-{counter}` as `photo-001` is.
    ///
    /// **Any three digits are a counter, so a name like `invoice-2024` reads as
    /// already shaped by `invoice-{counter}`.** Kept on purpose: the cost is a
    /// file left alone that a person might have expected renamed, where the
    /// other way round it is a rename the unattended sweep repeats.
    ///
    /// `ignoringCase` is for asking which numbers a *folder* already wears:
    /// APFS holds `Invoice-001.pdf` and `invoice-001.pdf` to be one name, so
    /// the first occupies `001` for the pattern `invoice-{counter}`. The
    /// idempotency question keeps case, because a rule that normalises
    /// capitals (`REPORT`) must still see `report` as not yet done.
    init(resolved template: String, ignoringCase: Bool = false) {
        self.ignoringCase = ignoringCase
        var parts: [Part] = []
        var literal = ""
        var rest = Substring(template.trimmingCharacters(in: .whitespacesAndNewlines))
        func flush() {
            if !literal.isEmpty {
                parts.append(.literal(ignoringCase ? Self.fold(literal) : literal))
            }
            literal = ""
        }
        while !rest.isEmpty {
            if rest.hasPrefix(RenamePattern.nameToken) {
                flush(); parts.append(.name)
                rest = rest.dropFirst(RenamePattern.nameToken.count)
            } else if rest.hasPrefix(RenamePattern.counterToken) {
                flush(); parts.append(.counter)
                rest = rest.dropFirst(RenamePattern.counterToken.count)
            } else {
                literal.append(rest.removeFirst())
            }
        }
        flush()
        self.parts = parts
    }

    private static func fold(_ text: String) -> String {
        text.folding(options: .caseInsensitive, locale: nil)
    }

    /// Whether `stem` reads as this shape: every literal, in order, with at
    /// least one character standing in for each name hole and three or more
    /// digits for each counter.
    func matches(_ stem: String) -> Bool {
        reading(stem) != nil
    }

    /// The counter numbers `stem` can be read as wearing, 1 to
    /// `RenamePattern.maxCounter`; a stem the shape does not describe wears none.
    /// Every way of dividing the stem is considered: `{counter}-{counter}` on
    /// `001-002` wears `1` and `2`, and `{name}-{counter}-x` on `a-001-002-x`
    /// wears `2` only, the name taking `a-001`.
    func numbers(in stem: String) -> Set<Int> {
        reading(stem) ?? []
    }

    private func reading(_ stem: String) -> Set<Int>? {
        var walk = Walk(characters: Array(ignoringCase ? Self.fold(stem) : stem), parts: parts)
        return walk.from(position: 0, part: 0)
    }

    /// One pass over (position, part) states, each answered once: the stem's
    /// length times the shape's parts, however many `{name}` holes divide the
    /// stem between them. Unmemoised, k holes cost about n^k on a long file
    /// name, which a watched folder and the editor's dry run can both supply.
    private struct Walk {
        let characters: [Character]
        let parts: [Part]
        private var seen: [Int: Set<Int>?] = [:]

        init(characters: [Character], parts: [Part]) {
            self.characters = characters
            self.parts = parts
        }

        /// Nil when no reading of the rest of the stem fits the rest of the
        /// shape; otherwise the counter numbers those readings wear.
        mutating func from(position: Int, part: Int) -> Set<Int>? {
            let key = position * (parts.count + 1) + part
            if let known = seen[key] { return known }
            let answer = compute(position, part)
            seen[key] = .some(answer)
            return answer
        }

        private mutating func compute(_ position: Int, _ part: Int) -> Set<Int>? {
            guard part < parts.count else { return position == characters.count ? [] : nil }
            switch parts[part] {
            case let .literal(text):
                let literal = Array(text)
                guard position + literal.count <= characters.count,
                      Array(characters[position..<position + literal.count]) == literal else {
                    return nil
                }
                return from(position: position + literal.count, part: part + 1)
            case .name:
                var found: Set<Int>?
                for end in (position + 1)..<max(position + 1, characters.count + 1) {
                    if let rest = from(position: end, part: part + 1) {
                        found = (found ?? []).union(rest)
                    }
                }
                return found
            case .counter:
                var run = 0
                while position + run < characters.count,
                      characters[position + run].isASCII, characters[position + run].isNumber {
                    run += 1
                }
                guard run >= 3 else { return nil }
                var found: Set<Int>?
                for length in 3...run {
                    guard let rest = from(position: position + length, part: part + 1) else {
                        continue
                    }
                    let significant = characters[position..<position + length].drop { $0 == "0" }
                    var numbers = rest
                    if significant.count <= 3, let value = Int(String(significant)),
                       value <= RenamePattern.maxCounter {
                        numbers.insert(value)
                    }
                    found = (found ?? []).union(numbers)
                }
                return found
            }
        }
    }
}
