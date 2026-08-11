import XCTest
import AppKit
import SwiftUI

/// Ink that carries a meaning comes from `HelmSignal`, never from the system
/// palette.
///
/// `SignalColourContrastTests` proves the tokens are readable and that the raw
/// colours they replace are not. It cannot prove anybody *used* them: the About
/// page's update card kept drawing `statusIcon(…, .orange)` and `(…, .green)`
/// two hundred lines below a `permissionRow` that had been converted, and the
/// shared `HelmStatusDot` filled `Color.green` at three call sites. Measured in
/// light against the real window background, those are 2.31:1 and 2.22:1 where
/// the tokens are 4.54:1 and 4.58:1.
///
/// So this is a scan, not a measurement: the shape it describes is "a raw system
/// signal colour handed to something that paints with it".
///
/// A tint is not ink and is deliberately not caught. `HelmBadge` takes `.orange`
/// as a *tint* and draws it at 0.20 behind text at `Color.primary` — the pill
/// exists so that a caller cannot get that contrast wrong — and `PaletteColor`
/// returns `.red` because the user picked the colour called red.
final class SignalInkTests: XCTestCase {

    /// The system colours `HelmSignal` exists to replace, in both spellings.
    private static let raw = ["orange", "green", "red"]
    /// Calls that paint with the colour they are given.
    private static let painters = ["foregroundStyle(", "foregroundColor(", ".fill(", "statusIcon("]

    func testNothingInTheShellPaintsWithARawSystemSignalColour() throws {
        var offenders: [String] = []

        for url in Self.shellSources() {
            guard let source = try? String(contentsOf: url, encoding: .utf8) else { continue }
            for (index, line) in source.components(separatedBy: "\n").enumerated() {
                guard Self.painters.contains(where: line.contains) else { continue }
                guard Self.raw.contains(where: { line.contains(".\($0))")
                                              || line.contains(".\($0) ")
                                              || line.contains("Color.\($0)") })
                else { continue }
                offenders.append("\(url.lastPathComponent):\(index + 1)  "
                                 + line.trimmingCharacters(in: .whitespaces))
            }
        }

        XCTAssertEqual(offenders, [], """
            These paint with a system colour instead of a HelmSignal token. In \
            light appearance orange measures 2.31:1 and green 2.22:1 against the \
            window, where warning is 4.54:1 and success 4.58:1:
            \(offenders.joined(separator: "\n"))
            """)
    }

    /// The scan is worth nothing if it stops finding the files it scans.
    func testTheScanReadsTheShell() throws {
        let names = Set(Self.shellSources().map(\.lastPathComponent))
        XCTAssertTrue(names.contains("SettingsWindow.swift"), "the scan lost HelmApp")
        XCTAssertTrue(names.contains("HelmStatusDot.swift"), "the scan lost HelmUI")
        XCTAssertGreaterThan(names.count, 20, "the source tree moved under this test")
    }

    private static func shellSources() -> [URL] {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Sources")
        var found: [URL] = []
        let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
        while let url = files?.nextObject() as? URL {
            guard url.pathExtension == "swift" else { continue }
            guard url.path.contains("/HelmUI/") || url.path.contains("/HelmApp/") else { continue }
            found.append(url)
        }
        return found
    }
}
