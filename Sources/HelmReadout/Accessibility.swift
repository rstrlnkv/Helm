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
    /// unless a role narrows it to one.
    static func press(_ args: [String]) throws {
        guard args.count == 2 || args.count == 3 else { throw Failure.usage("press <pid> <name> [<role>]") }
        let app = try application(args)
        var hits: [AXUIElement] = []
        walk(app, 0) { e, _ in
            guard name(e) == args[1], actions(e).contains(kAXPressAction) else { return }
            if args.count == 3, text(e, kAXRoleAttribute) != args[2] { return }
            hits.append(e)
        }
        guard !hits.isEmpty else { throw Failure.data("no control named \"\(args[1])\" with a press action") }
        guard hits.count == 1 else {
            throw Failure.data("\(hits.count) controls named \"\(args[1])\"; name a role:\n" + hits.map { "  " + describe($0) }.joined(separator: "\n"))
        }
        let rc = AXUIElementPerformAction(hits[0], kAXPressAction as CFString)
        print("pressed \(text(hits[0], kAXRoleAttribute)) \"\(args[1])\" frame \(frame(hits[0])) rc \(rc.rawValue)")
        if rc != .success { throw Failure.unavailable("press returned \(rc.rawValue)") }
    }
}
