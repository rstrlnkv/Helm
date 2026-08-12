// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import Foundation

/// Helm's own folder under Application Support: where durable state that is not
/// the log lives.
///
/// It was spelled out by hand in three places — `ScanJournal.defaultDirectory`
/// builds it from `FileManager`, `ResetPlan.roots` from a home directory, and the
/// VPN credential purge needed a third — which is the duplication `HelmRuntime`
/// exists to end. The two shapes are both here on purpose: a reset is a pure
/// function of somebody's home directory and has to stay testable without
/// touching this Mac's, while everything that actually writes wants the folder
/// this process should use.
public enum HelmSupport {

    /// The folder for a given home directory, as a path. `ResetPlan` names it as
    /// one of the two roots a reset may remove.
    public static func path(home: String) -> String {
        "\(home)/Library/Application Support/Helm"
    }

    /// Where a test run goes instead of into somebody's Application Support. The
    /// journal keeps its own, because its abandoned-directory sweep is written
    /// against its own prefix.
    private static let testScratch = TestScratch(prefix: "helm-support-")

    /// The folder this process should write in.
    ///
    /// A temporary directory of this process's own under a test runner — the rule
    /// `TestProcess` exists for, and `StoresOfTheirsAskIfThisIsATestTests` holds
    /// for every site that resolves a folder of the person's. In the app,
    /// `FileManager`'s own lookup, because a sandboxed or relocated home answers
    /// differently from string arithmetic; the spelled-out path is the fallback for
    /// a lookup that answers nothing at all.
    ///
    /// Resolved once, like `HelmLog.directory`: none of the three answers it is
    /// built from can change while the process lives, and the test-runner branch
    /// sweeps `$TMPDIR` for abandoned directories every time it is asked.
    public static let directory: URL = {
        if TestProcess.isRunning { return testScratch.directory() }
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask).first
        return base?.appendingPathComponent("Helm", isDirectory: true)
            ?? URL(fileURLWithPath: path(home: NSHomeDirectory()), isDirectory: true)
    }()
}
