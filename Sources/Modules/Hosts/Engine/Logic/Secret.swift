import Foundation

/// **The one buffer the engine can zero, and the only way out of it.**
///
/// `Data` is copy-on-write, so `resetBytes` reaches the person's own bytes
/// **only while the buffer is uniquely referenced**. With a second live
/// reference it allocates, zeroes the new allocation, and leaves the original
/// exactly where it was — unreferenced, un-overwritten, in freed heap memory
/// for the life of the process. This module's whole passphrase design rests on
/// the port zeroing what it is handed, and every one of those sentences was
/// about a copy: the decoded request held one reference and `var carried = …`
/// made the second.
///
/// A `Data` cannot carry that guarantee itself, because handing one to anybody
/// is a copy. A reference type can: the bytes are taken out of the decoded wire
/// payload at the boundary, and `take()` hands them on and keeps nothing — so
/// the buffer that reaches the port is the buffer the JSON decode produced, and
/// from the decode onwards it is the only one there is.
///
/// **It is not the only copy on the machine, and this file used to say it
/// was.** Two live above the decode, outside anything this type can reach, and
/// both are accepted residuals rather than oversights:
///
/// - **The encoded command.** `TransportClient.request(_:encoding:)` runs
///   `JSONEncoder().encode(payload)`, and Swift's `JSONEncoder` renders a `Data`
///   property as a **base64 String** — so the JSON document handed to
///   `EngineCommand` carries the passphrase in a form that decodes straight
///   back. Modelled: zero both `Data`s and the plaintext still comes out of the
///   wire buffer. What keeps the ceiling low is that `LocalTransport` retains
///   only its last *events*; a command is held for the length of the call, so
///   the document is freed when the request returns — freed, not overwritten.
/// - **The `String` the `SecureField` collected.** A Swift `String` cannot be
///   zeroed at all, and the `Data(passphrase.utf8)` at the call site is a copy
///   taken from it.
///
/// Taking the wire copy away needs a raw-`Data` payload with the secret at a
/// known offset and a transport that zeroes it once `send` returns — which is
/// `EngineCommand`, every module's wire type, reshaped for one command, while
/// the un-zeroable `String` sitting above it stays exactly where it is. Half of
/// that is worse than none: it would buy the design's own sentence back without
/// making it true. So this type does the part that can be done completely —
/// after the decode there is one buffer, and it moves.
///
/// **A copy would defeat it just as thoroughly and look right.** Measured:
/// `Data(secret)` at the call site makes the port's buffer unique and leaves
/// the original one copy away, still holding the passphrase. Nothing here
/// copies; everything moves.
final class Secret: @unchecked Sendable {

    private let lock = NSLock()
    private var data: Data?

    /// Takes the bytes out of the caller's buffer, leaving it empty.
    ///
    /// `inout` rather than a plain argument, because a plain argument would
    /// leave the caller holding the second reference this type exists to
    /// prevent — the defect exactly, in the constructor meant to cure it.
    init(taking buffer: inout Data) {
        data = buffer
        buffer = Data()
    }

    /// The bytes, once. Afterwards this object holds nothing, so the caller's
    /// is the only reference and the port's zeroing lands on the person's own
    /// bytes.
    ///
    /// A second call answers empty rather than trapping: a secret already given
    /// away is a state the wire can reach, and an empty passphrase is what
    /// `ssh-keygen` and `ssh-add` are asked with when there is none.
    func take() -> Data {
        lock.withLock {
            defer { data = nil }
            return data ?? Data()
        }
    }
}
