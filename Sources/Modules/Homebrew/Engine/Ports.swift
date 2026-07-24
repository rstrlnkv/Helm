import Foundation

public protocol BrewLocator: Sendable {
    func brewPath() -> String?
}

public protocol ProcessRunner: Sendable {
    /// Run to completion, capturing stdout (stderr merged). Blocking.
    func run(_ launchPath: String, _ args: [String], env: [String: String]) -> (status: Int32, stdout: String)
    /// Stream a long-running process: `onLine` per output line, `onExit` at the end.
    func stream(_ launchPath: String, _ args: [String], env: [String: String],
                onLine: @escaping @Sendable (String) -> Void,
                onExit: @escaping @Sendable (Int32) -> Void)
}

public protocol PrivilegedRunner: Sendable {
    /// Run a shell script with administrator privileges via the native macOS
    /// password dialog (the user types the password). Returns success.
    func runAdmin(_ script: String) -> Bool
}
