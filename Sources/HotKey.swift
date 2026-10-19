import Carbon.HIToolbox

/// System wide hotkey via Carbon. Needs no accessibility permission and reports
/// both press and release, which the hold-to-stop gesture relies on.
final class HotKey {
    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?

    private var ref: EventHotKeyRef?
    private let id: UInt32

    private static var registry: [UInt32: HotKey] = [:]
    private static var handlerInstalled = false

    init?(keyCode: Int, modifiers: Int, id: UInt32 = 1) {
        self.id = id
        HotKey.installHandler()
        let hotKeyID = EventHotKeyID(signature: OSType(0x5647_4C54), id: id) // 'VGLT'
        let status = RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), hotKeyID,
                                         GetApplicationEventTarget(), 0, &ref)
        guard status == noErr else { return nil }
        HotKey.registry[id] = self
    }

    deinit {
        if let ref { UnregisterEventHotKey(ref) }
        HotKey.registry[id] = nil
    }

    private static func installHandler() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var specs = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            guard let event else { return OSStatus(eventNotHandledErr) }
            var hotKeyID = EventHotKeyID()
            let err = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                        nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            guard err == noErr, let hotKey = HotKey.registry[hotKeyID.id] else { return OSStatus(eventNotHandledErr) }
            switch Int(GetEventKind(event)) {
            case kEventHotKeyPressed: hotKey.onPress?()
            case kEventHotKeyReleased: hotKey.onRelease?()
            default: break
            }
            return noErr
        }, specs.count, &specs, nil, nil)
    }
}
