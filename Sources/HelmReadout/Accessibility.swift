// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import ApplicationServices
import Foundation

private func attribute(_ e: AXUIElement, _ k: String) -> CFTypeRef? {
    var v: CFTypeRef?
    return AXUIElementCopyAttributeValue(e, k as CFString, &v) == .success ? v : nil
}

private func text(_ e: AXUIElement, _ k: String) -> String { attribute(e, k) as? String ?? "" }

/// What the control is called to an assistive tool: title, description, label, and last the value.
private func name(_ e: AXUIElement) -> String {
    for k in [kAXTitleAttribute, kAXDescriptionAttribute, kAXLabelValueAttribute as String, kAXValueAttribute] {
        let s = text(e, k)
        if !s.isEmpty { return s }
    }
    return ""
}

private func actions(_ e: AXUIElement) -> [String] {
    var names: CFArray?
    AXUIElementCopyActionNames(e, &names)
    return names as? [String] ?? []
}

private func frame(_ e: AXUIElement) -> String {
    var p = CGPoint.zero, s = CGSize.zero
    if let v = attribute(e, kAXPositionAttribute), CFGetTypeID(v) == AXValueGetTypeID() { AXValueGetValue(v as! AXValue, .cgPoint, &p) }
    if let v = attribute(e, kAXSizeAttribute), CFGetTypeID(v) == AXValueGetTypeID() { AXValueGetValue(v as! AXValue, .cgSize, &s) }
    return "\(Int(p.x.rounded())),\(Int(p.y.rounded())),\(Int(s.width.rounded())),\(Int(s.height.rounded()))"
}

private func walk(_ e: AXUIElement, _ depth: Int, _ visit: (AXUIElement, Int) -> Void) {
    visit(e, depth)
    guard depth < 25 else { return }
    for c in attribute(e, kAXChildrenAttribute) as? [AXUIElement] ?? [] { walk(c, depth + 1, visit) }
}

private func describe(_ e: AXUIElement) -> String {
    let value = attribute(e, kAXValueAttribute).map { " value=\"\($0)\"" } ?? ""
    let selected = (attribute(e, kAXSelectedAttribute) as? Bool).map { " selected=\($0)" } ?? ""
    let enabled = (attribute(e, kAXEnabledAttribute) as? Bool).map { " enabled=\($0)" } ?? ""
    return "\(text(e, kAXRoleAttribute)) name=\"\(name(e))\"\(value)\(selected)\(enabled) frame=\(frame(e)) actions=\(actions(e).joined(separator: ","))"
}

enum Accessibility {
    private static func application(_ args: [String]) throws -> AXUIElement {
        guard AXIsProcessTrusted() else { throw Failure.unavailable("Accessibility is not granted to the process at the top of this command's chain") }
        guard let pid = Int32(args[0]) else { throw Failure.usage("a pid") }
        return AXUIElementCreateApplication(pid)
    }

    static func tree(_ args: [String]) throws {
        guard args.count == 1 else { throw Failure.usage("ax <pid>") }
        walk(try application(args), 0) { e, d in print(String(repeating: "  ", count: d) + describe(e)) }
    }

    /// Presses the one control of that name that has a press action. More than one: refuses and lists them,
    /// numbered in tree order (the order `ax` prints), unless a role narrows it to one or `--nth <n>` (1-based,
    /// counted among the controls left after the role) picks one: the same action offered twice on a page,
    /// a toolbar button and an empty state's, keeps one name. Without `--nth` a tie is still refused.
    static func press(_ given: [String]) throws {
        var args = given, nth: Int?
        if let i = args.firstIndex(of: "--nth") {
            guard i == args.count - 2, let n = Int(args[i + 1]), n >= 1 else { throw Failure.usage("press <pid> <name> [<role>] [--nth <n>=1...]") }
            nth = n
            args.removeSubrange(i...)
        }
        guard args.count == 2 || args.count == 3 else { throw Failure.usage("press <pid> <name> [<role>] [--nth <n>=1...]") }
        let app = try application(args)
        var hits: [AXUIElement] = []
        walk(app, 0) { e, _ in
            guard name(e) == args[1], actions(e).contains(kAXPressAction) else { return }
            if args.count == 3, text(e, kAXRoleAttribute) != args[2] { return }
            hits.append(e)
        }
        guard !hits.isEmpty else { throw Failure.data("no control named \"\(args[1])\" with a press action") }
        let list = hits.enumerated().map { "  \($0.offset + 1): " + describe($0.element) }.joined(separator: "\n")
        if let n = nth {
            guard n <= hits.count else { throw Failure.data("--nth \(n), but \(hits.count) controls named \"\(args[1])\":\n" + list) }
            hits = [hits[n - 1]]
        }
        guard hits.count == 1 else {
            throw Failure.data("\(hits.count) controls named \"\(args[1])\"; name a role or pass --nth <n>:\n" + list)
        }
        let rc = AXUIElementPerformAction(hits[0], kAXPressAction as CFString)
        print("pressed \(text(hits[0], kAXRoleAttribute)) \"\(args[1])\" frame \(frame(hits[0])) rc \(rc.rawValue)")
        if rc != .success { throw Failure.unavailable("press returned \(rc.rawValue)") }
    }

    /// Sets the vertical scroll bar of the widest scroll area to `fraction` of its range, for what lies
    /// below the fold: a SwiftUI row offers no scroll-to-visible, and the area's page-down action answers
    /// -25204. The value is absolute, so a rerun gives the same frame. Prints the bar's value, how far
    /// the area's first child moved, and the result code; refuses when the app has no area or the area
    /// has no bar (nothing below the fold).
    static func scroll(_ args: [String]) throws {
        guard args.count == 2, let fraction = Double(args[1]), fraction.isFinite, (0...1).contains(fraction) else {
            throw Failure.usage("scroll <pid> <fraction 0...1>")
        }
        let app = try application(args)
        var best: (area: AXUIElement, width: Int)?
        walk(app, 0) { e, _ in
            guard text(e, kAXRoleAttribute) == kAXScrollAreaRole as String else { return }
            var s = CGSize.zero
            if let v = attribute(e, kAXSizeAttribute), CFGetTypeID(v) == AXValueGetTypeID() { AXValueGetValue(v as! AXValue, .cgSize, &s) }
            if Int(s.width) > best?.width ?? -1 { best = (e, Int(s.width)) }
        }
        guard let area = best?.area else { throw Failure.data("no scroll area in the app") }
        guard let bar = attribute(area, kAXVerticalScrollBarAttribute) else { throw Failure.data("nothing below the fold: the scroll area has no vertical scroll bar") }
        let first = (attribute(area, kAXChildrenAttribute) as? [AXUIElement])?.first
        let before = first.map(top) ?? 0
        let rc = AXUIElementSetAttributeValue(bar as! AXUIElement, kAXValueAttribute as CFString, NSNumber(value: fraction))
        usleep(500_000)
        let value = attribute(bar as! AXUIElement, kAXValueAttribute).map { "\($0)" } ?? "unreadable"
        let moved = first.map { Int((top($0) - before).rounded()) } ?? 0
        print("scrolled to \(fraction) bar value \(value) moved \(moved) pt rc \(rc.rawValue)")
        if rc != .success { throw Failure.unavailable("scroll returned \(rc.rawValue)") }
    }

    /// Presses the status item of the app `args[0]` as the system draws it: on macOS 27 the button
    /// is in the tree of `MenuBarAgent`, `args[1]`, not of the app, so it is found by the pid its element
    /// answers to. The label "Helm" (`StatusItemController`) is the button's description; its title is the
    /// countdown text while one is shown, and `name` reads the title first, so the match reads both.
    /// Not exactly one: refuses and lists them.
    static func statusItem(_ args: [String]) throws {
        guard args.count == 2, let pid = Int32(args[0]), Int32(args[1]) != nil else { throw Failure.usage("statusitem <pid> <host-pid>") }
        let host = try application([args[1]])
        var hits: [AXUIElement] = []
        walk(host, 0) { e, _ in
            var owner: pid_t = 0
            guard text(e, kAXRoleAttribute) == kAXButtonRole as String, (name(e) == "Helm" || text(e, kAXDescriptionAttribute) == "Helm"), actions(e).contains(kAXPressAction),
                  AXUIElementGetPid(e, &owner) == .success, owner == pid else { return }
            hits.append(e)
        }
        guard hits.count == 1 else {
            throw Failure.data("\(hits.count) status items labelled \"Helm\" (title or description) of pid \(pid) under pid \(args[1])" + (hits.isEmpty ? "" : ":\n" + hits.map { "  " + describe($0) }.joined(separator: "\n")))
        }
        let rc = AXUIElementPerformAction(hits[0], kAXPressAction as CFString)
        print("pressed status item pid \(pid) frame \(frame(hits[0])) rc \(rc.rawValue)")
        if rc != .success { throw Failure.unavailable("press returned \(rc.rawValue)") }
    }

    private static func top(_ e: AXUIElement) -> CGFloat {
        var p = CGPoint.zero
        if let v = attribute(e, kAXPositionAttribute), CFGetTypeID(v) == AXValueGetTypeID() { AXValueGetValue(v as! AXValue, .cgPoint, &p) }
        return p.y
    }
}
