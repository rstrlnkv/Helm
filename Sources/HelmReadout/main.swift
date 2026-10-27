// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import Foundation

/// What a screen reads as, in numbers, for `Scripts/shoot.sh` and for a person
/// looking at a capture: a point's colour, runs of one colour, the contrast of
/// two, the frame difference over a crop, a process's windows, executable path and accessibility
/// elements, and the press of a control by its name. It prints and never judges:
/// no threshold lives here, so no number can be argued with by a rule written
/// before the reading (ARCHITECTURE.md § Two screen instruments).
///
/// A tool, not a module: no dependency on any other target, and declared in no
/// product (SwiftPM synthesises one for it, but `HelmApp` does not depend on it, so
/// `--product HelmApp` never builds it).
/// Exit codes are sysexits: 64 usage, 65 bad data or a refusal to guess, 66 no input
/// file, 69 a service or grant is missing.
enum Failure: Error {
    case usage(String), data(String), noInput(String), unavailable(String)

    var code: Int32 {
        switch self {
        case .usage: return 64
        case .data: return 65
        case .noInput: return 66
        case .unavailable: return 69
        }
    }

    var message: String {
        switch self {
        case .usage(let s): return "usage: HelmReadout \(s)"
        case .data(let s), .unavailable(let s): return s
        case .noInput(let s): return "no such file: \(s)"
        }
    }
}

let commands = "point | bands | contrast | diff | window | exe | scale | ax | press | session"
let arguments = Array(CommandLine.arguments.dropFirst())
do {
    guard let command = arguments.first else { throw Failure.usage(commands) }
    let rest = Array(arguments.dropFirst())
    switch command {
    case "point": try Pixels.point(rest)
    case "bands": try Pixels.bands(rest)
    case "contrast": try Pixels.contrast(rest)
    case "diff": try Pixels.diff(rest)
    case "window": try Windows.windows(rest)
    case "exe": try Windows.exe(rest)
    case "scale": try Windows.scale(rest)
    case "ax": try Accessibility.tree(rest)
    case "press": try Accessibility.press(rest)
    case "session": Windows.session()
    default: throw Failure.usage(commands)
    }
} catch let failure as Failure {
    FileHandle.standardError.write(Data((failure.message + "\n").utf8))
    exit(failure.code)
}
