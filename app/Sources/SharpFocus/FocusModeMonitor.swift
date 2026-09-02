import AppKit

/// Reads the active macOS Focus mode from the DoNotDisturb database
/// (~/Library/DoNotDisturb/DB). There is no public API that names the active
/// Focus; these files are what every current tool uses. Reading them requires
/// Full Disk Access on macOS 14+, so this is strictly opt-in: without access
/// the monitor reports nil and the UI offers to open the right settings pane.
final class FocusModeMonitor: FocusModeProviding {
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
    static var hasAccess: Bool {
        (try? Data(contentsOf: assertionsURL)) != nil
    }

    static func openFullDiskAccessSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!
        NSWorkspace.shared.open(url)
    }

    /// Names of all configured Focus modes, for the rule editor.
    var knownModes: [String] {
        guard let configs = Self.modeConfigurations() else { return [] }
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
        let work = DispatchWorkItem { [weak self] in
            DispatchQueue.main.async { self?.refresh() }
        }
        pendingRefresh = work
        queue.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    private func refresh() {
        let mode = Self.readActiveModeName()
        guard mode != currentFocusMode else { return }
        currentFocusMode = mode
        NSLog("SharpFocus: Focus mode is now \(mode ?? "none")")
        onChange?()
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
