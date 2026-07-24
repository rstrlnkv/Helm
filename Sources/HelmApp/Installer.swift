import AppKit
import Foundation

/// Silent in-app installer for ad-hoc builds. Unzips a self-downloaded app bundle
/// (no quarantine, so no Gatekeeper prompt), then hands off to a small detached
/// script that waits for this process to quit, swaps the bundle in place, and
/// relaunches. The running app cannot overwrite its own bundle, hence the script.
enum Installer {
    enum InstallError: Error { case unzipFailed, appNotFound, versionMismatch(String), notReplaceable }

    /// Unzips `zipURL`, validates the bundle, then swaps + relaunches (terminates the app).
    /// Runs on the main actor; the work is quick for a ~2 MB archive.
    @MainActor
    static func installZip(at zipURL: URL, expectedVersion: String) throws {
        let fm = FileManager.default
        let work = fm.temporaryDirectory
            .appendingPathComponent("HelmUpdate-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: work, withIntermediateDirectories: true)

        // Unzip with ditto (handles the ditto-produced archive + preserves the signature).
        let unzip = Process()
        unzip.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        unzip.arguments = ["-x", "-k", zipURL.path, work.path]
        try unzip.run()
        unzip.waitUntilExit()
        guard unzip.terminationStatus == 0 else { throw InstallError.unzipFailed }

        guard let newApp = firstAppBundle(in: work, fm: fm) else { throw InstallError.appNotFound }

        // Sanity: the downloaded bundle must actually be the version we expect.
        let got = version(ofBundleAt: newApp) ?? ""
        guard sameVersion(got, expectedVersion) else { throw InstallError.versionMismatch(got) }

        let installPath = Bundle.main.bundlePath
        guard fm.isWritableFile(atPath: (installPath as NSString).deletingLastPathComponent)
                || fm.isWritableFile(atPath: installPath) else {
            throw InstallError.notReplaceable
        }

        try launchSwapScript(newApp: newApp.path, installPath: installPath, work: work)
        NSApp.terminate(nil)
    }

    // MARK: - Helpers

    private static func firstAppBundle(in dir: URL, fm: FileManager) -> URL? {
        guard let items = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return nil }
        return items.first { $0.pathExtension == "app" }
    }

    private static func version(ofBundleAt app: URL) -> String? {
        let plist = app.appendingPathComponent("Contents/Info.plist")
        guard let dict = NSDictionary(contentsOf: plist) else { return nil }
        return dict["CFBundleShortVersionString"] as? String
    }

    /// Compares versions ignoring a leading "v" (tag "v0.4.0" vs bundle "0.4.0").
    private static func sameVersion(_ a: String, _ b: String) -> Bool {
        func norm(_ s: String) -> String {
            (s.hasPrefix("v") || s.hasPrefix("V")) ? String(s.dropFirst()) : s
        }
        return norm(a) == norm(b)
    }

    private static func launchSwapScript(newApp: String, installPath: String, work: URL) throws {
        let scriptURL = work.appendingPathComponent("swap.sh")
        let pid = ProcessInfo.processInfo.processIdentifier
        // Quote-safe: paths are passed as positional args, not interpolated into commands.
        let script = """
        #!/bin/bash
        NEW="$1"; INSTALL="$2"; PID="$3"
        # Wait for the running Helm to exit before touching its bundle.
        while /bin/kill -0 "$PID" 2>/dev/null; do /bin/sleep 0.2; done
        /bin/sleep 0.3
        /bin/rm -rf "$INSTALL"
        /usr/bin/ditto "$NEW" "$INSTALL"
        /usr/bin/xattr -cr "$INSTALL" 2>/dev/null || true
        /usr/bin/open "$INSTALL"
        """
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/bash")
        proc.arguments = [scriptURL.path, newApp, installPath, String(pid)]
        // Detach: the script must outlive this process (it swaps + relaunches us).
        proc.standardOutput = nil
        proc.standardError = nil
        try proc.run()
    }
}
