import Foundation

/// **The one buffer a typed passphrase lives in, and the only way out of it.**
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
/// is a copy. A reference type can: the bytes are taken out of the wire payload
/// at the boundary, and `take()` hands them on and keeps nothing — so the
/// buffer that reaches the port is the buffer the JSON decode produced, and it
/// is the only one there is.
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
