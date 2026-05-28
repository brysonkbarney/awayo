import Carbon
import Foundation

enum AwayoHotKeyError: LocalizedError {
    case eventHandlerFailed(OSStatus)
    case registrationFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .eventHandlerFailed(let status):
            "Awayo could not prepare global hotkeys. macOS returned \(status)."
        case .registrationFailed(let status):
            "Awayo could not register that hotkey. It may already be used by macOS or another app. macOS returned \(status)."
        }
    }
}

final class AwayoHotKeyManager: @unchecked Sendable {
    private static let signature = fourCharacterCode("Awyo")
    private static let hotKeyID = UInt32(1)

    private var eventHandlerRef: EventHandlerRef?
    private var hotKeyRef: EventHotKeyRef?
    private var handler: (() -> Void)?

    deinit {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }

        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
        }
    }

    func register(_ hotKey: AwayoHotKey?, handler: @escaping () -> Void) throws {
        unregister()
        self.handler = handler

        guard let hotKey else {
            return
        }

        try installEventHandlerIfNeeded()

        let hotKeyID = EventHotKeyID(signature: Self.signature, id: Self.hotKeyID)
        var newHotKeyRef: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(hotKey.keyCode),
            hotKey.carbonModifierFlags,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &newHotKeyRef
        )

        guard status == noErr, let newHotKeyRef else {
            throw AwayoHotKeyError.registrationFailed(status)
        }

        hotKeyRef = newHotKeyRef
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
    }

    private func installEventHandlerIfNeeded() throws {
        guard eventHandlerRef == nil else {
            return
        }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, eventRef, userData in
                guard let eventRef, let userData else {
                    return noErr
                }

                var eventHotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    eventRef,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &eventHotKeyID
                )

                guard status == noErr else {
                    return status
                }

                let manager = Unmanaged<AwayoHotKeyManager>
                    .fromOpaque(userData)
                    .takeUnretainedValue()

                DispatchQueue.main.async {
                    manager.handleHotKey(eventHotKeyID)
                }

                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerRef
        )

        guard status == noErr else {
            throw AwayoHotKeyError.eventHandlerFailed(status)
        }
    }

    private func handleHotKey(_ eventHotKeyID: EventHotKeyID) {
        guard eventHotKeyID.signature == Self.signature,
              eventHotKeyID.id == Self.hotKeyID else {
            return
        }

        handler?()
    }

    private static func fourCharacterCode(_ value: String) -> OSType {
        value.utf8.reduce(0) { result, byte in
            (result << 8) + OSType(byte)
        }
    }
}
