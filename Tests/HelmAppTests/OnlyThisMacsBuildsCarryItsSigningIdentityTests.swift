import XCTest
import HelmTestSupport

/// **A build made on this Mac may carry this Mac's signing identity; a release
/// may not.**
///
/// An ad-hoc build is a new program to TCC and the keychain on every rebuild,
/// so each install cost the grants and one keychain dialog per item, per build,
/// per app — counted 2026-09-17, four to five dialogs a build across two apps.
/// `Scripts/signing-identity.sh` lets this Mac name a certificate of its own,
/// and `Scripts/make-zip.sh` and `Scripts/make-dmg.sh` refuse any bundle not
/// signed ad-hoc, because that key lives on one machine and every user's grants
/// would hang on it.
///
/// Run for real, with a `codesign` stub on the path and a scratch `HOME` and
/// `TMPDIR`, so neither this Mac's identity nor its staged bundle is read.
final class OnlyThisMacsBuildsCarryItsSigningIdentityTests: XCTestCase {

    private struct Run {
        let status: Int32
        let output: String
        let errors: String
    }

    private func script(_ name: String) -> URL {
        RepoSource.root.appendingPathComponent("Scripts/\(name)")
    }

    private func run(_ script: URL, env: [String: String]) throws -> Run {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/bash")
        proc.arguments = [script.path]
        proc.environment = env
        let out = Pipe(), err = Pipe()
        proc.standardOutput = out
        proc.standardError = err
        try proc.run()
        let output = out.fileHandleForReading.readDataToEndOfFile()
        let errors = err.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        return Run(status: proc.terminationStatus,
                   output: String(decoding: output, as: UTF8.self),
                   errors: String(decoding: errors, as: UTF8.self))
    }

    // MARK: - Which identity a build on this Mac takes

    private func identity(home: URL, override: String? = nil) throws -> String {
        var env = ["PATH": "/usr/bin:/bin", "HOME": home.path]
        if let override { env["HELM_SIGN_IDENTITY"] = override }
        let result = try run(script("signing-identity.sh"), env: env)
        XCTAssertEqual(result.status, 0, result.errors)
        return result.output.trimmingCharacters(in: .newlines)
    }

    private func homeNaming(_ name: String?) throws -> URL {
        let home = scratchDirectory("signing-home")
        if let name {
            let folder = home.appendingPathComponent(".config/helm")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try (name + "\n").write(to: folder.appendingPathComponent("signing-identity"),
                                    atomically: true, encoding: .utf8)
        }
        return home
    }

    func testAMacThatNamesNoIdentitySignsAdHoc() throws {
        XCTAssertEqual(try identity(home: try homeNaming(nil)), "-")
    }

    func testAMacThatNamesAnIdentitySignsWithIt() throws {
        XCTAssertEqual(try identity(home: try homeNaming("Helm Local Signing")), "Helm Local Signing",
                       "the certificate this Mac names is not the one its builds are signed with")
    }

    /// The override is how a release is packaged on a Mac that has a local
    /// identity; an empty one means ad-hoc too, never "fall back to the file".
    func testTheOverrideForcesAdHocOverTheFile() throws {
        let home = try homeNaming("Helm Local Signing")
        XCTAssertEqual(try identity(home: home, override: "-"), "-")
        XCTAssertEqual(try identity(home: home, override: ""), "-",
                       "an empty override fell through to this Mac's identity")
    }

    // MARK: - What a release refuses

    /// A staged bundle and a `codesign` stub that verifies it and describes its
    /// signature as `signature`.
    private func release(_ scriptName: String, signature: String) throws -> Run {
        let tmp = scratchDirectory("release-tmp")
        let app = tmp.appendingPathComponent("helm-package/Helm.app/Contents")
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)

        let bin = scratchDirectory("release-stub-bin")
        let stub = bin.appendingPathComponent("codesign")
        try """
            #!/bin/bash
            if [ "$1" = "-dv" ]; then echo "Executable=/x"; echo "\(signature)" >&2; exit 0; fi
            exit 0
            """.write(to: stub, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: stub.path)
        // No Info.plist: the version read that comes after the guard fails, so
        // a script the guard wrongly let through stops before it packs anything.

        return try run(script(scriptName), env: ["PATH": "\(bin.path):/usr/bin:/bin",
                                                 "TMPDIR": tmp.path,
                                                 "HOME": scratchDirectory("release-home").path])
    }

    func testAReleaseRefusesABundleSignedWithALocalIdentity() throws {
        for name in ["make-zip.sh", "make-dmg.sh"] {
            let local = try release(name, signature: "Signature=size=9000")
            XCTAssertNotEqual(local.status, 0, "\(name) packed a bundle signed with this Mac's identity")
            XCTAssertTrue(local.errors.contains("local identity"), """
                \(name) stopped for some other reason, so this says nothing about the guard: \
                \(local.errors)
                """)

            // The subject: the same script with an ad-hoc bundle gets past the
            // guard and stops later, at the version read.
            let adHoc = try release(name, signature: "Signature=adhoc")
            XCTAssertFalse(adHoc.errors.contains("local identity"),
                           "\(name) refused an ad-hoc bundle as though it carried an identity")
        }
    }
}
