import Carbon.HIToolbox
import Foundation

/// Global hotkeys via Carbon's RegisterEventHotKey — works without
/// Accessibility permission, unlike event taps or NSEvent global monitors.
final class HotKeyCenter {
    static let shared = HotKeyCenter()

    private var handlers: [UInt32: () -> Void] = [:]
    private var hotKeyRefs: [EventHotKeyRef?] = []
    private var nextID: UInt32 = 1
    private var eventHandlerInstalled = false

    private init() {}

    /// `modifiers` uses Carbon flags, e.g. `UInt32(cmdKey | optionKey | controlKey)`.
    func register(keyCode: UInt32, modifiers: UInt32, handler: @escaping () -> Void) {
        installEventHandlerIfNeeded()

        let id = nextID
        nextID += 1
        handlers[id] = handler

        var hotKeyRef: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x5346_4F43) /* 'SFOC' */, id: id)
        RegisterEventHotKey(
            keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
        hotKeyRefs.append(hotKeyRef)
    }

    private func installEventHandlerIfNeeded() {
        guard !eventHandlerInstalled else { return }
        eventHandlerInstalled = true

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData -> OSStatus in
                guard let userData, let event else { return noErr }
                var hotKeyID = EventHotKeyID()
                GetEventParameter(
                    event, EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID), nil,
                    MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
                let center = Unmanaged<HotKeyCenter>.fromOpaque(userData).takeUnretainedValue()
                center.handlers[hotKeyID.id]?()
                return noErr
            },
            1, &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            nil)
    }
}
