import Darwin
import Foundation
import HelmRuntime

/// A child on a pseudo-terminal, and the one secret this app holds in memory.
///
/// **Why a pty at all.** `ssh-keygen -N '<passphrase>'` puts the passphrase in
/// `ps auxww` for every process on the machine to read — the same defect as a
/// staged path in a privileged sentence, one argument over. `ssh-add` on an
/// encrypted key has the identical problem. So the passphrase is never an
/// argument: the child is given a terminal, it asks the way it asks a person,
/// and the answer is written to the master end.
///
/// **What the secret never touches.** Not `argv`, not the environment, not a
/// file, not the log. It is `Data` the caller owns, written once per prompt and
/// then zeroed — `zero(_:)` below is called on every exit from `run`, including
/// the timeout and the spawn failure.
///
/// `SSH_ASKPASS` with `SSH_ASKPASS_REQUIRE=force` was considered and is worse:
/// it adds an executable to the bundle that has to be signed with it, and it
/// still needs a channel to hand that helper the secret.
///
/// This starts in the module. It moves to `HelmRuntime` when a second module
/// spells it — that is the rule, and the list of things written twice before
/// they moved is long enough to trust it.
enum PTYProcess {

    struct Result: Sendable {
        let status: Int32
        /// Everything the child wrote, prompts included. **Never logged whole**
        /// — a caller that wants a line out of it takes the line.
        let output: String
        init(status: Int32, output: String) {
            self.status = status
            self.output = output
        }
    }

    /// The status of a run whose deadline passed. Distinguishable from anything
    /// a child can produce, the way `HelmProcess.timedOutStatus` is: exit codes
    /// are 0…255, a signal death reports the signal, and -1 is a failed spawn.
    static let timedOutStatus: Int32 = -2
    /// The status when the terminal or the spawn itself could not be had.
    static let couldNotStartStatus: Int32 = -1

    /// Run `path` with `arguments` on a pty, answering every passphrase prompt
    /// with `secret`.
    ///
    /// `secret` is zeroed before this returns, on every path out. A caller that
    /// needs it twice keeps its own copy and is responsible for that copy.
    ///
    /// **The prompt is matched, not counted.** `ssh-keygen` asks twice — once
    /// for the passphrase and once to confirm it — and `ssh-add` asks once, and
    /// both wordings have changed across macOS releases. What does not change is
    /// that the word «passphrase» is in the question, so each read that contains
    /// it and has not yet been answered gets one answer.
    static func run(_ path: String, _ arguments: [String],
                           answering secret: inout Data,
                           timeout: TimeInterval = 60) -> Result {
        defer { zero(&secret) }

        var master: Int32 = -1
        var slave: Int32 = -1
        guard openTerminal(&master, &slave) else {
            return Result(status: couldNotStartStatus, output: "")
        }
        defer {
            if master >= 0 { close(master) }
            if slave >= 0 { close(slave) }
        }

        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        // The child's three descriptors are the terminal, and the master end is
        // not among them: a child holding the master would keep the read below
        // from ever seeing EOF.
        posix_spawn_file_actions_adddup2(&actions, slave, 0)
        posix_spawn_file_actions_adddup2(&actions, slave, 1)
        posix_spawn_file_actions_adddup2(&actions, slave, 2)
        posix_spawn_file_actions_addclose(&actions, master)

        var attributes: posix_spawnattr_t?
        posix_spawnattr_init(&attributes)
        defer { posix_spawnattr_destroy(&attributes) }
        // **Its own session.** `readpassphrase` opens `/dev/tty` and wants a
        // controlling terminal; a child in this process's session would find
        // Helm's — which is nothing at all in a bundled app — and fall back to
        // whatever stdin happens to be.
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETSID))

        var pid: pid_t = 0
        let argv: [String] = [path] + arguments
        var pointers: [UnsafeMutablePointer<CChar>?] = argv.map { strdup($0) }
        pointers.append(nil)
        defer { for pointer in pointers where pointer != nil { free(pointer) } }

        guard posix_spawn(&pid, path, &actions, &attributes, &pointers, environ) == 0 else {
            return Result(status: couldNotStartStatus, output: "")
        }

        // The slave is closed here and only here: while this process holds it,
        // the master never reads EOF even after the child has gone.
        close(slave)
        slave = -1

        return converse(with: pid, on: master, secret: secret, timeout: timeout)
    }

    /// Read until the child is done, answering each prompt that asks for a
    /// passphrase.
    private static func converse(with pid: pid_t, on master: Int32,
                                 secret: Data, timeout: TimeInterval) -> Result {
        var output = ""
        var buffer = [UInt8](repeating: 0, count: 4096)
        let deadline = Date().addingTimeInterval(timeout)
        var answered = 0

        while true {
            let left = deadline.timeIntervalSinceNow
            guard left > 0 else {
                kill(pid, SIGKILL)
                var ignored: Int32 = 0
                waitpid(pid, &ignored, 0)
                return Result(status: timedOutStatus, output: output)
            }

            var descriptor = pollfd(fd: master, events: Int16(POLLIN), revents: 0)
            let ready = poll(&descriptor, 1, Int32(min(left, 1) * 1000))
            if ready < 0 && errno == EINTR { continue }
            if ready > 0 {
                let read = Darwin.read(master, &buffer, buffer.count)
                // EOF, or the far end went away — on macOS a pty master reads
                // EIO rather than 0 once the last slave is closed, and both mean
                // the same thing here.
                if read <= 0 { break }
                let chunk = String(decoding: buffer[0..<read], as: UTF8.self)
                output += chunk
                if chunk.lowercased().contains("passphrase") {
                    answer(secret, on: master)
                    answered += 1
                }
            }

            // A child that has exited with nothing left to read is done. Asked
            // after the read, so the last chunk is never dropped.
            var status: Int32 = 0
            if waitpid(pid, &status, WNOHANG) == pid {
                return Result(status: exitStatus(status), output: output)
            }
        }

        var status: Int32 = 0
        waitpid(pid, &status, 0)
        return Result(status: exitStatus(status), output: output)
    }

    /// One answer, and the newline the prompt is waiting for.
    ///
    /// The bytes are written from the caller's own buffer — no `String` is made
    /// of them anywhere in this file, because a `String` is a copy this code
    /// cannot zero.
    private static func answer(_ secret: Data, on master: Int32) {
        secret.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress, bytes.count > 0 else { return }
            var written = 0
            while written < bytes.count {
                let n = write(master, base.advanced(by: written), bytes.count - written)
                if n <= 0 { break }
                written += n
            }
        }
        var newline: UInt8 = 0x0A
        _ = write(master, &newline, 1)
    }

    /// `posix_openpt` rather than `openpty`, because the four calls are the
    /// thing being reasoned about and one of them can fail on its own.
    private static func openTerminal(_ master: inout Int32, _ slave: inout Int32) -> Bool {
        master = posix_openpt(O_RDWR | O_NOCTTY)
        guard master >= 0, grantpt(master) == 0, unlockpt(master) == 0,
              let name = ptsname(master) else { return false }
        slave = open(name, O_RDWR)
        guard slave >= 0 else { return false }
        silence(slave)
        return true
    }

    /// **Echo off, before the child is spawned.**
    ///
    /// A terminal echoes what is written to it, so without this the passphrase
    /// comes straight back in `output` — measured, against a child that reads
    /// with `sh`'s own `read`: the transcript read «Enter passphrase: hunter2».
    /// `ssh-keygen` clears echo itself while it asks, and this must not depend
    /// on that: the tool's own habits are not a property this code can hold, and
    /// a transcript is a thing callers log lines out of.
    ///
    /// `ECHONL` goes with the other three because it echoes the newline even
    /// when `ECHO` is off, which is enough to tell somebody reading the
    /// transcript where an answer was given.
    private static func silence(_ terminal: Int32) {
        var settings = termios()
        guard tcgetattr(terminal, &settings) == 0 else { return }
        settings.c_lflag &= ~tcflag_t(ECHO | ECHOE | ECHOK | ECHONL)
        tcsetattr(terminal, TCSANOW, &settings)
    }

    /// Overwrite the bytes and drop them. `resetBytes` writes through the
    /// buffer rather than replacing the value, which is the difference between
    /// zeroing a secret and abandoning one.
    ///
    /// **The range is the value's own indices, not `0..<count`.** A `Data` that
    /// is a *slice* does not start at zero: its `startIndex` is wherever the
    /// slice begins, so `0..<count` writes over bytes in front of it and leaves
    /// its own tail — the part still holding the passphrase — untouched. No
    /// caller here hands over a slice today, which is why nothing has caught
    /// it; one `dropFirst` anywhere upstream is all it would take.
    private static func zero(_ secret: inout Data) {
        secret.resetBytes(in: secret.startIndex..<secret.endIndex)
        secret = Data()
    }

    private static func exitStatus(_ raw: Int32) -> Int32 {
        // The child that was signalled reports the signal, the way
        // `HelmProcess` does, so a caller can tell a refusal from a killing.
        (raw & 0x7F) == 0 ? (raw >> 8) & 0xFF : (raw & 0x7F)
    }
}
