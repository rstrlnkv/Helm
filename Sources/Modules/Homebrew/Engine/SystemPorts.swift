import Foundation
import HelmRuntime

// MARK: - Locator

public struct FSBrewLocator: BrewLocator {
    public init() {}
    public func brewPath() -> String? {
        for p in ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"] where FileManager.default.isExecutableFile(atPath: p) {
            return p
        }
        return nil
    }
}

// MARK: - Process runner

/// Splits streamed bytes into whole lines, thread-safely.
private final class LineBuffer: @unchecked Sendable {
    private let onLine: @Sendable (String) -> Void
    private let lock = NSLock()
    private var partial = ""
    init(onLine: @escaping @Sendable (String) -> Void) { self.onLine = onLine }
    func feed(_ data: Data) {
        guard let s = String(data: data, encoding: .utf8) else { return }
        lock.lock()
        partial += s
        var lines = partial.components(separatedBy: "\n")
        partial = lines.removeLast()   // keep the trailing incomplete line
        lock.unlock()
        for line in lines { onLine(line) }
    }
    func flush() {
        lock.lock(); let rest = partial; partial = ""; lock.unlock()
        if !rest.isEmpty { onLine(rest) }
    }
}

public struct ShellProcessRunner: ProcessRunner {
    public init() {}

    private func environment(_ extra: [String: String]) -> [String: String] {
        var e = ProcessInfo.processInfo.environment
        for (k, v) in extra { e[k] = v }
        return e
    }

    /// The port stays — it is what makes the engine testable — but the body is
    /// `HelmProcess`, like every other module's.
    ///
    /// Two things were different here, and both were wrong in the same
    /// direction. This copy merged stderr into stdout, and all four of its
    /// callers parse what they get: `BrewListParser` takes the first word of
    /// every line as a package name, so a version-support warning from `brew`
    /// became a row with an Uninstall button beside it. And it waited with
    /// `waitUntilExit`, the 50 ms run-loop poll `HelmProcess` was written to
    /// remove, paid twice per query.
    ///
    /// `stream` keeps stderr: a console should show what the tool says. It is
    /// output that gets parsed that must not carry diagnostics.
    public func run(_ launchPath: String, _ args: [String], env: [String: String]) -> (status: Int32, stdout: String) {
        let result = HelmProcess.run(launchPath, args, env: environment(env))
        return (result.status, result.output)
    }

    public func stream(_ launchPath: String, _ args: [String], env: [String: String],
                       onLine: @escaping @Sendable (String) -> Void,
                       onExit: @escaping @Sendable (Int32) -> Void) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: launchPath)
        p.arguments = args
        p.environment = environment(env)
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        let buffer = LineBuffer(onLine: onLine)
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let d = handle.availableData
            if !d.isEmpty { buffer.feed(d) }
        }
        p.terminationHandler = { proc in
            pipe.fileHandleForReading.readabilityHandler = nil
            buffer.flush()
            onExit(proc.terminationStatus)
        }
        do { try p.run() } catch { onExit(-1) }
    }
}

// MARK: - Privileged runner

public struct OSAPrivilegedRunner: PrivilegedRunner {
    public init() {}
    public func runAdmin(_ script: String) -> Bool {
        let esc = script
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let osa = "do shell script \"\(esc)\" with administrator privileges"
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", osa]
        do { try p.run(); p.waitUntilExit(); return p.terminationStatus == 0 } catch { return false }
    }
}

// MARK: - Factory

public struct HomebrewSystemPorts {
    public let locator = FSBrewLocator()
    public let runner = ShellProcessRunner()
    public let privileged = OSAPrivilegedRunner()
    public init() {}
}
