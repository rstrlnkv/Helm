import Foundation

/// Apple's Command Line Tools as this module needs to know them: whether they
/// are on the Mac, and what one tick of the wait for them concludes. Pure — no
/// file, no process, no clock — so every rule below has a test that costs
/// nobody a download.
///
/// **Why the module waits at all.** Homebrew's `install.sh` installs the tools
/// itself only when it can ask `sudo` for a ticket on a terminal, and Helm runs
/// it with neither. So on a Mac without them Helm files Apple's own request
/// (`xcode-select --install`), Apple's window does the download, and this waits
/// for `git` to appear before the one root step and the installer run.
enum CommandLineTools {

    /// The `git` Apple's tools put at a fixed path. Its presence is the whole
    /// definition of "the tools are installed" here, because `git` is what the
    /// installer's own check for a usable one (`USABLE_GIT` in `install.sh`)
    /// asks for.
    static let git = "/Library/Developer/CommandLineTools/usr/bin/git"

    /// The `git` inside a developer directory `xcode-select -p` printed, or nil
    /// when that answer cannot name one.
    ///
    /// The tool ends its line with a newline. An empty answer and a relative one
    /// are refused: a path that is not absolute would be resolved against
    /// whatever this process's working directory happens to be.
    static func git(inDeveloperDirectory printed: String) -> String? {
        let directory = printed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard directory.hasPrefix("/") else { return nil }
        let root = directory.hasSuffix("/") ? String(directory.dropLast()) : directory
        return root + "/usr/bin/git"
    }

    /// Helm's own reading of whether `git` is there: the fixed path first, then
    /// wherever `xcode-select -p` points. It is not the script's test:
    /// `install.sh` finds `git` on the `PATH` (`find_tool`) and then under the
    /// developer directory `xcode-select --print-path` names, and looks at the
    /// fixed path only to decide whether to install the tools itself
    /// (`should_install_command_line_tools`). `selected` is lazy so that the
    /// process runs only when the fixed `git` is not there — the ordinary Mac
    /// with the tools starts nothing at all.
    static func present(isExecutable: (String) -> Bool, selected: () -> String?) -> Bool {
        if isExecutable(git) { return true }
        guard let printed = selected(), let other = git(inDeveloperDirectory: printed) else { return false }
        return isExecutable(other)
    }

    // MARK: - One tick of the wait

    /// What the wait remembers between ticks. The tick's alone: ticks are
    /// serial, because each one arms the next.
    struct Wait: Equatable {
        /// Whether Apple's installer has ever been read as running during this
        /// wait. Without it, "not running" is the state before the window has
        /// opened as much as after it has closed.
        var sawInstaller = false
        var ticks = 0
        var saidNeverSeen = false
    }

    enum Verdict: Equatable {
        case keepWaiting
        case toolsArrived
        /// Apple's window was seen and is gone, and the tools are not there:
        /// Cancel, Disagree, Stop, or a failure on Apple's side.
        case closedWithoutTools
    }

    /// Ticks without ever seeing the installer before the wait says so, once.
    /// At the engine's two-second tick that is a minute: past the time a window
    /// takes to open, and early enough for a dev round to read the line.
    static let neverSeenAfter = 30

    /// The verdict of one tick.
    ///
    /// 1. The tools are there: `toolsArrived`, whatever the installer is doing —
    ///    the «Done» button in Apple's last window is not waited for.
    /// 2. The installer is running: remember it, keep waiting.
    /// 3. It is not running but has been seen: `closedWithoutTools`.
    /// 4. It has never been seen: keep waiting. **An absence is not a failure
    ///    when no presence was ever read.** The identity the reading looks for
    ///    is a bundle id that was measured on one macOS and not the one a
    ///    person may run, and a miss must degrade to a wait that ends at Stop
    ///    waiting rather than to a false «Failed» over a window still open.
    /// 5. After `neverSeenAfter` ticks of that, `sayNeverSeen` is true exactly
    ///    once, and the engine logs it — the line a dev round finds the wrong
    ///    identity by.
    static func next(_ wait: Wait, toolsPresent: Bool, installerRunning: Bool)
    -> (wait: Wait, verdict: Verdict, sayNeverSeen: Bool) {
        var wait = wait
        wait.ticks += 1
        if toolsPresent { return (wait, .toolsArrived, false) }
        if installerRunning {
            wait.sawInstaller = true
            return (wait, .keepWaiting, false)
        }
        if wait.sawInstaller { return (wait, .closedWithoutTools, false) }
        let say = wait.ticks >= neverSeenAfter && !wait.saidNeverSeen
        if say { wait.saidNeverSeen = true }
        return (wait, .keepWaiting, say)
    }
}
