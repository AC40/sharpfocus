import AppKit
import ApplicationServices

final class AccessibilityMonitor: ObservableObject {
    static let shared = AccessibilityMonitor()

    @Published private(set) var isTrusted: Bool = AccessibilityMonitor.computeIsTrusted()

    private var pollTimer: Timer?

    private init() {
        let bundlePath = Bundle.main.bundlePath
        NSLog("SharpFocus: AX init — trusted=\(isTrusted) bundle=\(bundlePath) AXIsProcessTrusted=\(AXIsProcessTrusted())")
    }

    static func computeIsTrusted() -> Bool {
        if AXIsProcessTrusted() { return true }
        return canProbeAX()
    }

    private static func canProbeAX() -> Bool {
        guard let pid = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first?.processIdentifier else {
            return false
        }
        let el = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(el, kAXChildrenAttribute as CFString, &value) == .success
    }

    @discardableResult
    static func check(prompt: Bool) -> Bool {
        if prompt {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            let trusted = AXIsProcessTrustedWithOptions(options)
            if trusted { return true }
            return computeIsTrusted()
        }
        return computeIsTrusted()
    }

    func refresh() {
        let now = Self.computeIsTrusted()
        guard now != isTrusted else { return }
        DispatchQueue.main.async { [weak self] in
            self?.isTrusted = now
            NSLog("SharpFocus: AX refresh — trusted=\(now)")
        }
    }

    static func openSettings() {
        let urls = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
            "x-apple.systempreferences:com.apple.preference.security?Privacy",
        ]
        for string in urls {
            if let url = URL(string: string), NSWorkspace.shared.open(url) { break }
        }
    }

    static var runningAppPath: String { Bundle.main.bundlePath }

    func startPolling() {
        guard pollTimer == nil else { return }
        let timer = Timer(timeInterval: 0.8, repeats: true) { [weak self] _ in
            guard let self else { return }
            let trusted = Self.computeIsTrusted()
            if trusted != self.isTrusted {
                DispatchQueue.main.async { self.isTrusted = trusted }
                NSLog("SharpFocus: Accessibility trust changed -> \(trusted)")
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
        refresh()
    }

    func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    func isMissionControlActiveViaAX() -> Bool? {
        guard Self.computeIsTrusted() else { return nil }
        guard let dockPID = dockPID else { return nil }
        let dockElement = AXUIElementCreateApplication(dockPID)
        if let axActive = missionControlInAXWindows(of: dockElement) {
            return axActive
        }
        if searchAXTree(dockElement, depth: 0) { return true }
        if axHasAnyContent(dockElement) { return false }
        return nil
    }

    static func isMissionControlByStrictCG(_ list: [[String: Any]], screenSizes: [CGSize]) -> Bool {
        for entry in list {
            guard
                let owner = entry[kCGWindowOwnerName as String] as? String, owner == "Dock",
                let layer = entry[kCGWindowLayer as String] as? Int,
                (18...20).contains(layer),
                let boundsDict = entry[kCGWindowBounds as String] as? NSDictionary,
                let bounds = CGRect(dictionaryRepresentation: boundsDict)
            else { continue }
            for size in screenSizes {
                let coversWidth = bounds.width >= size.width - 2
                let coversHeight = bounds.height >= size.height - 2
                let areaCovers = bounds.width * bounds.height >= 0.92 * size.width * size.height
                if coversWidth && coversHeight && areaCovers {
                    return true
                }
            }
        }
        return false
    }

    private var dockPID: pid_t? {
        NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first?.processIdentifier
            ?? NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == "com.apple.dock" })?.processIdentifier
    }

    private func axHasAnyContent(_ element: AXUIElement) -> Bool {
        var value: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXWindowsAttribute as CFString, &value) == .success,
           let arr = value as? [Any], !arr.isEmpty { return true }
        if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success,
           let arr = value as? [Any], !arr.isEmpty { return true }
        return false
    }

    private func missionControlInAXWindows(of dockElement: AXUIElement) -> Bool? {
        var windowsRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(dockElement, kAXWindowsAttribute as CFString, &windowsRef)
        guard result == .success, let windows = windowsRef as? [AXUIElement], !windows.isEmpty else {
            return nil
        }
        for window in windows {
            if elementLooksLikeMissionControl(window) { return true }
            if elementContainsMissionControl(window, depth: 1) { return true }
        }
        return false
    }

    private func elementContainsMissionControl(_ element: AXUIElement, depth: Int) -> Bool {
        guard depth <= 2 else { return false }
        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let children = childrenRef as? [AXUIElement] else { return false }
        for child in children {
            if elementLooksLikeMissionControl(child) { return true }
            if elementContainsMissionControl(child, depth: depth + 1) { return true }
        }
        return false
    }

    private func elementLooksLikeMissionControl(_ element: AXUIElement) -> Bool {
        let attributes: [CFString] = [
            kAXTitleAttribute as CFString,
            kAXDescriptionAttribute as CFString,
            kAXIdentifierAttribute as CFString,
            kAXSubroleAttribute as CFString,
            kAXRoleDescriptionAttribute as CFString,
        ]
        for attr in attributes {
            var valueRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, attr, &valueRef) == .success,
                  let string = valueRef as? String, !string.isEmpty else { continue }
            let lower = string.lowercased()
            if lower.contains("mission control") || lower.contains("missioncontrol") { return true }
            if lower == "mc" || lower == "exposé" || lower == "expose" || lower == "app exposé" { return true }
            if lower.contains("expose") { return true }
            if lower == "launchpad" { return true }
        }
        return false
    }

    private func searchAXTree(_ element: AXUIElement, depth: Int) -> Bool {
        if depth > 6 { return false }
        if elementLooksLikeMissionControl(element) { return true }
        for attrName in [kAXChildrenAttribute as CFString, kAXWindowsAttribute as CFString] {
            var valueRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, attrName, &valueRef) == .success else { continue }
            if let children = valueRef as? [AXUIElement] {
                for child in children {
                    if searchAXTree(child, depth: depth + 1) { return true }
                }
            } else if CFGetTypeID(valueRef as CFTypeRef) == AXUIElementGetTypeID() {
                let child = valueRef as! AXUIElement
                if searchAXTree(child, depth: depth + 1) { return true }
            }
        }
        return false
    }
}

extension AccessibilityMonitor {
    static var isTrusted: Bool { computeIsTrusted() }
}
