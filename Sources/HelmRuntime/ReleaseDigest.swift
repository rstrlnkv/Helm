import Foundation
import CryptoKit

/// The one thing standing between a GitHub release asset and code running on
/// the user's Mac.
///
/// The updater downloads a zip, swaps the bundle and relaunches. It strips the
/// quarantine flag on the way — deliberately, so no Gatekeeper prompt appears —
/// and the app is ad-hoc signed, so `codesign --verify` proves nothing: any
/// ad-hoc signature passes. TLS protects the transport, not the contents, so
/// whoever can publish an asset to the repo can run code everywhere.
///
/// So the release notes carry the digest of the asset, and the updater checks
/// the file it downloaded against it. This is not a signature — someone who can
/// publish an asset can publish notes — but it closes the case of a *swapped
/// asset* and gives a place for a real key later. Without a digest the update
/// is not installed silently at all: the release page opens instead, and the
/// user decides.
public enum ReleaseDigest {
    /// The line the release notes carry, e.g.
    /// `sha256 Helm-0.7.1-dev.10.zip 3f9a…`
    public static func line(asset: String, sha256: String) -> String {
        "sha256 \(asset) \(sha256)"
    }

    /// Finds the digest published for `asset`. Case-insensitive on the hex,
    /// exact on the file name — a digest for a different asset is not a digest
    /// for this one.
    public static func parse(notes: String, asset: String) -> String? {
        for raw in notes.split(separator: "\n") {
            let fields = raw.split(whereSeparator: \.isWhitespace).map(String.init)
            guard fields.count >= 3,
                  fields[0].lowercased() == "sha256",
                  fields[1] == asset else { continue }
            let hex = fields[2].lowercased()
            guard isHexDigest(hex) else { continue }
            return hex
        }
        return nil
    }

    /// 64 lowercase hex characters and nothing else: a truncated or decorated
    /// digest must not compare equal to anything.
    public static func isHexDigest(_ value: String) -> Bool {
        value.count == 64 && value.allSatisfy { $0.isHexDigit && !$0.isUppercase }
    }

    /// Streams the file rather than reading it whole: a release zip is tens of
    /// megabytes and this runs while the app is up.
    ///
    /// The pool goes **inside** the loop, not around it. `FileHandle.read`
    /// returns an autoreleased `Data`, so without one every slice ever read
    /// stays alive until the whole call returns and the footprint tracks the
    /// volume read rather than what is kept: measured over a 1200 MB file,
    /// 1204 MB of growth without the pool against 1.0 MB with it. This is the
    /// same defect the duplicate scanner's hash loop had, in a loop that is not
    /// even parallel — see ARCHITECTURE.md § Memory.
    public static func sha256(ofFileAt url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            // Read and update inside the pool, hand only a verdict back out —
            // the same shape `DuplicateScanner.hash` uses, so the slice never
            // outlives the iteration that read it.
            let more: Bool = try autoreleasepool {
                guard let data = try handle.read(upToCount: 1 << 20), !data.isEmpty else {
                    return false
                }
                hasher.update(data: data)
                return true
            }
            if !more { break }
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Constant-time in the sense that matters here: both are fixed-length hex
    /// we produced ourselves, so a plain comparison leaks nothing useful.
    public static func matches(fileAt url: URL, expected: String) -> Bool {
        guard isHexDigest(expected.lowercased()),
              let actual = try? sha256(ofFileAt: url) else { return false }
        return actual == expected.lowercased()
    }
}
