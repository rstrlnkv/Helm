import Foundation

/// Making a key: what may be asked for, and the sentence that asks for it.
///
/// Pure. The generation itself is a child on a terminal (`PTYProcess`); what
/// lives here is every decision taken before one is spawned, so each can be
/// asked about without one.
public enum KeyGeneration {

    /// The two types worth offering.
    ///
    /// `ed25519` is the default and the right answer for almost everybody;
    /// `rsa` is here at 4096 bits for the hosts that still demand it. A closed
    /// enum rather than a string, so «what may be generated» is a build-time
    /// question and a payload cannot name a cipher this app has never seen.
    public enum KeyType: String, Codable, Sendable, CaseIterable {
        case ed25519
        case rsa

        /// The bits `ssh-keygen` is told. `ed25519` has one size and refuses
        /// `-b`, so the argument is only added where it means something.
        var bits: Int? { self == .rsa ? 4096 : nil }
    }

    /// What the sheet asks for. **The passphrase is `Data`**, not a `String`:
    /// a `String` is a value this code cannot overwrite, and every other part
    /// of this design exists to keep the secret in one buffer it can zero.
    public struct Request: Codable, Sendable {
        public let type: KeyType
        /// The file name inside `~/.ssh`, never a path.
        public let name: String
        public let comment: String
        /// Empty means no passphrase — which `ssh-keygen` asks for in the same
        /// words and accepts as an empty answer, so there is one path through
        /// the terminal rather than two.
        ///
        /// **`var`, so the engine can move the bytes out of the decoded payload
        /// rather than copy them.** See `Secret`: a copy is a second reference,
        /// and a second reference is what made every `resetBytes` in this
        /// module zero a copy.
        public var passphrase: Data

        public init(type: KeyType, name: String, comment: String, passphrase: Data) {
            self.type = type
            self.name = name
            self.comment = comment
            self.passphrase = passphrase
        }
    }

    /// Why a request was not run.
    public enum Refusal: String, Codable, Sendable, Equatable, Error {
        /// Not a plain file name: empty, `.`/`..`, or carrying a separator.
        case notAPlainName
        /// Something of that name is already in the directory. **Never
        /// overwritten**: `ssh-keygen` would ask, and an answer given to a
        /// question the person never saw is how a key gets destroyed.
        case nameTaken
        /// A comment with a line break in it. It is written into the `.pub`
        /// file, which is one line per key — a break there makes a file `ssh`
        /// reads as two keys, one of them nonsense.
        case commentHasALineBreak
    }

    /// The sentence, or the refusal that stopped it being built.
    ///
    /// The path is composed here and nowhere else, from a directory the caller
    /// owns and a name this function has just judged.
    public static func arguments(for request: Request, in directory: URL)
        -> Result<[String], Refusal> {
        guard isPlain(request.name) else { return .failure(.notAPlainName) }
        guard !request.comment.contains(where: \.isNewline) else {
            return .failure(.commentHasALineBreak)
        }
        var arguments = ["-t", request.type.rawValue,
                         "-f", directory.appendingPathComponent(request.name).path,
                         "-C", request.comment]
        if let bits = request.type.bits { arguments += ["-b", String(bits)] }
        // **No `-N`.** That is the whole point of the terminal: the passphrase
        // is answered at the prompt, never spelled in a sentence every process
        // on the machine can read.
        return .success(arguments)
    }

    /// A name is a name, and nothing else. The same condition
    /// `SystemSSHKeys.url(for:)` applies on its own side; neither is the
    /// other's excuse.
    public static func isPlain(_ name: String) -> Bool {
        !name.isEmpty && !name.contains("/") && name != "." && name != ".."
    }
}

/// What a generation came to.
public enum GenerateOutcome: String, Codable, Sendable, Equatable {
    case done
    case notAPlainName
    case nameTaken
    case commentHasALineBreak
    /// The tool ran and did not make a key.
    case failed
    /// One is already being made. Its own answer rather than a silent second
    /// run: two `ssh-keygen`s pointed at one path is how a key that was just
    /// made is replaced by another the person did not ask for.
    case alreadyRunning

    /// The refusal's own name, so the two enums cannot drift apart at a call
    /// site that maps them by hand.
    static func of(_ refusal: KeyGeneration.Refusal) -> GenerateOutcome {
        switch refusal {
        case .notAPlainName: return .notAPlainName
        case .nameTaken: return .nameTaken
        case .commentHasALineBreak: return .commentHasALineBreak
        }
    }
}
