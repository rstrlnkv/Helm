import AppKit
import Foundation
import HelmRuntime

/// Silent in-app installer for ad-hoc builds. Unzips a self-downloaded app bundle
/// (no quarantine, so no Gatekeeper prompt), then hands off to a small detached
/// script that waits for this process to quit before it touches the installed
/// bundle. The running app cannot overwrite its own bundle, hence the script.
enum Installer {
    enum InstallError: Error {
        case unzipFailed, appNotFound, versionMismatch(String), notReplaceable
        /// The swap script could not be started. `HelmProcess` has already
        /// logged why; this is what the caller shows.
        case couldNotHandOver
        /// The note that says an update is in flight could not be written, so
        /// nothing was handed over. **Refusing is the safe direction here**, and
        /// is the only one available: without the note, a failed swap looks like
        /// one that worked. `UpdateHandoff.note` says the rest.
        case couldNotRecordHandover
        /// The downloaded bundle calls itself something other than what is
        /// installed here, so the swap would put one program at another's
        /// address. Refusing is the only direction available: this function has
        /// no second place to install to, and by the time the script runs there
        /// is nobody here to ask.
        case identityMismatch
        /// A prior `.helm-old` entry blocks the swap; leave it and Helm alone.
        case existingBackup
    }

    /// Unzips `zipURL`, validates the bundle, then hands off the swap and quits.
    /// Runs on the main actor, but the unzip does not: `ditto` is a blocking
    /// child process, and holding the main thread through it would freeze the
    /// Installing line. Everything that touches `Bundle.main`, `NSApp` or the
    /// swap stays on main.
    ///
    /// Installer attempts to clean up its staging directory if it does not hand
    /// it over. After handover, `UpdateSwap` attempts cleanup after a successful
    /// copy and keeps the staged payload on failure.
    ///
    /// `installedID` and `installPath` default to the running app's identity and
    /// path. `handOver` starts the swap and quits; tests substitute a recorder.
    @MainActor
    static func installZip(
        at zipURL: URL, expectedVersion: String,
        installedID: String? = Bundle.main.bundleIdentifier,
        installPath: String = Bundle.main.bundlePath,
        handOver: (_ newApp: URL, _ installPath: String, _ workDir: String, _ version: String) throws -> Void
            = { newApp, installPath, workDir, version in
                try launchSwapScript(newApp: newApp.path, installPath: installPath,
                                     workDir: workDir, version: version)
                NSApp.terminate(nil)
            }
    ) async throws {
        let fm = FileManager.default
        let work = fm.temporaryDirectory
            .appendingPathComponent("HelmUpdate-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        var handedOver = false
        defer { if !handedOver { try? fm.removeItem(at: work) } }

        // Unzip with ditto (handles the ditto-produced archive + preserves the signature).
        let zipPath = zipURL.path, workPath = work.path
        let unzipped = await offTheCooperativePool {
            HelmProcess.run("/usr/bin/ditto", ["-x", "-k", zipPath, workPath]).status
        }
        guard unzipped == 0 else { throw InstallError.unzipFailed }

        // After a successful unzip, try to remove the consumed archive.
        try? fm.removeItem(at: zipURL)

        guard let newApp = firstAppBundle(in: work, fm: fm) else { throw InstallError.appNotFound }

        // Sanity: the downloaded bundle must actually be the version we expect.
        let got = version(ofBundleAt: newApp) ?? ""
        guard accepts(version: got, build: build(ofBundleAt: newApp), expected: expectedVersion)
        else { throw InstallError.versionMismatch(got) }

        // The swap goes to the installed path, whatever is standing there, so
        // the downloaded bundle must call itself the same program that is
        // installed here: a dev build (identifier rewritten after signing) would
        // otherwise take Beta's newer release into the dev build's own address.
        guard isSameProgram(newApp, as: installedID) else {
            throw InstallError.identityMismatch
        }

        guard fm.isWritableFile(atPath: (installPath as NSString).deletingLastPathComponent)
                || fm.isWritableFile(atPath: installPath) else {
            throw InstallError.notReplaceable
        }

        // lstat sees a dangling link without following it. The script checks
        // again after quit, in case a backup appeared after this check.
        var backup = stat()
        guard lstat(installPath + UpdateSwap.asideSuffix, &backup) != 0 else {
            throw InstallError.existingBackup
        }
        // A lookup failure other than "not found" does not establish absence.
        guard errno == ENOENT else { throw InstallError.notReplaceable }

        try handOver(newApp, installPath, work.path, expectedVersion)
        handedOver = true
    }

    // MARK: - Helpers

    private static func firstAppBundle(in dir: URL, fm: FileManager) -> URL? {
        guard let items = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return nil }
        return items.first { $0.pathExtension == "app" }
    }

    private static func info(ofBundleAt app: URL) -> [String: Any]? {
        PropertyListFile.infoPlist(ofBundleAt: app)
    }

    private static func version(ofBundleAt app: URL) -> String? {
        info(ofBundleAt: app)?["CFBundleShortVersionString"] as? String
    }

    /// The build number a bundle carries, read from the same plist as its version.
    private static func build(ofBundleAt app: URL) -> String? {
        info(ofBundleAt: app)?["CFBundleVersion"] as? String
    }

    /// What a bundle on disk calls itself. Read exactly the way its version is
    /// read one function up, so the two answers come from one plist.
    static func identifier(ofBundleAt app: URL) -> String? {
        info(ofBundleAt: app)?["CFBundleIdentifier"] as? String
    }

    /// Whether the bundle calls itself the installed program. A missing
    /// identifier on either side is no match.
    static func isSameProgram(_ app: URL, as installedID: String?) -> Bool {
        guard let installedID, let got = identifier(ofBundleAt: app) else { return false }
        return got == installedID
    }

    /// Whether a downloaded bundle (its CFBundleShortVersionString and
    /// CFBundleVersion) is the release `expected` names. A build tag
    /// (`v0.11.1.BETA.1620`) names a version and a build, and a bundle carries
    /// the two apart, so both must match; a missing build refuses. Any other
    /// tag is compared with the short version alone.
    static func accepts(version: String, build: String?, expected: String) -> Bool {
        guard let tag = UpdateVersion.buildTag(expected) else {
            return sameVersion(version, expected)
        }
        return sameVersion(version, tag.core.map(String.init).joined(separator: "."))
            && build == String(tag.build)
    }

    /// Compares versions ignoring a leading "v" (tag "v0.4.0" vs bundle "0.4.0").
    private static func sameVersion(_ a: String, _ b: String) -> Bool {
        func norm(_ s: String) -> String {
            (s.hasPrefix("v") || s.hasPrefix("V")) ? String(s.dropFirst()) : s
        }
        return norm(a) == norm(b)
    }

    private static func launchSwapScript(newApp: String, installPath: String,
                                         workDir: String, version: String) throws {
        // Keep the script outside workDir: after a successful copy it attempts
        // cleanup of workDir before relaunch and removal of the script itself.
        let scriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("HelmSwap-\(UUID().uuidString).sh")
        try UpdateSwap.script.write(to: scriptURL, atomically: true, encoding: .utf8)

        // Before the spawn, because after it there is nobody here to write
        // anything: this process is about to end and the script has no screen.
        // The script removes it when the copy landed, so what a failure leaves
        // behind is the note itself (`UpdateHandoff`).
        guard UpdateHandoff.note(version: version) else {
            // Before the spawn, so there is nothing handed over to undo — only
            // the script this function just wrote, which nothing will delete
            // now that nothing will run it.
            try? FileManager.default.removeItem(at: scriptURL)
            throw InstallError.couldNotRecordHandover
        }

        // Not `HelmProcess.run`: that runner reads the child to EOF and waits
        // for its status, and this child waits for *this* process to exit.
        // `HelmProcess.start` all the same, the door that answers instead of
        // raising: an abort while Helm is replacing itself is the worst place.
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/bash")
        proc.arguments = [scriptURL.path]
            + UpdateSwap.arguments(newApp: newApp,
                                   installPath: installPath,
                                   pid: ProcessInfo.processInfo.processIdentifier,
                                   workDir: workDir,
                                   script: scriptURL.path)
        // Detach: the script must outlive this process to replace its bundle.
        proc.standardOutput = nil
        proc.standardError = nil
        guard HelmProcess.start(proc, path: "/bin/bash") else {
            // Nothing was handed over, so there is nothing for the next launch
            // to report — and a note left here would accuse a swap that never
            // happened.
            UpdateHandoff.clear()
            throw InstallError.couldNotHandOver
        }
    }
}
