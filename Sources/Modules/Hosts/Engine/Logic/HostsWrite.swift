import Foundation
import HelmRuntime

/// The one command this module ever asks root to run.
///
/// **Three properties, each deliberate.**
///
/// 1. *The command carries its content, never a path.* A file staged in
///    `$TMPDIR` and named to root stands in `ps auxww` for as long as the
///    password prompt is up, and any process running as this user can swap it
///    between the prompt and the write. Keep Awake's sudoers rule was built
///    that way once; `SudoersRule` carries that story.
/// 2. *base64 is the gate.* Its alphabet holds no quote, no `$`, no backtick,
///    no `;`, no backslash and no newline — so there is nothing in an encoded
///    payload that can end the AppleScript literal and become root's intent.
///    Injection here is unrepresentable rather than unlikely, and that is a
///    stronger claim than any amount of escaping. The quotes in the sentence
///    below are the author's own, around the count substitution;
///    `AppleScript.literal` escapes those two, and no payload can add a third.
/// 3. *`>` truncates in place — and truncates first.* Owner `root:wheel` and
///    mode 644 belong to the file, not to the write; no new inode appears and
///    no umask is inherited. But the shell opens the redirect *before* the
///    pipeline runs, so anything checked after it is a post-mortem, and
///    `|| exit 1` is not the promise it reads as. Three readings, macOS 27,
///    2026-08-18, taken on scratch files:
///
///    - A pipeline's status is its **last** command's. With `/bin/echo` unable
///      to run, `base64 -D` read EOF, wrote nothing and exited 0 — so
///      `|| exit 1` never fired and root reported *success* over an emptied
///      file. This is the shape a payload too long for `ARG_MAX` arrives in.
///    - `>` truncates **before** the decoder runs. A 20-byte file was already 0
///      bytes when `QQ==QQ==` was rejected, and the refusal came afterwards.
///    - `QQ=` decodes to **nothing at status 0**, and so do `Q`, `=` and
///      `====`. Every one of them is inside this alphabet.
///
///    So the count guard runs first, and the redirect does not exist until the
///    payload has decoded to exactly the number of bytes the file is meant to
///    have. Two of those three paths ended in «the file is empty and the write
///    said it worked», which is worse than any refusal: the engine's read-back
///    would notice, but noticing is not the same as not destroying, and the
///    person cannot get the file back without a backup they do not yet know is
///    there.
///
/// **This gate and `HostsFile`'s are about different things, and neither
/// replaces the other.** `HostsFile`'s editors guard the file's *grammar* — a
/// newline inside a name is a second live mapping nobody typed. This one guards
/// the *shell sentence*: a payload can be a perfectly well-formed hosts file and
/// still end root's literal, and it can be an unimpeachable base64 string that
/// decodes to nonsense. A payload has to pass both, in that order.
///
/// The DNS flush rides along because it needs root too, and because without it
/// the edit «does not work» for minutes and the app gets the blame.
public enum HostsWrite {

    /// The file, as a constant. Never composed, never an argument, never taken
    /// from a payload — the only path in this module that needs no gate,
    /// because it cannot be influenced.
    public static let path = "/etc/hosts"

    private static let alphabet = Set(
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=")

    /// Whether the sentence carrying `text` would survive its own `execve`.
    ///
    /// **The ceiling is accepted and made legible, not lifted.** `do shell
    /// script` execs `/bin/sh -c <the whole string>`, `ARG_MAX` is 1 048 576 on
    /// macOS, base64 costs 4 bytes for every 3 — and the count guard spells the
    /// payload *twice*, checked then written. That leaves ≈390 KB of hosts
    /// file. Ad-blocking hosts files run 1–4 MB and cannot be written at all.
    ///
    /// Exceeding it is *safe*: the exec itself refuses, nothing runs, the file
    /// is untouched. What was missing was words, and the caller asks this
    /// **before the encode** so that «too large» never arrives as the `nil`
    /// from `command(base64:)`, which already means «not base64». Two different
    /// refusals must not arrive as one outcome.
    ///
    /// The arithmetic lives here because the ceiling is a fact about the
    /// *sentence*, and only this file knows the sentence's shape — a caller
    /// computing it would be re-deriving the command.
    static func fits(_ text: String) -> Bool {
        let bytes = text.utf8.count
        // Base64 is 4 characters per 3 bytes, rounded up to a whole group.
        let payload = 4 * ((bytes + 2) / 3)
        return sentenceOverhead + 2 * payload + String(bytes).utf8.count <= budget
    }

    /// Everything in the AppleScript but the payload and the count — measured
    /// off the real sentence rather than counted by hand, so that editing the
    /// command or the wrapper moves the ceiling with it.
    ///
    /// `.max` if the sample is somehow refused, which makes `fits` answer false
    /// for everything: a ceiling that cannot be computed refuses in the safe
    /// direction, the way a broken seal does.
    private static let sentenceOverhead: Int = {
        let sample = "QUJD"  // three bytes, so the count substitutes one digit
        guard let shell = command(base64: sample) else { return .max }
        let script = AppleScript.administratorShellScript(shell)
        return script.utf8.count - 2 * sample.utf8.count - 1
    }()

    /// `ARG_MAX` less room for the environment, which `execve` weighs beside
    /// the arguments. Asked of the kernel rather than copied from a man page —
    /// it is a fact about the machine, and a number in the source would be a
    /// claim nothing keeps true.
    ///
    /// The headroom is generous on purpose. Being too cautious costs a person
    /// nothing but a sentence they can read; being too bold costs an `E2BIG` at
    /// the dialog, after they have typed their password.
    private static let budget = Int(sysconf(_SC_ARG_MAX)) - 64 * 1024

    /// The file's bytes as base64, for `command(base64:)`.
    public static func encode(_ text: String) -> String {
        Data(text.utf8).base64EncodedString()
    }

    /// The shell command for `AppleScript.administratorShellScript`, or `nil`
    /// if the payload is not base64 — which is the gate, and the reason this
    /// returns an optional rather than a string.
    ///
    /// The AppleScript wrapping is `AppleScript.administratorShellScript`'s
    /// job and is deliberately not repeated here: the escaping that decides
    /// whether root runs a command or an attacker's continuation of it lives in
    /// exactly one place in this app.
    public static func command(base64: String) -> String? {
        guard !base64.isEmpty, base64.allSatisfy({ alphabet.contains($0) }) else { return nil }
        return "[ \"$(\(decode(base64)) | /usr/bin/wc -c)\" -eq \(expectedBytes(base64)) ] || exit 1; "
            + "\(decode(base64)) > \(path) || exit 1; "
            + "/usr/bin/dscacheutil -flushcache >/dev/null 2>&1; "
            + "/usr/bin/killall -HUP mDNSResponder >/dev/null 2>&1; "
            + "exit 0"
    }

    /// Named once and spelled into the sentence twice — checked, then written.
    /// The payload is one shell word: this alphabet has no space and no glob
    /// character, and cannot begin with `-`, so it is never a second argument
    /// and never an option to `/bin/echo`.
    private static func decode(_ base64: String) -> String {
        "/bin/echo \(base64) | /usr/bin/base64 -D"
    }

    /// How many bytes the shell must count before it is allowed to open the
    /// file — an `Int`, so it carries nothing but itself.
    ///
    /// **A number `wc -c` cannot answer with is the refusal.** Foundation and
    /// `/usr/bin/base64` do not agree on every string in the alphabet (`====`
    /// is one byte to one and nothing to the other), so this is not a decode
    /// the app is trusting — it is a claim the shell has to meet with its own
    /// decoder before the redirect exists. Nothing is the answer to a payload
    /// Foundation refuses, and to one that decodes empty: `0` is a count `wc`
    /// *can* produce, so asking for it would open the file to write nothing.
    private static func expectedBytes(_ base64: String) -> Int {
        let decoded = Data(base64Encoded: base64)?.count ?? 0
        return decoded > 0 ? decoded : -1
    }
}
