import HelmTestSupport
import XCTest

/// **Nothing the shell draws asks macOS for a grant on the thread that draws it.**
///
/// `PermissionCheck.currentFullDiskAccess()` is four synchronous `open`s and
/// `read`s of somebody's `chat.db`, Safari bookmarks and address book, and its own
/// declaration says the milliseconds it costs have no ceiling: a blocking syscall
/// answers when it answers. Seven module pages were cured of this by
/// `helmTracksFullDiskAccess`, whose doc comment records that five settings pages
/// carried the same `@State` and the same synchronous line. `Sources/HelmApp` never
/// got the cure, and the worst of the three sites was `HelmPanelContent` — the
/// menu-bar panel, which runs this on every click of the icon.
///
/// **The subject is the enclosing type, not the file.** `PermissionAudit` and
/// `AppDelegate` probe too, at launch and from an audit, and those are judged
/// separately: what makes a call a defect is that a `View` makes it, because a
/// `View`'s `body`, `.task`, `.onAppear` and `.onReceive` all run where the frame
/// is built.
///
/// **The scanner proves itself on a fixture before it is trusted over the tree.**
/// An assertion of an absence passes when the subject never happened at all — a
/// renamed probe, a scan that reads no files — so `testTheScanSeesTheShape` puts
/// the defect in a string and requires it back.
final class AGrantIsAskedOffTheDrawingThreadTests: XCTestCase {

    /// The probes that block, spelled as they are called.
    private static let probes = ["PermissionCheck.currentFullDiskAccess",
                                 "PermissionCheck.currentAccessibility"]

    func testNoViewInTheShellProbesSynchronously() throws {
        var offences: [String] = []
        for file in try RepoSource.swiftFiles(under: "Sources/HelmApp") {
            offences += Self.offences(in: try RepoSource.text(of: file), file: file)
        }
        XCTAssertEqual(offences, [], """
            \(offences.count) synchronous permission probes are made by a `View` in \
            Sources/HelmApp, so the thread that draws waits on a file read of the user's \
            home directory:
            \(offences.joined(separator: "\n"))
            The cure is `helmTracksFullDiskAccess` / `helmTracksAccessibility`, which the \
            module pages already take.
            """)
    }

    /// The scan can fail, shown rather than asserted: the same walk over a
    /// `View` that does the thing, and over a plain type that does it for a
    /// reason of its own.
    func testTheScanSeesTheShape() {
        let drawn = """
            private struct SomePage: View {
                @State private var diskAccess: PermissionState = .denied
                var body: some View {
                    Text("hi").task { diskAccess = PermissionCheck.currentFullDiskAccess() }
                }
            }
            """
        XCTAssertEqual(Self.offences(in: drawn, file: "fixture.swift").count, 1,
                       "the scan cannot see a probe inside a `View`, so its silence over the "
                       + "tree means nothing")

        let launch = """
            @MainActor enum SomeAudit {
                static func run() {
                    log(PermissionCheck.currentFullDiskAccess())
                }
            }
            """
        XCTAssertEqual(Self.offences(in: launch, file: "fixture.swift"), [],
                       "the scan reports a probe made by something that does not draw")

        let named = """
            private struct SomeController: NSSplitViewController {
                func run() { _ = PermissionCheck.currentAccessibility() }
            }
            """
        XCTAssertEqual(Self.offences(in: named, file: "fixture.swift"), [],
                       "`View` inside a longer name is read as a conformance")
    }

    // MARK: - The walk

    /// Comments and string insides blanked, so a probe named in prose is not a
    /// finding — this repository writes those on purpose. Offsets are the blanked
    /// text's throughout, which is what keeps the line numbers honest.
    private static func offences(in source: String, file: String) -> [String] {
        let blanked = SwiftSource.code(source)
        let characters = Array(blanked)
        let types = SwiftSource.typeBodies(in: blanked)
        var out: [String] = []
        for probe in probes {
            for offset in offsets(of: probe, in: blanked) {
                let drawing = types.filter { $0.contains(offset) }.filter {
                    conformsToView(header(of: $0, in: characters))
                }
                guard let closest = drawing.min(by: { $0.width < $1.width }) else { continue }
                let line = blanked.prefix(offset).filter { $0 == "\n" }.count + 1
                out.append("\(file):\(line) — \(probe)() inside \(name(of: closest, characters))")
            }
        }
        return out
    }

    private static func offsets(of needle: String, in source: String) -> [Int] {
        let characters = Array(source), pattern = Array(needle)
        guard characters.count >= pattern.count else { return [] }
        return (0...(characters.count - pattern.count)).filter {
            Array(characters[$0..<($0 + pattern.count)]) == pattern
        }
    }

    /// Everything between the keyword that introduced a body and the body's own
    /// brace: the name and, when it has any, the conformances.
    private static func header(of body: SwiftSource.Body, in characters: [Character]) -> String {
        let text = String(characters[0..<body.open])
        guard let keyword = text.matches(of: introducer).last else { return text }
        return String(text[keyword.range.lowerBound...])
    }

    private static func name(of body: SwiftSource.Body, _ characters: [Character]) -> String {
        header(of: body, in: characters)
            .split(separator: "\n").first.map(String.init)?
            .trimmingCharacters(in: .whitespaces) ?? body.name
    }

    /// Computed, not stored: `Regex` is not `Sendable`, so a `static let` of one
    /// is a Swift 6 build error rather than a style choice.
    private static var introducer: Regex<Substring> {
        /\b(?:struct|class|enum|extension|protocol|actor)\b/
    }

    private static var conformance: Regex<Substring> { /\bView\b|\bViewModifier\b/ }

    private static func conformsToView(_ header: String) -> Bool {
        header.firstMatch(of: conformance) != nil
    }
}
