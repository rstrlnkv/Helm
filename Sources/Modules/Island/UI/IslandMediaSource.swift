import AppKit
import Foundation

/// Now-playing tracking for Music and Spotify via AppleScript (the private
/// MediaRemote API is entitlement-locked on modern macOS, so scripting the
/// players is the reliable public path). Polls only while a player app is
/// actually running; announces track changes as island events.
final class IslandMediaSource: @unchecked Sendable {
    struct State: Sendable, Equatable {
        var title: String?
        var artist: String?
        var playing = false
        var position: Double = 0
        var duration: Double = 0
        var artworkURL: URL?
    }

    private let onEvent: @MainActor (String, String) -> Void
    private let onState: @MainActor (State) -> Void
    private var timer: Timer?
    private var lastTrack: String?
    private let queue = DispatchQueue(label: "helm.island.media", qos: .utility)

    private static let players: [(bundleID: String, appName: String)] = [
        ("com.apple.Music", "Music"),
        ("com.spotify.client", "Spotify"),
    ]

    init(onEvent: @escaping @MainActor (String, String) -> Void,
         onState: @escaping @MainActor (State) -> Void) {
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
            Task { @MainActor in self.onState(State()) }
            return
        }

        let artworkLine = player.appName == "Spotify"
            ? "set aw to (artwork url of current track)" : "set aw to \"\""
        let script = """
        tell application "\(player.appName)"
            set st to (player state is playing)
            try
                \(artworkLine)
                return (st as text) & "|" & (name of current track) & "|" & (artist of current track) & "|" & (player position as text) & "|" & (duration of current track as text) & "|" & aw
            on error
                return (st as text) & "||||||"
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
        let parts = output.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        var state = State()
        state.playing = parts.first == "true"
        state.title = parts.count > 1 && !parts[1].isEmpty ? parts[1] : nil
        state.artist = parts.count > 2 && !parts[2].isEmpty ? parts[2] : nil
        // Music reports duration in seconds, Spotify position in s / duration in ms.
        state.position = parts.count > 3 ? Double(parts[3].replacingOccurrences(of: ",", with: ".")) ?? 0 : 0
        var duration = parts.count > 4 ? Double(parts[4].replacingOccurrences(of: ",", with: ".")) ?? 0 : 0
        if player.appName == "Spotify" { duration /= 1000 }
        state.duration = duration
        if parts.count > 5, parts[5].hasPrefix("http") { state.artworkURL = URL(string: parts[5]) }

        let snapshot = state
        Task { @MainActor in self.onState(snapshot) }

        // Peek only on a track change while actually playing.
        let track = state.title.map { "\($0) — \(state.artist ?? "")" } ?? ""
        guard state.playing, !track.isEmpty, track != lastTrack else {
            if track.isEmpty { lastTrack = nil }
            return
        }
        lastTrack = track
        Task { @MainActor in self.onEvent(track, "music.note") }
    }

    func previousTrack() { command("previous track") }
    func nextTrack() { command("next track") }

    private func command(_ verb: String) {
        queue.async {
            let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
            guard let player = Self.players.first(where: { running.contains($0.bundleID) }) else { return }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", "tell application \"\(player.appName)\" to \(verb)"]
            process.standardOutput = Pipe(); process.standardError = Pipe()
            try? process.run()
            process.waitUntilExit()
            self.poll()
        }
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
