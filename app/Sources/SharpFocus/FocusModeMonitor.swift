import AppKit

/// Reads the active macOS Focus mode from the DoNotDisturb database
/// (~/Library/DoNotDisturb/DB). There is no public API that names the active
/// Focus; these files are what every current tool uses. Reading them requires
/// Full Disk Access on macOS 14+, so this is strictly opt-in: without access
/// the monitor reports nil and the UI offers to open the right settings pane.
final class FocusModeMonitor {
    static let shared = FocusModeMonitor()
    static let isSupported = true

    private static let dbDirectory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/DoNotDisturb/DB", isDirectory: true)
    private static let assertionsURL = dbDirectory.appendingPathComponent("Assertions.json")
    private static let modesURL = dbDirectory.appendingPathComponent("ModeConfigurations.json")

    private(set) var currentFocusMode: String?
    var onChange: (() -> Void)?

    private var directorySource: DispatchSourceFileSystemObject?
    private var pollTimer: Timer?
    private var pendingRefresh: DispatchWorkItem?
    private let queue = DispatchQueue(label: "sharpfocus.focusmode")

    /// True when the database is readable (i.e. Full Disk Access is granted).
    /// `access(2)` is TCC-gated too, so this needs no actual read.
    static var hasAccess: Bool {
        FileManager.default.isReadableFile(atPath: assertionsURL.path)
    }

    static func openFullDiskAccessSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!
        NSWorkspace.shared.open(url)
    }

    /// Names of all configured Focus modes, for the rule editor. Refreshed
    /// together with the active mode.
    private(set) var knownModes: [String] = []

    private static func loadKnownModes() -> [String] {
        guard let configs = modeConfigurations() else { return [] }
        return configs.values
            .compactMap { ($0["mode"] as? [String: Any])?["name"] as? String }
            .sorted()
    }

    func start() {
        guard directorySource == nil else { return }
        refresh()

        // donotdisturbd rewrites the files atomically (write + rename), so we
        // watch the directory rather than a file inode.
        let fd = open(Self.dbDirectory.path, O_EVTONLY)
        if fd >= 0 {
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: queue)
            source.setEventHandler { [weak self] in self?.scheduleRefresh() }
            source.setCancelHandler { close(fd) }
            source.resume()
            directorySource = source
        }

        // Safety net for activations that don't go through the assertion
        // store (schedules, other devices), and for when the watch failed.
        let timer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in self?.refresh() }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    func stop() {
        directorySource?.cancel()
        directorySource = nil
        pollTimer?.invalidate()
        pollTimer = nil
    }

    private func scheduleRefresh() {
        pendingRefresh?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.refresh() }
        pendingRefresh = work
        queue.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    private func refresh() {
        // File I/O off the main thread; publish on main.
        queue.async { [weak self] in
            let mode = Self.readActiveModeName()
            let modes = Self.loadKnownModes()
            DispatchQueue.main.async {
                guard let self else { return }
                self.knownModes = modes
                guard mode != self.currentFocusMode else { return }
                self.currentFocusMode = mode
                NSLog("SharpFocus: Focus mode is now \(mode ?? "none")")
                self.onChange?()
            }
        }
    }

    // MARK: - Parsing

    private static func json(at url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    /// `data[0].modeConfigurations[<identifier>]`
    private static func modeConfigurations() -> [String: [String: Any]]? {
        guard let root = json(at: modesURL),
              let store = (root["data"] as? [[String: Any]])?.first
        else { return nil }
        return store["modeConfigurations"] as? [String: [String: Any]]
    }

    /// `data[0].storeAssertionRecords[].assertionDetails.assertionDetailsModeIdentifier`
    private static func readActiveModeName() -> String? {
        guard let root = json(at: assertionsURL),
              let store = (root["data"] as? [[String: Any]])?.first,
              let records = store["storeAssertionRecords"] as? [[String: Any]]
        else { return nil }

        let identifier = records
            .sorted {
                ($0["assertionStartDateTimestamp"] as? Double ?? 0)
                    > ($1["assertionStartDateTimestamp"] as? Double ?? 0)
            }
            .compactMap { ($0["assertionDetails"] as? [String: Any])?["assertionDetailsModeIdentifier"] as? String }
            .first
        guard let identifier else { return nil }

        if let mode = modeConfigurations()?[identifier]?["mode"] as? [String: Any],
           let name = mode["name"] as? String {
            return name
        }
        // Fallback: derive something readable from the identifier.
        return identifier.split(separator: ".").last.map { String($0).capitalized }
    }
}
