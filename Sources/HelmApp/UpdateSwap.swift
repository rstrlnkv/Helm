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
/// **Move aside, copy, and only then delete.** It used to `rm -rf` the installed
/// bundle and copy the new one into the hole, reading no status: a `ditto` that
/// refused for any reason — a full disk, a payload that will not read, a
/// `/Applications` that stopped being writable in the second since it was asked
/// — left the person with no Helm at all. The downloaded zip is deleted before
/// the handover (`Installer.installZip`) and the unzipped payload lives in a
/// directory the script removes, so there was nothing anywhere to go back to.
///
/// **What it can report, and what it cannot.** Nothing it writes can reach a
/// screen: the report belongs to whichever Helm launches next, which is the new
/// one when the swap worked and the old one when it did not. So the *app*
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
    STATUS=0
    # Wait for the running Helm to exit before touching its bundle.
    while /bin/kill -0 "$PID" 2>/dev/null; do /bin/sleep 0.2; done
    /bin/sleep 0.3
    # An earlier attempt's copy would make the move below fail before it started.
    /bin/rm -rf "$ASIDE"
    if /bin/mv "$INSTALL" "$ASIDE"; then
      if /usr/bin/ditto "$NEW" "$INSTALL"; then
        /usr/bin/xattr -cr "$INSTALL" 2>/dev/null || true
        /bin/rm -rf "$ASIDE"
        # Only now: the payload and the note are what a failure is recovered from.
        /bin/rm -rf "$WORK"
        /bin/rm -f "$MARK"
      else
        /bin/rm -rf "$INSTALL"
        /bin/mv "$ASIDE" "$INSTALL"
        STATUS=1
      fi
    else
      # The bundle could not be moved out of the way, so nothing is copied over
      # it: a ditto into a live bundle merges into it, which is how a half-new,
      # half-old Helm gets made.
      STATUS=1
    fi
    # Whichever bundle is there now — the new one, or the one put back.
    /usr/bin/open "$INSTALL"
    /bin/rm -f "$SELF"
    exit "$STATUS"
    """

    /// The one declaration of the argument order. The script names `$1 … $6` and
    /// this builds them; a caller that assembled its own array would be the
    /// second spelling of an order only one side could change.
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
/// copy landed, and read by whichever Helm launches afterwards — the new one if
/// the swap worked, the one that was put back if it did not. **The absence of
/// the removal is the report**, so nothing has to be written at the moment
/// things go wrong, which is the moment least able to write anything: a full
/// disk cannot record that the disk was full.
///
/// It holds the version the update was reaching for and nothing else. A path
/// would name where somebody keeps their applications, and the log carries no
/// names.
enum UpdateHandoff {

    /// Beside the rest of Helm's durable state, so «Reset all settings» takes it
    /// with everything else (`ResetPlan.roots`).
    static var file: URL { HelmSupport.directory.appendingPathComponent("update-handoff") }

    static func note(version: String) {
        PrivateFile.directory(at: HelmSupport.directory)
        PrivateFile.write(Data(version.utf8), to: file)
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

    /// Said out loud at launch, once. There is no sentence on screen for this
    /// yet — writing one is the localizer's, in all eight languages — and a log
    /// line is what the app can honestly offer today: the person has the version
    /// they already had, and the trail says which one did not go in.
    static func reportAtLaunch() {
        guard let version = take() else { return }
        HelmLog.shared.error("update",
                             "the update to \(version) did not finish; this copy is the "
                             + "one that was already installed")
    }
}
