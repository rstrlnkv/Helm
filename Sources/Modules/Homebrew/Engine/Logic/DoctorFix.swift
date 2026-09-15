import Foundation

/// A command line `brew doctor` printed, and whether Helm may run it.
///
/// **Shape only, here.** `DoctorParser` never constructs one — every
/// `DoctorIssue` it produces carries `fix: nil`, because parsing text is not
/// judging a command safe to run. `DoctorFix.judge(_:installed:)`, the
/// allowlist that decides `kind` against the argv-exact rules this module's
/// plan lays out (Task 3), belongs in this file next to the type it judges,
/// and has not landed yet — a command parsed out of a tool's output is data,
/// not an instruction, until that allowlist says otherwise.
public struct DoctorFix: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        /// Safe for Helm to run through the module's own operation path.
        case runnable
        /// Shown to the person to copy; never executed by this app.
        case copyOnly
    }
    public let argv: [String]
    public let kind: Kind
    public init(argv: [String], kind: Kind) {
        self.argv = argv
        self.kind = kind
    }
}
