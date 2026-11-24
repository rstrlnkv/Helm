import Foundation

/// A digest as the string everything here writes it: lowercase hex, two digits
/// a byte, nothing between them.
///
/// One spelling, because it is not free to differ: an update's digest is
/// compared against what a release note published, and a rule's mark
/// (`RuleStamp`) is compared as a string against the ones an earlier build
/// wrote onto somebody's files. The answer is identical, for all 256 byte
/// values, to `String(format: "%02x")`.
///
/// It is also the fast way: `String(format:)` goes through Foundation's
/// formatter and allocates a `String` per byte, many times slower, and a
/// duplicate group's id is asked on every `ForEach` diff, a render path.
public enum HexDigest {

    private static let digits = Array("0123456789abcdef".utf8)

    /// - Parameter bytes: a `SHA256Digest`, an HMAC code, or any other run of
    ///   bytes. Taken as a `Sequence` so no caller has to copy its digest into
    ///   a `Data` first.
    public static func string(of bytes: some Sequence<UInt8>) -> String {
        var out: [UInt8] = []
        out.reserveCapacity(bytes.underestimatedCount * 2)
        for byte in bytes {
            out.append(digits[Int(byte >> 4)])
            out.append(digits[Int(byte & 0x0F)])
        }
        // The rule guards against `String(decoding:)` turning invalid bytes into
        // U+FFFD. None can reach here: every element came from `digits`, which
        // is ASCII. The failable form would need a `?? ""`, and an empty string
        // standing in for a digest is the one answer this type must never give.
        // swiftlint:disable:next optional_data_string_conversion
        return String(decoding: out, as: UTF8.self)
    }
}
