import AppKit

final class FocusModeMonitor {
    static let shared = FocusModeMonitor()

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

    static var hasAccess: Bool {
        FileManager.default.isReadableFile(atPath: assertionsURL.path)
    }

    static func openFullDiskAccessSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!
        NSWorkspace.shared.open(url)
    }

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

        let fd = open(Self.dbDirectory.path, O_EVTONLY)
        if fd >= 0 {
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: queue)
            source.setEventHandler { [weak self] in self?.scheduleRefresh() }
            source.setCancelHandler { close(fd) }
            source.resume()
            directorySource = source
        }

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

    private static func json(at url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private static func modeConfigurations() -> [String: [String: Any]]? {
        guard let root = json(at: modesURL),
              let store = (root["data"] as? [[String: Any]])?.first
        else { return nil }
        return store["modeConfigurations"] as? [String: [String: Any]]
    }

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
        return identifier.split(separator: ".").last.map { String($0).capitalized }
    }
}
