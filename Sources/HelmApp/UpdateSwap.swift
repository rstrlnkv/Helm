// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import Foundation
import HelmRuntime

/// The handover: the shell script that replaces Helm with the copy Helm just
/// downloaded, and the note that says one is in flight.
///
/// A running app cannot overwrite its own bundle, so the last thing Helm does is
/// hand this to `/bin/bash` and quit. Everything after that happens with nobody
/// able to say a word — the app that owns the log is gone, and this script has
/// no screen — which is why what it does matters more here than anywhere else in
/// the app.
///
/// **Move aside, copy, and only then delete.** A `ditto` can refuse for any
/// reason (a full disk, a payload that will not read, a `/Applications` that
/// stopped being writable), so deleting the original first could leave no Helm
/// at all. A `ditto` into a live bundle merges into it, so the installed bundle
/// must move first. An earlier backup may be the only complete copy. Restore it
/// into an empty install path; if both paths exist, leave both alone.
///
/// **What it can report, and what it cannot.** Nothing it writes can reach a
/// screen: the report belongs to whichever Helm launches next. So the *app*
/// writes the note before it quits (`UpdateHandoff`) and the script's only
/// reporting duty is to take that note away on success — the failure is then
/// reported by an act nobody had to remember to perform, which also covers the
/// script being killed, the machine losing power, and the swap never starting.
enum UpdateSwap {

    /// Where the bundle being replaced waits until the copy is known to have
    /// landed. A sibling of the installed app, so the move is a rename inside one
    /// directory rather than a copy across volumes.
    static let asideSuffix = ".helm-old"

    /// `$1 … $6`, in the order `arguments` builds them.
    ///
    /// Quote-safe: every path arrives as a positional argument and is used
    /// quoted, never interpolated into a command line.
    static let script = """
    #!/bin/bash
    NEW="$1"; INSTALL="$2"; PID="$3"; WORK="$4"; SELF="$5"; MARK="$6"
    ASIDE="$INSTALL\(asideSuffix)"
    STATUS=1; RELAUNCH=0
    restore_original() {
      [ ! -e "$INSTALL" ] && [ ! -L "$INSTALL" ] &&
        [ -d "$ASIDE" ] && [ ! -L "$ASIDE" ] && /bin/mv "$ASIDE" "$INSTALL"
    }
    # Wait for the running Helm to exit before touching its bundle.
    while /bin/kill -0 "$PID" 2>/dev/null; do /bin/sleep 0.2; done
    /bin/sleep 0.3
    if [ -e "$ASIDE" ] || [ -L "$ASIDE" ]; then
      # The install may be partial. Do not overwrite or relaunch it.
      if restore_original; then RELAUNCH=1; fi
    elif /bin/mv "$INSTALL" "$ASIDE"; then
      if /usr/bin/ditto "$NEW" "$INSTALL"; then
        /usr/bin/xattr -cr "$INSTALL" 2>/dev/null || true
        /bin/rm -rf "$ASIDE"
        # Only now: the payload and the note are what a failure is recovered from.
        /bin/rm -rf "$WORK"
        /bin/rm -f "$MARK"
        STATUS=0; RELAUNCH=1
      elif /bin/rm -rf "$INSTALL" && restore_original; then
        RELAUNCH=1
      fi
    elif [ -d "$INSTALL" ]; then
      # The move failed; nothing was copied over the installed app.
      RELAUNCH=1
    fi
    if [ "$RELAUNCH" = 1 ]; then /usr/bin/open "$INSTALL"; fi
    /bin/rm -f "$SELF"
    exit "$STATUS"
    """

    /// The one declaration of the argument order: the script names `$1 … $6`
    /// and this builds them.
    ///
    /// The note's path is not a caller's choice — there is one — so it is read
    /// here rather than passed in and got wrong.
    static func arguments(newApp: String, installPath: String, pid: Int32,
                          workDir: String, script: String) -> [String] {
        [newApp, installPath, String(pid), workDir, script, UpdateHandoff.file.path]
    }
}

/// The note that an update was handed over and has not been seen through.
///
/// Written by the app before it quits, removed by the swap script only when the
/// copy landed, and read by whichever Helm launches afterwards. **The absence
/// of the removal is the report**, so nothing has to be written at the moment
/// things go wrong, which is the moment least able to write anything: a full
/// disk cannot record that the disk was full.
///
/// It holds the version the update was reaching for and nothing else. A path
/// would name where somebody keeps their applications, which a file that
/// only resumes an update has no use for.
enum UpdateHandoff {

    /// Beside the rest of Helm's durable state, so «Reset all settings» takes it
    /// with everything else (`ResetPlan.removablePaths`).
    static var file: URL { HelmSupport.directory.appendingPathComponent("update-handoff") }

    /// - Returns: whether the note is on disk.
    ///
    /// **A note that was not written inverts the whole arrangement.** The
    /// absence of this file *is* the report of a successful swap — the script
    /// removes it only when the copy landed — so a note that never existed says
    /// "the update worked" about an update that has not been attempted yet, and
    /// a swap that then fails is reported by nobody. There is no second chance
    /// to write it: by the time anything goes wrong this process is gone and
    /// the script has no screen.
    ///
    /// So the answer travels, and `Installer.launchSwapScript` refuses the
    /// handover on a refusal: what cannot be recorded here is the safety net
    /// under the most destructive thing this app does.
    static func note(version: String) -> Bool {
        return PrivateFile.writeMakingTheFolder(Data(version.utf8), at: file)
    }

    static func clear() {
        try? FileManager.default.removeItem(at: file)
    }

    /// The version an unfinished handover was reaching for, or nil when there
    /// was none. **Consumes it**: a note left in place would tell every launch
    /// from now on about one update that failed once.
    static func take() -> String? {
        guard let data = try? Data(contentsOf: file) else { return nil }
        clear()
        return String(bytes: data, encoding: .utf8) ?? ""
    }

    /// Said out loud at launch, once. The note records which update did not
    /// finish, not whether the swap script put the original back.
    ///
    /// - Returns: the version that did not go in, for `UpdateService` to
    ///   publish to the updates card. **Returned whether or not logging is on**:
    ///   the line is the log's to drop, the sentence on the card is not.
    @discardableResult
    static func reportAtLaunch() -> String? {
        guard let version = take() else { return nil }
        HelmLog.shared.error("update", "the update to \(version) did not finish")
        return version
    }
}
