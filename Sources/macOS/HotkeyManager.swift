import Carbon
import AppKit

/// Registers and manages the global Cmd+Shift+I hotkey using Carbon's RegisterEventHotKey.
final class HotkeyManager {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private let handler: () -> Void

    // Unique ID for our hotkey event
    private static let hotkeyID = EventHotKeyID(signature: OSType(0x4244_5554), id: 1) // 'BDUT'

    init(handler: @escaping () -> Void) {
        self.handler = handler
        register()
    }

    deinit {
        unregister()
    }

    // MARK: - Registration

    private func register() {
        // Install application event handler
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))

        let selfPtr = Unmanaged.passRetained(self).toOpaque()

        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, event, userData) -> OSStatus in
                guard let userData = userData else { return OSStatus(eventNotHandledErr) }
                let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()

                var hotkeyID = EventHotKeyID()
                GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotkeyID
                )

                if hotkeyID.signature == HotkeyManager.hotkeyID.signature,
                   hotkeyID.id == HotkeyManager.hotkeyID.id {
                    manager.handler()
                    return noErr
                }
                return OSStatus(eventNotHandledErr)
            },
            1,
            &eventType,
            selfPtr,
            &eventHandlerRef
        )

        guard status == noErr else {
            print("[BrainDump] Failed to install hotkey event handler: \(status)")
            Unmanaged<HotkeyManager>.fromOpaque(selfPtr).release()
            return
        }

        // Cmd+Shift+I: keyCode 34 = 'i', modifiers = cmdKey | shiftKey
        let registerStatus = RegisterEventHotKey(
            34,                          // kVK_ANSI_I
            UInt32(cmdKey | shiftKey),
            HotkeyManager.hotkeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        if registerStatus != noErr {
            print("[BrainDump] Failed to register global hotkey: \(registerStatus)")
        }
    }

    private func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
        if let ref = eventHandlerRef {
            RemoveEventHandler(ref)
            eventHandlerRef = nil
        }
    }
}
