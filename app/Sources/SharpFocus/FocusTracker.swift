import AppKit

struct Hole: Equatable {
    let rect: CGRect
    let rounded: Bool
}

final class FocusTracker: ObservableObject {
    static let shared = FocusTracker()

    private init() {}

    @Published private(set) var pinnedWindowIDs: Set<CGWindowID> = []

    var onUpdate: (([Hole], [Hole]) -> Void)?
    var onMissionControlChange: ((Bool) -> Void)?
    private(set) var missionControlActive = false

    private var timer: Timer?
    private var lastFocusHoles: [Hole] = []
    private var lastGrayHoles: [Hole] = []
    private var activationObserver: NSObjectProtocol?
    private var screenObserver: NSObjectProtocol?
    private lazy var screenSizes: [CGSize] = NSScreen.screens.map { $0.frame.size }

    func start() {
        guard timer == nil else { return }
        let t = Timer(timeInterval: 1.0 / 15.0, repeats: true) { [weak self] _ in self?.poll() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        poll(force: true)

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in self?.screenSizes = NSScreen.screens.map { $0.frame.size } }

        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] _ in self?.poll() }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        lastFocusHoles = []
        lastGrayHoles = []
        if let observer = activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            activationObserver = nil
        }
        if let observer = screenObserver {
            NotificationCenter.default.removeObserver(observer)
            screenObserver = nil
        }
    }

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

    func togglePin(_ id: CGWindowID) {
        if pinnedWindowIDs.contains(id) {
            pinnedWindowIDs.remove(id)
        } else {
            pinnedWindowIDs.insert(id)
        }
        poll(force: true)
    }

    func clearPinnedWindows() {
        pinnedWindowIDs = []
        poll(force: true)
    }

    struct WindowInfo: Hashable {
        let id: CGWindowID
        let pid: pid_t
        let bounds: CGRect
        let title: String
        var ownerPid: pid_t { pid }
    }

    private func rawWindowList() -> [[String: Any]] {
        CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
    }

    private func normalWindows(in list: [[String: Any]]) -> [WindowInfo] {
        var appCounts: [String: Int] = [:]
        return list.compactMap { entry in
            guard
                let layer = entry[kCGWindowLayer as String] as? Int, layer == 0,
                let pid = entry[kCGWindowOwnerPID as String] as? pid_t,
                let id = entry[kCGWindowNumber as String] as? CGWindowID,
                let boundsDict = entry[kCGWindowBounds as String] as? NSDictionary,
                let bounds = CGRect(dictionaryRepresentation: boundsDict),
                bounds.width > 30, bounds.height > 30,
                (entry[kCGWindowAlpha as String] as? Double ?? 1) > 0.01
            else { return nil }

            var title = ""
            let ownerName = entry[kCGWindowOwnerName as String] as? String
            if let ownerName {
                appCounts[ownerName, default: 0] += 1
                title += ownerName
                if let name = entry[kCGWindowName as String] as? String {
                    title += " - " + name
                } else {
                    title += " (\(appCounts[ownerName]!))"
                }
            }
            if title.isEmpty { title = "Unknown Window" }
            return WindowInfo(id: id, pid: pid, bounds: bounds, title: title)
        }
    }

    func allWindows() -> [WindowInfo] {
        normalWindows(in: rawWindowList())
    }

    private func detectMissionControl(in list: [[String: Any]]) -> Bool {
        if let axResult = AccessibilityMonitor.shared.isMissionControlActiveViaAX() {
            return axResult
        }
        let strict = AccessibilityMonitor.isMissionControlByStrictCG(list, screenSizes: screenSizes)
        if strict { NSLog("SharpFocus: Mission Control detected via strict CG fallback (no AX)") }
        return strict
    }

    private func frontmostWindow() -> CGWindowID? {
        guard let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier,
              frontPID != getpid()
        else { return nil }
        return normalWindows(in: rawWindowList()).first { $0.pid == frontPID }?.id
    }

    func poll(force: Bool = false) {
        let settings = Settings.shared
        let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let followMode = settings.followMode
        let focusedStaysGrayscale = settings.focusedStaysGrayscale
        let alwaysApps = settings.alwaysApps
        let ownPID = getpid()

        let rawList = rawWindowList()

        let missionControl = detectMissionControl(in: rawList)
        if missionControl != missionControlActive {
            missionControlActive = missionControl
            onMissionControlChange?(missionControl)
        }

        let alwaysPIDs: Set<pid_t> = alwaysApps.isEmpty ? [] : Set(
            NSWorkspace.shared.runningApplications
                .filter { $0.bundleIdentifier.map(alwaysApps.contains) ?? false }
                .map(\.processIdentifier)
        )

        let windows = normalWindows(in: rawList)
        let focusHoles = Self.holes(in: windows, frontPID: frontPID, ownPID: ownPID,
                                    alwaysPIDs: alwaysPIDs, pinnedWindowIDs: pinnedWindowIDs,
                                    followMode: followMode, includeFocused: true)
        let grayHoles = focusedStaysGrayscale
            ? Self.holes(in: windows, frontPID: frontPID, ownPID: ownPID,
                         alwaysPIDs: alwaysPIDs, pinnedWindowIDs: pinnedWindowIDs,
                         followMode: followMode, includeFocused: false)
            : focusHoles

        if force || focusHoles != lastFocusHoles || grayHoles != lastGrayHoles {
            lastFocusHoles = focusHoles
            lastGrayHoles = grayHoles
            onUpdate?(focusHoles, grayHoles)
        }
    }

    private static func holes(in windows: [WindowInfo], frontPID: pid_t?, ownPID: pid_t,
                              alwaysPIDs: Set<pid_t>, pinnedWindowIDs: Set<CGWindowID>,
                              followMode: FollowMode, includeFocused: Bool) -> [Hole] {
        var holes: [Hole] = []
        var blockers: [CGRect] = []
        var focusedWindowTaken = false
        for window in windows {
            var include = false
            if window.pid == ownPID || pinnedWindowIDs.contains(window.id) || alwaysPIDs.contains(window.pid) {
                include = true
            } else if includeFocused, window.pid == frontPID {
                switch followMode {
                case .frontApp: include = true
                case .focusedWindow: include = !focusedWindowTaken
                }
            }
            if include, window.pid == frontPID { focusedWindowTaken = true }

            if include {
                var pieces = [window.bounds]
                for blocker in blockers where blocker.intersects(window.bounds) {
                    pieces = Self.subtract(blocker, from: pieces)
                }
                let intact = pieces == [window.bounds]
                holes.append(contentsOf: pieces.map { Hole(rect: $0, rounded: intact) })
                blockers.append(contentsOf: pieces)
            } else {
                blockers.append(window.bounds)
            }
        }
        return holes
    }

    static func subtract(_ cut: CGRect, from rects: [CGRect]) -> [CGRect] {
        var result: [CGRect] = []
        for rect in rects {
            let overlap = rect.intersection(cut)
            guard !overlap.isEmpty else {
                result.append(rect)
                continue
            }
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
