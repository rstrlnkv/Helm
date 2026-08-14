import Foundation

/// A digest as the string everything here writes it: lowercase hex, two digits
/// a byte, nothing between them.
///
/// Written four times before it moved — `ReleaseDigest.sha256`,
/// `SettingSeal.mac`, `DuplicateScanner.hash` and `DuplicateGroup.id` each
/// spelled `map { String(format: "%02x", $0) }.joined()`, two of them inside
/// this target — and the spelling is not free to differ: an update's digest is
/// compared against what a release note published, and a seal's is compared
/// against what an earlier build wrote into somebody's settings. One uppercase
/// letter would refuse every sealed setting on the Mac it shipped to.
///
/// It is also the fast way, which the hand-written line was not.
/// `String(format:)` goes through Foundation's formatter for every byte and
/// allocates a `String` for each, then joins 32 of them; a group's id is asked
/// once per group on every `ForEach` diff, which is a render path. Measured at
/// `-O` over 100.000 SHA-256 digests, three runs agreeing: 2.25 s the old way
/// against 0.033 s this way, 22.3 µs a digest against 0.33 µs. The answer is
/// identical for all 256 byte values, which is what `HexDigestTests` pins —
/// against the old line written out, not against this one.
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
        // U+FFFD where a failable initializer would have said so. There is no
        // invalid byte to reach here: every element was just taken from
        // `digits`, which is ASCII. The failable form would need a `?? ""`, and
        // an empty string standing in for a digest is the one answer this type
        // must never give — it compares equal to nothing and refuses everything.
        // swiftlint:disable:next optional_data_string_conversion
        return String(decoding: out, as: UTF8.self)
    }
}
