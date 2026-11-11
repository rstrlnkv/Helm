// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import ApplicationServices
import CoreGraphics
import Darwin
import Foundation

private struct WindowInfo {
    let id: Int, layer: Int, owner: String, pid: Int32, alpha: Double
    let bounds: CGRect
}

private func windowList(_ options: CGWindowListOption) -> [WindowInfo] {
    let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []
    return list.compactMap { w in
        guard let id = w[kCGWindowNumber as String] as? Int, let pid = w[kCGWindowOwnerPID as String] as? Int32,
              let bd = w[kCGWindowBounds as String] as? [String: CGFloat],
              let x = bd["X"], let y = bd["Y"], let width = bd["Width"], let height = bd["Height"] else { return nil }
        return WindowInfo(id: id, layer: w[kCGWindowLayer as String] as? Int ?? 0,
                          owner: w[kCGWindowOwnerName as String] as? String ?? "?", pid: pid,
                          alpha: w[kCGWindowAlpha as String] as? Double ?? 1,
                          bounds: CGRect(x: x, y: y, width: width, height: height))
    }
}

enum Windows {
    /// One line per window of the process, and under each on screen the windows in front of it
    /// whose bounds meet it: the front check, said in numbers.
    static func windows(_ args: [String]) throws {
        guard args.count == 1, let pid = Int32(args[0]) else { throw Failure.usage("window <pid>") }
        let onScreen = windowList(.optionOnScreenOnly)   // front to back
        for w in windowList(.optionAll) where w.pid == pid {
            let shown = onScreen.firstIndex { $0.id == w.id }
            let b = w.bounds
            print("window \(w.id) layer \(w.layer) onscreen \(shown == nil ? "no" : "yes") bounds \(Int(b.minX.rounded())),\(Int(b.minY.rounded())),\(Int(b.width.rounded())),\(Int(b.height.rounded()))")
            guard let front = shown else { continue }
            let above = onScreen[..<front].filter { $0.pid != pid && $0.alpha > 0 && $0.bounds.intersects(b) }
            print("above: " + (above.isEmpty ? "none" : above.map { "\($0.owner) \($0.pid) layer \($0.layer)" }.joined(separator: "; ")))
        }
    }

    /// The path of the process's executable as the kernel holds it (`proc_pidpath`), not argv[0]:
    /// any process can set its own argv[0], none can set this. Exit 65 when the pid has none.
    static func exe(_ args: [String]) throws {
        guard args.count == 1, let pid = Int32(args[0]) else { throw Failure.usage("exe <pid>") }
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { throw Failure.data("no executable path for pid \(pid)") }
        print(String(cString: buffer))
    }

    /// Pixels per point of the display holding a point: what a capture of a region there should
    /// measure, so a shot whose size disagrees can be said so. Prints "unknown" when no display holds it.
    static func scale(_ args: [String]) throws {
        guard args.count == 2, let x = Double(args[0]), let y = Double(args[1]) else { throw Failure.usage("scale <x> <y>") }
        var display = CGDirectDisplayID(), count: UInt32 = 0
        guard CGGetDisplaysWithPoint(CGPoint(x: x, y: y), 1, &display, &count) == .success, count == 1,
              let mode = CGDisplayCopyDisplayMode(display), mode.width > 0 else { print("unknown"); return }
        print(Double(mode.pixelWidth) / Double(mode.width))
    }

    static func session() {
        let d = CGSessionCopyCurrentDictionary() as? [String: Any] ?? [:]
        let locked = d["CGSSessionScreenIsLocked"] as? Bool ?? false
        let console = d["kCGSSessionOnConsoleKey"] as? Bool ?? false
        func yn(_ b: Bool) -> String { b ? "yes" : "no" }
        print("locked: \(yn(locked))  on-console: \(yn(console))  ax-trusted: \(yn(AXIsProcessTrusted()))  screen-recording: \(yn(CGPreflightScreenCaptureAccess()))")
    }
}
