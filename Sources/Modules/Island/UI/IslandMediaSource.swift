import AppKit
import Foundation

/// Now-playing tracking for Music and Spotify via AppleScript (the private
/// MediaRemote API is entitlement-locked on modern macOS, so scripting the
/// players is the reliable public path). Polls only while a player app is
/// actually running; announces track changes as island events.
final class IslandMediaSource: @unchecked Sendable {
    private let onEvent: @MainActor (String, String) -> Void
    /// Continuous state for the controls pill: (track title or nil, playing).
    private let onState: @MainActor (String?, Bool) -> Void
    private var timer: Timer?
    private var lastTrack: String?
    private let queue = DispatchQueue(label: "helm.island.media", qos: .utility)

    private static let players: [(bundleID: String, appName: String)] = [
        ("com.apple.Music", "Music"),
        ("com.spotify.client", "Spotify"),
    ]

    init(onEvent: @escaping @MainActor (String, String) -> Void,
         onState: @escaping @MainActor (String?, Bool) -> Void) {
        self.onEvent = onEvent
        self.onState = onState
        let timer = Timer(timeInterval: 3.0, repeats: true) { [weak self] _ in
            self?.queue.async { self?.poll() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        queue.async { [weak self] in self?.poll() }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func poll() {
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        guard let player = Self.players.first(where: { running.contains($0.bundleID) })
        else {
            lastTrack = nil
            Task { @MainActor in self.onState(nil, false) }
            return
        }

        let script = """
        tell application "\(player.appName)"
            set st to (player state is playing)
            try
                return (st as text) & "|" & (name of current track) & " — " & (artist of current track)
            on error
                return (st as text) & "|"
            end try
        end tell
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        guard (try? process.run()) != nil else { return }
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = output.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
        let playing = parts.first == "true"
        let track = parts.count > 1 ? String(parts[1]) : ""

        Task { @MainActor in self.onState(track.isEmpty ? nil : track, playing) }

        // Peek only on a track change while actually playing.
        guard playing, !track.isEmpty, track != lastTrack else {
            if track.isEmpty { lastTrack = nil }
            return
        }
        lastTrack = track
        Task { @MainActor in self.onEvent(track, "music.note") }
    }

    /// Toggles playback in whichever supported player is running.
    func playPause() {
        queue.async {
            let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
            guard let player = Self.players.first(where: { running.contains($0.bundleID) }) else { return }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", "tell application \"\(player.appName)\" to playpause"]
            process.standardOutput = Pipe(); process.standardError = Pipe()
            try? process.run()
            process.waitUntilExit()
            self.poll()
        }
    }
}
