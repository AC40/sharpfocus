import AppKit

/// A screen region that stays in full color. `rounded` is set for whole,
/// unoccluded windows so the cutout can follow the window's corner radius.
struct Hole: Equatable {
    let rect: CGRect
    let rounded: Bool
}

/// Watches the window list and reports which screen regions ("holes") should
/// stay in full color. Rects are in global CoreGraphics coordinates
/// (origin at the top-left of the primary display, y grows downward).
///
/// Uses CGWindowList polling — window bounds and owner PIDs are available
/// without any special permissions.
final class FocusTracker {
    var onUpdate: (([Hole]) -> Void)?
    /// Fired when Mission Control / App Exposé / Launchpad becomes active or
    /// inactive (detected via Dock-owned windows at elevated layers).
    var onMissionControlChange: ((Bool) -> Void)?
    private(set) var missionControlActive = false

    /// Individually pinned windows (session-only; window IDs don't survive relaunches).
    private(set) var pinnedWindowIDs: Set<CGWindowID> = []

    private var timer: Timer?
    private var lastHoles: [Hole] = []
    private var activationObserver: NSObjectProtocol?

    func start() {
        guard timer == nil else { return }
        let t = Timer(timeInterval: 1.0 / 15.0, repeats: true) { [weak self] _ in self?.poll() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        poll(force: true)

        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] _ in self?.poll() }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        lastHoles = []
        if let observer = activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            activationObserver = nil
        }
    }

    /// Toggles the pin on the currently focused window. Returns true if it is now pinned.
    @discardableResult
    func togglePinFocusedWindow() -> Bool {
        guard let front = frontmostWindow() else { return false }
        if pinnedWindowIDs.contains(front) {
            pinnedWindowIDs.remove(front)
        } else {
            pinnedWindowIDs.insert(front)
        }
        poll(force: true)
        return pinnedWindowIDs.contains(front)
    }

    func clearPinnedWindows() {
        pinnedWindowIDs = []
        poll(force: true)
    }

    private struct WindowInfo {
        let id: CGWindowID
        let pid: pid_t
        let bounds: CGRect
    }

    private func rawWindowList() -> [[String: Any]] {
        CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID)
            as? [[String: Any]] ?? []
    }

    /// Normal-level, visible windows, front-to-back, excluding our own.
    private func normalWindows(in list: [[String: Any]]) -> [WindowInfo] {
        let myPID = getpid()
        return list.compactMap { entry in
            guard
                let layer = entry[kCGWindowLayer as String] as? Int, layer == 0,
                let pid = entry[kCGWindowOwnerPID as String] as? pid_t, pid != myPID,
                let id = entry[kCGWindowNumber as String] as? CGWindowID,
                let boundsDict = entry[kCGWindowBounds as String] as? NSDictionary,
                let bounds = CGRect(dictionaryRepresentation: boundsDict),
                bounds.width > 30, bounds.height > 30,
                (entry[kCGWindowAlpha as String] as? Double ?? 1) > 0.01
            else { return nil }
            return WindowInfo(id: id, pid: pid, bounds: bounds)
        }
    }

    /// Mission Control / App Exposé put up *screen-sized* Dock-owned windows
    /// at layers 18-20. The regular Dock bar is a thin strip at layer 20 and
    /// wallpaper windows sit at the desktop level (large negative layer), so
    /// "Dock window, elevated layer, covers most of a screen" is distinctive.
    private func detectMissionControl(in list: [[String: Any]]) -> Bool {
        let screenSizes = NSScreen.screens.map { $0.frame.size }
        return list.contains { entry in
            guard
                let owner = entry[kCGWindowOwnerName as String] as? String, owner == "Dock",
                let layer = entry[kCGWindowLayer as String] as? Int,
                (1...100).contains(layer),
                let boundsDict = entry[kCGWindowBounds as String] as? NSDictionary,
                let bounds = CGRect(dictionaryRepresentation: boundsDict)
            else { return false }
            return screenSizes.contains { size in
                bounds.width * bounds.height >= 0.7 * size.width * size.height
            }
        }
    }

    private func frontmostWindow() -> CGWindowID? {
        guard let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        else { return nil }
        return normalWindows(in: rawWindowList()).first { $0.pid == frontPID }?.id
    }

    func poll(force: Bool = false) {
        let settings = Settings.shared
        let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier

        let rawList = rawWindowList()

        let missionControl = detectMissionControl(in: rawList)
        if missionControl != missionControlActive {
            missionControlActive = missionControl
            onMissionControlChange?(missionControl)
        }

        let alwaysPIDs = Set(
            NSWorkspace.shared.runningApplications
                .filter { app in
                    guard let id = app.bundleIdentifier else { return false }
                    return settings.alwaysApps.contains(id)
                }
                .map(\.processIdentifier)
        )

        // Walk front-to-back. A focused window only stays in color where it is
        // not covered by a non-focused window in front of it; the resulting
        // colored region is kept as disjoint rects so the even-odd mask stays
        // correct even with overlapping windows.
        var holes: [Hole] = []
        var occluders: [CGRect] = []
        var coloredRegion: [CGRect] = []
        var focusedWindowTaken = false
        for window in normalWindows(in: rawList) {
            var include = false
            if pinnedWindowIDs.contains(window.id) || alwaysPIDs.contains(window.pid) {
                include = true
            } else if window.pid == frontPID {
                switch settings.followMode {
                case .frontApp:
                    include = true
                case .focusedWindow:
                    if !focusedWindowTaken {
                        include = true
                        focusedWindowTaken = true
                    }
                }
            }
            if include {
                var pieces = [window.bounds]
                for blocker in occluders + coloredRegion {
                    pieces = Self.subtract(blocker, from: pieces)
                }
                coloredRegion.append(contentsOf: pieces)
                let intact = pieces == [window.bounds]
                holes.append(contentsOf: pieces.map { Hole(rect: $0, rounded: intact) })
            } else {
                occluders.append(window.bounds)
            }
        }

        if force || holes != lastHoles {
            lastHoles = holes
            onUpdate?(holes)
        }
    }

    /// Removes `cut` from each rect, splitting into up to four remainder rects.
    static func subtract(_ cut: CGRect, from rects: [CGRect]) -> [CGRect] {
        var result: [CGRect] = []
        for rect in rects {
            let overlap = rect.intersection(cut)
            guard !overlap.isEmpty else {
                result.append(rect)
                continue
            }
            // Top strip (smaller y in CG coords), bottom strip, left and right slivers.
            if overlap.minY > rect.minY {
                result.append(CGRect(x: rect.minX, y: rect.minY,
                                     width: rect.width, height: overlap.minY - rect.minY))
            }
            if overlap.maxY < rect.maxY {
                result.append(CGRect(x: rect.minX, y: overlap.maxY,
                                     width: rect.width, height: rect.maxY - overlap.maxY))
            }
            if overlap.minX > rect.minX {
                result.append(CGRect(x: rect.minX, y: overlap.minY,
                                     width: overlap.minX - rect.minX, height: overlap.height))
            }
            if overlap.maxX < rect.maxX {
                result.append(CGRect(x: overlap.maxX, y: overlap.minY,
                                     width: rect.maxX - overlap.maxX, height: overlap.height))
            }
        }
        return result
    }
}
