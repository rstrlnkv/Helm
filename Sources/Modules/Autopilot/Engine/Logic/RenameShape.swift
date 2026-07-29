import Foundation

/// The names one rename pattern can produce for one file: the pattern with
/// `{date}` and `{counter}` already resolved and `{name}` left as a hole.
///
/// It exists to answer whether a rename has already happened. `RuleStamp` is the
/// general answer to that and a volume without extended attributes cannot keep
/// it — `setxattr` returns `ENOTSUP` on exFAT, which is what a USB stick usually
/// is, and `WatchScope` admits `/Volumes` on purpose. So the sweep an hour later
/// asks the pattern again, `{name}` takes the previous run's output as its
/// input, and a pattern that adds anything at all adds it once an hour until the
/// name passes the 255-byte limit on a path component and the rule fails on that
/// file for good.
///
/// A prefix test would cover `{date}-{name}` and miss `{name} {date}`,
/// `{name}{counter}` and anything that puts the file's name in the middle. The
/// question is not what the name starts with; it is whether the name is one this
/// pattern could have produced.
struct RenameShape {

    /// The literal text around the holes: one more of these than there are
    /// `{name}`s, and exactly one when the pattern never names the file.
    private let literals: [String]

    /// Trimmed, because `RenamePattern` trims what it produces: the name that
    /// lands from `"  {name}  "` carries no padding, so its shape must not
    /// expect any.
    init(resolved template: String) {
        literals = template
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: RenamePattern.nameToken)
    }

    /// Whether `stem` reads as this shape: every literal, in order, with at
    /// least one character standing in for each hole.
    func matches(_ stem: String) -> Bool {
        guard let head = literals.first, stem.hasPrefix(head) else { return false }
        return Self.matches(stem.dropFirst(head.count), against: literals.dropFirst())
    }

    /// Every remaining literal has a hole in front of it, and a hole is never
    /// empty — a file has a name — so the literal is looked for from the second
    /// character on. Searched rather than measured because two holes can divide
    /// what is left in more than one way, and only the rest of the shape can say
    /// which division was the one that happened.
    private static func matches(_ rest: Substring, against literals: ArraySlice<String>) -> Bool {
        guard let literal = literals.first else { return rest.isEmpty }
        guard !rest.isEmpty else { return false }
        var start = rest.index(after: rest.startIndex)
        while true {
            let candidate = rest[start...]
            if candidate.hasPrefix(literal),
               matches(candidate.dropFirst(literal.count), against: literals.dropFirst()) {
                return true
            }
            guard start < rest.endIndex else { return false }
            start = rest.index(after: start)
        }
    }
}
