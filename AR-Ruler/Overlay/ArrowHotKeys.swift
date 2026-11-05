import AppKit
import Carbon.HIToolbox

/// Modifier + arrow keys, registered only while a ruler exists. Unlike an event monitor, a Carbon hot key
/// consumes the key press, so the nudge doesn't also move the caret in the app underneath.
final class ArrowHotKeys {
    var onNudge: ((CGVector) -> Void)?

    private static let signature: OSType = 0x4152_524E // 'ARRN'
    private static let arrows: [(keyCode: Int, delta: CGVector)] = [
        (kVK_LeftArrow, CGVector(dx: -1, dy: 0)),
        (kVK_RightArrow, CGVector(dx: 1, dy: 0)),
        (kVK_UpArrow, CGVector(dx: 0, dy: 1)),
        (kVK_DownArrow, CGVector(dx: 0, dy: -1))
    ]

    private var refs: [EventHotKeyRef] = []
    private var handler: EventHandlerRef?
    private var repeatTimer: Timer?
    private(set) var registeredModifier: ModifierKey?

    deinit {
        unregister()
        if let handler { RemoveEventHandler(handler) }
    }

    func register(modifier: ModifierKey) {
        guard registeredModifier != modifier else { return }
        unregister()
        installHandlerIfNeeded()
        let carbonModifier: Int
        switch modifier {
        case .option: carbonModifier = optionKey
        case .control: carbonModifier = controlKey
        case .command: carbonModifier = cmdKey
        }
        for (index, arrow) in Self.arrows.enumerated() {
            var ref: EventHotKeyRef?
            let id = EventHotKeyID(signature: Self.signature, id: UInt32(index))
            let status = RegisterEventHotKey(UInt32(arrow.keyCode), UInt32(carbonModifier), id, GetApplicationEventTarget(), 0, &ref)
            if status == noErr, let ref {
                refs.append(ref)
            } else {
                NSLog("AR Ruler: couldn't register nudge key %d (status %d); another app may own it", arrow.keyCode, status)
            }
        }
        registeredModifier = modifier
    }

    func unregister() {
        stopRepeating()
        refs.forEach { UnregisterEventHotKey($0) }
        refs = []
        registeredModifier = nil
    }

    private func installHandlerIfNeeded() {
        guard handler == nil else { return }
        var types = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))
        ]
        let callback: EventHandlerUPP = { _, event, userData in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            let hotKeys = Unmanaged<ArrowHotKeys>.fromOpaque(userData).takeUnretainedValue()
            var id = EventHotKeyID()
            let status = GetEventParameter(
                event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                nil, MemoryLayout<EventHotKeyID>.size, nil, &id
            )
            guard status == noErr, id.signature == ArrowHotKeys.signature, Int(id.id) < ArrowHotKeys.arrows.count else {
                return OSStatus(eventNotHandledErr)
            }
            if GetEventKind(event) == UInt32(kEventHotKeyPressed) {
                hotKeys.pressed(Int(id.id))
            } else {
                hotKeys.stopRepeating()
            }
            return noErr
        }
        InstallEventHandler(GetApplicationEventTarget(), callback, types.count, &types, Unmanaged.passUnretained(self).toOpaque(), &handler)
    }

    /// Hot keys fire once per press, so holding the key has to be repeated by hand.
    private func pressed(_ index: Int) {
        let arrow = Self.arrows[index]
        onNudge?(arrow.delta)
        stopRepeating()
        repeatTimer = Timer(timeInterval: 0.35, repeats: false) { [weak self] _ in
            guard let self else { return }
            let timer = Timer(timeInterval: 0.04, repeats: true) { [weak self] _ in
                guard let self else { return }
                guard CGEventSource.keyState(.combinedSessionState, key: CGKeyCode(arrow.keyCode)) else {
                    self.stopRepeating()
                    return
                }
                self.onNudge?(arrow.delta)
            }
            self.repeatTimer = timer
            RunLoop.main.add(timer, forMode: .common)
            self.onNudge?(arrow.delta)
        }
        if let repeatTimer { RunLoop.main.add(repeatTimer, forMode: .common) }
    }

    private func stopRepeating() {
        repeatTimer?.invalidate()
        repeatTimer = nil
    }
}
