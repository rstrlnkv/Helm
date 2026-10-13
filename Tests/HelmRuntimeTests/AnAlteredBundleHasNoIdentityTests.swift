// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import HelmTestSupport
import Security
import XCTest
@testable import HelmRuntime

/// **A bundle whose content changed after it was signed is not who its signature
/// says it is.**
///
/// `CodeIdentity.of(bundleAt:)` reads the signing and team identifiers out of the
/// signature with `SecCodeCopySigningInformation`, and first asks
/// `SecStaticCodeCheckValidity` whether that signature still matches the code it
/// covers. The first two rows hold it to that: each signs a bundle ad hoc in a
/// scratch directory, changes **one byte outside the signature** and reads the
/// identity again, and no identity may come back.
///
/// A row only means something if the situation is real, so each of the two
/// establishes it first with readers that are not the subject —
/// `SecStaticCodeCheckValidity` and `codesign --verify`, both asked by this test —
/// and says nothing about the identity unless the untouched bundle is intact and
/// has an identity, and the altered one is not intact. A row that cannot establish
/// that fails as «void», which is a different message from the one the assertion
/// about the identity prints.
///
/// Every row prints what it read, one line per stage, so a run can be read from its
/// log without this source: `[altered-bundle] row=… stage=… identity=…
/// SecStaticCodeCheckValidity=… codesign-verify=…`.
///
/// The last two rows are the neighbour on the other side of the check, and they sit
/// here because they use this file's reader and its bundle: a bundle **nobody
/// signed** is not a bundle whose signature stopped matching, and what
/// `CodeIdentity.of(bundleAt:)` hands back for it — an identity with no signing
/// identifier, which is not nil — is what VPN's «this app is not signed» row stands
/// on. They fail if the check that refuses an altered bundle also swallows that.
final class AnAlteredBundleHasNoIdentityTests: XCTestCase {

    private static let identifier = "com.helm.test.altered"

    /// What three readers said about one bundle at one moment. Each reading builds
    /// its own `SecStaticCode`, so none of them can answer from another's object.
    private struct Reading {
        let created: OSStatus
        let validity: OSStatus
        let codesignExit: Int32
        let codesignLine: String
        let identity: CodeIdentity?

        /// Both independent readers agree the bundle is whole.
        var intact: Bool { validity == errSecSuccess && codesignExit == 0 }

        /// The system did read it as signed code, and the content did not match.
        /// An unsigned bundle, a file that is not a Mach-O and a path that is not
        /// there are all non-zero too, and none of them is an altered signature.
        var altered: Bool {
            let notAnAlteration: [OSStatus] = [errSecCSUnsigned, errSecCSBadObjectFormat,
                                               errSecCSStaticCodeNotFound]
            return created == errSecSuccess && validity != errSecSuccess
                && !notAnAlteration.contains(validity) && codesignExit != 0
        }

        /// The system did read it as code, and found no signature on it at all —
        /// neither «intact» nor «changed after signing», and of the statuses
        /// `altered` sets aside the one the last two rows are about.
        var unsigned: Bool {
            created == errSecSuccess && validity == errSecCSUnsigned && codesignExit != 0
        }

        var description: String {
            let who = identity.map {
                "signingID=\($0.signingID ?? "nil") teamID=\($0.teamID ?? "nil")"
            } ?? "nil"
            let words = SecCopyErrorMessageString(validity, nil) as String? ?? "?"
            return "identity=\(who) SecStaticCodeCheckValidity=\(validity) (\(words)) "
                + "codesign-verify=exit \(codesignExit) \"\(codesignLine)\""
        }
    }

    private struct MeasurementVoid: Error, CustomStringConvertible {
        let description: String
    }

    private func read(_ app: URL) -> Reading {
        var code: SecStaticCode?
        let created = SecStaticCodeCreateWithPath(app as CFURL, [], &code)
        var validity = created
        if created == errSecSuccess, let code {
            validity = SecStaticCodeCheckValidity(code, [], nil)
        }
        // `HelmProcess` sends stderr to the null device, and `codesign` says
        // everything there: the shell merges it into the one stream that is read.
        let verified = HelmProcess.run(
            "/bin/sh", ["-c", "exec \"$0\" \"$@\" 2>&1", "/usr/bin/codesign",
                        "--verify", "--strict", app.path],
            timeout: 30)
        let line = verified.output.split(separator: "\n").last.map(String.init) ?? ""
        return Reading(created: created, validity: validity,
                       codesignExit: verified.status,
                       codesignLine: line.replacingOccurrences(of: app.path, with: "<app>"),
                       identity: CodeIdentity.of(bundleAt: app))
    }

    /// A bundle shaped like `package-app.sh`'s output, signed ad hoc where it
    /// stands. `executable` writes the main executable.
    private func signedBundle(in root: URL, executable: (URL) throws -> Void) throws -> URL {
        let app = try bareBundle(in: root, name: "Altered", executable: executable)
        let signed = HelmProcess.run("/usr/bin/codesign",
                                     ["--force", "--sign", "-",
                                      "--identifier", Self.identifier, app.path],
                                     timeout: 30)
        guard signed.status == 0 else {
            throw MeasurementVoid(description: "codesign exited \(signed.status) on the fixture")
        }
        return app
    }

    /// The same bundle with nobody's signature on it: no `codesign` run, so no
    /// `_CodeSignature` folder. Its `Info.plist` still claims the identifier, as
    /// any unsigned app's does, which is the one string a reader must not take for
    /// who the code is.
    private func bareBundle(in root: URL, name: String,
                            executable: (URL) throws -> Void) throws -> URL {
        let app = root.appendingPathComponent("\(name).app")
        let macOS = app.appendingPathComponent("Contents/MacOS")
        try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)
        try """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" \
            "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0"><dict>
            <key>CFBundleIdentifier</key><string>\(Self.identifier)</string>
            <key>CFBundleExecutable</key><string>\(name)</string>
            <key>CFBundleShortVersionString</key><string>0.9.0</string>
            <key>CFBundleVersion</key><string>405</string>
            </dict></plist>
            """.write(to: app.appendingPathComponent("Contents/Info.plist"),
                      atomically: true, encoding: .utf8)
        try executable(macOS.appendingPathComponent(name))
        return app
    }

    /// Flip the lowest bit of the byte at `offset` and read it back, so the line
    /// the row prints is what the file holds.
    private func flipByte(in file: URL, at offset: Int) throws -> (old: UInt8, new: UInt8) {
        let handle = try FileHandle(forUpdating: file)
        defer { try? handle.close() }
        try handle.seek(toOffset: UInt64(offset))
        guard let old = try handle.read(upToCount: 1)?.first else {
            throw MeasurementVoid(description: "offset \(offset) is past the end of \(file.lastPathComponent)")
        }
        let new = old ^ 0x01
        try handle.seek(toOffset: UInt64(offset))
        try handle.write(contentsOf: Data([new]))
        let held = try Data(contentsOf: file)[offset]
        guard held == new else {
            throw MeasurementVoid(description: "the byte at \(offset) reads \(held) after writing \(new)")
        }
        return (old, new)
    }

    /// The measurement itself: untouched, then altered, each printed, each judged
    /// by the readers that are not the subject before the subject is judged.
    private func measure(_ row: String, app: URL, alter: () throws -> String) throws {
        let untouched = read(app)
        print("[altered-bundle] row=\(row) stage=untouched \(untouched.description)")
        guard untouched.intact, untouched.identity?.signingID == Self.identifier else {
            XCTFail("""
                MEASUREMENT VOID: the untouched fixture is not an intact bundle with an identity \
                (\(untouched.description)), so a nil below would mean nothing
                """)
            return
        }

        let alteration = try alter()
        print("[altered-bundle] row=\(row) stage=altered alteration=\(alteration)")
        let altered = read(app)
        print("[altered-bundle] row=\(row) stage=altered \(altered.description)")
        guard altered.altered else {
            XCTFail("""
                MEASUREMENT VOID: after the alteration the system does not say the content \
                differs from its signature (\(altered.description)), so «identity back» could be \
                an alteration that never broke anything
                """)
            return
        }

        XCTAssertNil(altered.identity, """
            CodeIdentity.of(bundleAt:) handed back \(altered.identity.map { "\($0)" } ?? "nil") for \
            a bundle the system itself calls invalid (\(altered.description)); an identity read \
            from a signature that does not match its content is somebody's claim, not a fact
            """)
        print("[altered-bundle] row=\(row) verdict="
              + (altered.identity == nil ? "no identity for the altered bundle"
                                         : "IDENTITY HANDED BACK for the altered bundle"))
    }

    /// The measurement for a bundle nobody signed: the subject first, judged by
    /// readers that are not `CodeIdentity`, then what `CodeIdentity` handed back.
    private func measureUnsigned(_ row: String, app: URL) {
        let reading = read(app)
        let folder = FileManager.default.fileExists(
            atPath: app.appendingPathComponent("Contents/_CodeSignature").path)
        print("[altered-bundle] row=\(row) stage=unsigned "
              + "_CodeSignature=\(folder ? "present" : "absent") \(reading.description)")
        guard reading.unsigned, !folder else {
            XCTFail("""
                MEASUREMENT VOID: the fixture is not a bundle nobody signed \
                (_CodeSignature \(folder ? "present" : "absent"), \(reading.description)), so what \
                CodeIdentity hands back below would say nothing about an unsigned bundle
                """)
            return
        }

        let verdict: String
        if let identity = reading.identity {
            verdict = identity.isVerifiable ? "VERIFIABLE IDENTITY handed back for an unsigned bundle"
                                            : "identity handed back, not verifiable"
        } else {
            verdict = "NIL handed back for an unsigned bundle"
        }
        print("[altered-bundle] row=\(row) verdict=\(verdict)")

        let said = reading.identity.map { "\($0)" } ?? "nil"
        XCTAssertNotNil(reading.identity, """
            CodeIdentity.of(bundleAt:) handed back nil for a bundle nobody signed \
            (\(reading.description)); VPN reads an identity that is not verifiable as «this app \
            is not signed» and shows it on the row, and reads nil as «nothing to record» and says \
            nothing
            """)
        XCTAssertNil(reading.identity?.signingID,
                     "an unsigned bundle has no signing identifier, and the plist's is not one: \(said)")
        XCTAssertNil(reading.identity?.teamID, "an unsigned bundle has no team identifier: \(said)")
        XCTAssertEqual(reading.identity?.isVerifiable, false,
                       "an unsigned bundle's identity must not be one to compare against: \(said)")
    }

    // MARK: - The rows

    /// A signed copy of a system binary — a real Mach-O, as an application's main
    /// executable is — with one byte of its code changed after signing.
    func testAMachOBundleAlteredAfterSigningHasNoIdentity() throws {
        let root = scratchDirectory("altered-macho")
        let app = try signedBundle(in: root) { destination in
            // Thin, so that "the architecture the system reads" is not a question,
            // and re-signed in the bundle, so the original signature is not the one.
            #if arch(arm64)
            let arch = "arm64e"
            #else
            let arch = "x86_64"
            #endif
            let thin = HelmProcess.run("/usr/bin/lipo",
                                       ["-thin", arch, "/usr/bin/true", "-output", destination.path],
                                       timeout: 30)
            guard thin.status == 0 else {
                throw MeasurementVoid(description: "lipo exited \(thin.status) extracting \(arch)")
            }
        }
        let binary = app.appendingPathComponent("Contents/MacOS/Altered")
        let layout = try XCTUnwrap(MachOLayout(try Data(contentsOf: binary)),
                                   "the fixture is not a thin 64-bit Mach-O with a __text section and a signature")
        let offset = layout.textOffset + layout.textSize / 2

        try measure("macho-code-byte", app: app) {
            guard offset < layout.signatureOffset else {
                throw MeasurementVoid(description: "byte \(offset) is inside the signature at \(layout.signatureOffset)")
            }
            let (old, new) = try flipByte(in: binary, at: offset)
            return "Contents/MacOS/Altered offset \(offset) of \(layout.fileSize) "
                + "(__text \(layout.textOffset)..<\(layout.textOffset + layout.textSize), "
                + "signature starts at \(layout.signatureOffset)) "
                + "old=0x\(String(old, radix: 16)) new=0x\(String(new, radix: 16))"
        }
    }

    /// A bundle whose main executable is a script — the shape the neighbouring
    /// family builds — with one byte of the script changed after signing. A script
    /// carries no signature of its own, so everything the signature says lives in
    /// the bundle's `_CodeSignature` folder, beside the content it covers and apart
    /// from it.
    func testAScriptBundleAlteredAfterSigningHasNoIdentity() throws {
        let script = "#!/bin/sh\necho one\n"
        let root = scratchDirectory("altered-script")
        let app = try signedBundle(in: root) { destination in
            try script.write(to: destination, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755],
                                                  ofItemAtPath: destination.path)
        }
        let executable = app.appendingPathComponent("Contents/MacOS/Altered")
        // The last letter of «one»: `echo one` becomes `echo ond`.
        let offset = script.utf8.count - 2

        try measure("script-byte", app: app) {
            let (old, new) = try flipByte(in: executable, at: offset)
            return "Contents/MacOS/Altered offset \(offset) of \(script.utf8.count) "
                + "(signature is in Contents/_CodeSignature, a different file) "
                + "old=0x\(String(old, radix: 16)) new=0x\(String(new, radix: 16))"
        }
    }

    // MARK: - The neighbour: a bundle nobody signed

    /// A bundle nobody signed is not one whose signature stopped matching, and the
    /// answer for it must not move with the check above: an identity that is not
    /// there to compare against (`isVerifiable` false), not nil. VPN tells the two
    /// apart — it keeps a rule for the first and the row says the app is not signed,
    /// while for nil it records nothing and says nothing. The main executable is a
    /// script with no `_CodeSignature` beside it, the plain case; the plist claims
    /// `com.helm.test.altered`, and the identity must not be that.
    func testAScriptBundleNobodySignedHasAnIdentityThatIsNotVerifiable() throws {
        let root = scratchDirectory("unsigned-script")
        let app = try bareBundle(in: root, name: "Unsigned") { destination in
            try "#!/bin/sh\necho one\n".write(to: destination, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755],
                                                  ofItemAtPath: destination.path)
        }
        measureUnsigned("script-unsigned", app: app)
    }

    /// The same for a real Mach-O: a thin copy of a system binary with the
    /// signature it carried taken off, because a copy that merely skipped
    /// `codesign --sign` still holds Apple's.
    func testAMachOBundleWithItsSignatureRemovedHasAnIdentityThatIsNotVerifiable() throws {
        let root = scratchDirectory("unsigned-macho")
        let app = try bareBundle(in: root, name: "Unsigned") { destination in
            #if arch(arm64)
            let arch = "arm64e"
            #else
            let arch = "x86_64"
            #endif
            let thin = HelmProcess.run("/usr/bin/lipo",
                                       ["-thin", arch, "/usr/bin/true", "-output", destination.path],
                                       timeout: 30)
            guard thin.status == 0 else {
                throw MeasurementVoid(description: "lipo exited \(thin.status) extracting \(arch)")
            }
            let removed = HelmProcess.run("/usr/bin/codesign",
                                          ["--remove-signature", destination.path], timeout: 30)
            guard removed.status == 0 else {
                throw MeasurementVoid(description: "codesign --remove-signature exited \(removed.status)")
            }
        }
        measureUnsigned("macho-unsigned", app: app)
    }
}

/// Where a thin 64-bit Mach-O keeps its code and where its signature starts, read
/// from the load commands, so that «a byte outside the signature» is a fact about
/// the fixture and not a hope.
private struct MachOLayout {
    let fileSize: Int
    let textOffset: Int
    let textSize: Int
    let signatureOffset: Int

    init?(_ data: Data) {
        func word(_ at: Int) -> Int? {
            guard at >= 0, at + 4 <= data.count else { return nil }
            return Int(data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: at, as: UInt32.self) })
        }
        func quad(_ at: Int) -> Int? {
            guard at >= 0, at + 8 <= data.count else { return nil }
            return Int(truncatingIfNeeded:
                        data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: at, as: UInt64.self) })
        }
        func name(_ at: Int) -> String {
            guard at >= 0, at + 16 <= data.count else { return "" }
            return String(decoding: data[at..<at + 16].prefix { $0 != 0 }, as: UTF8.self)
        }
        let loadCommandSegment64 = 0x19, loadCommandCodeSignature = 0x1D
        guard word(0) == 0xFEED_FACF, let count = word(16) else { return nil }
        var at = 32
        var text: (offset: Int, size: Int)?
        var signature: Int?
        for _ in 0..<count {
            guard let command = word(at), let size = word(at + 4), size >= 8 else { return nil }
            if command == loadCommandSegment64, name(at + 8) == "__TEXT", let sections = word(at + 64) {
                for index in 0..<sections {
                    let section = at + 72 + index * 80
                    if name(section) == "__text",
                       let length = quad(section + 40), let offset = word(section + 48) {
                        text = (offset, length)
                    }
                }
            }
            if command == loadCommandCodeSignature { signature = word(at + 8) }
            at += size
        }
        guard let text, text.size > 0, let signature else { return nil }
        self.fileSize = data.count
        self.textOffset = text.offset
        self.textSize = text.size
        self.signatureOffset = signature
    }
}
