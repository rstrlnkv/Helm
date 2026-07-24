import AppKit
import Foundation

/// Now-playing tracking for Music and Spotify via AppleScript (the private
/// MediaRemote API is entitlement-locked on modern macOS, so scripting the
/// players is the reliable public path). Polls only while a player app is
/// actually running; announces track changes as island events.
final class IslandMediaSource: @unchecked Sendable {
    private let onEvent: @MainActor (String, String) -> Void
    private var timer: Timer?
    private var lastTrack: String?
    private let queue = DispatchQueue(label: "helm.island.media", qos: .utility)

    private static let players: [(bundleID: String, appName: String)] = [
        ("com.apple.Music", "Music"),
        ("com.spotify.client", "Spotify"),
    ]

    init(onEvent: @escaping @MainActor (String, String) -> Void) {
        self.onEvent = onEvent
        let timer = Timer(timeInterval: 5.0, repeats: true) { [weak self] _ in
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
            return
        }

        let script = """
        tell application "\(player.appName)"
            if player state is playing then
                return (name of current track) & " — " & (artist of current track)
            end if
            return ""
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
        let track = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)

        guard !track.isEmpty, track != lastTrack else {
            if track.isEmpty { lastTrack = nil }
            return
        }
        lastTrack = track
        Task { @MainActor in self.onEvent(track, "music.note") }
    }
}
