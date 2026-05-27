import Foundation
import ApplicationServices

private func eventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passRetained(event) }
    let manager = Unmanaged<HotkeyManager>.fromOpaque(userInfo).takeUnretainedValue()

    if type == .tapDisabledByTimeout {
        manager.reenableTap()
        return Unmanaged.passRetained(event)
    }

    return manager.handleEvent(type: type, event: event)
}

class HotkeyManager {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var tapThread: Thread?
    private var tapRunLoop: CFRunLoop?

    private var hotkey: Hotkey = .defaultHotkey
    private var onPress: (() -> Void)?
    private var onRelease: (() -> Void)?

    private var previousFlags: UInt64 = 0
    private var isHotkeyDown = false

    func startListening(for hotkey: Hotkey, onPress: @escaping () -> Void, onRelease: @escaping () -> Void) {
        stopListening()

        guard AXIsProcessTrusted() else { return }

        self.hotkey = hotkey
        self.onPress = onPress
        self.onRelease = onRelease
        self.previousFlags = 0
        self.isHotkeyDown = false

        let eventMask: CGEventMask = (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: eventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return
        }

        self.eventTap = tap
        self.runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)

        let thread = Thread { [weak self] in
            guard let self, let source = self.runLoopSource else { return }
            self.tapRunLoop = CFRunLoopGetCurrent()
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            CFRunLoopRun()
        }
        thread.name = "com.flowclone.hotkey-tap"
        thread.qualityOfService = .userInteractive
        thread.start()
        self.tapThread = thread
    }

    func stopListening() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let runLoop = tapRunLoop {
            CFRunLoopStop(runLoop)
        }
        if let source = runLoopSource, let runLoop = tapRunLoop {
            CFRunLoopRemoveSource(runLoop, source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        tapThread = nil
        tapRunLoop = nil
        isHotkeyDown = false
    }

    fileprivate func reenableTap() {
        guard let tap = eventTap else { return }
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    fileprivate func handleEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if hotkey.isModifierOnly {
            return handleModifierOnlyHotkey(type: type, event: event)
        } else {
            return handleKeyComboHotkey(type: type, event: event)
        }
    }

    private func handleModifierOnlyHotkey(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        guard type == .flagsChanged else { return Unmanaged.passRetained(event) }

        let currentFlags = event.flags.rawValue
        let targetBit = hotkey.modifiers
        let wasDown = previousFlags & targetBit != 0
        let isDown = currentFlags & targetBit != 0
        previousFlags = currentFlags

        if !wasDown && isDown && !isHotkeyDown {
            isHotkeyDown = true
            let press = onPress
            Task { @MainActor in press?() }
            return nil
        } else if wasDown && !isDown && isHotkeyDown {
            isHotkeyDown = false
            let release = onRelease
            Task { @MainActor in release?() }
            return nil
        }

        return Unmanaged.passRetained(event)
    }

    private func handleKeyComboHotkey(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .flagsChanged {
            let currentFlags = event.flags.rawValue
            if isHotkeyDown {
                let requiredModifiers = hotkey.modifiers
                let hasModifiers = currentFlags & requiredModifiers == requiredModifiers
                if !hasModifiers {
                    isHotkeyDown = false
                    let release = onRelease
                    Task { @MainActor in release?() }
                }
            }
            previousFlags = currentFlags
            return Unmanaged.passRetained(event)
        }

        let eventKeyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let eventModifiers = event.flags.rawValue
        let requiredModifiers = hotkey.modifiers

        let modifierMask: UInt64 = CGEventFlags.maskCommand.rawValue
            | CGEventFlags.maskShift.rawValue
            | CGEventFlags.maskAlternate.rawValue
            | CGEventFlags.maskControl.rawValue

        let relevantEventModifiers = eventModifiers & modifierMask
        let relevantRequiredModifiers = requiredModifiers & modifierMask

        guard eventKeyCode == hotkey.keyCode && relevantEventModifiers == relevantRequiredModifiers else {
            return Unmanaged.passRetained(event)
        }

        if type == .keyDown {
            if !isHotkeyDown {
                isHotkeyDown = true
                let press = onPress
                Task { @MainActor in press?() }
            }
            return nil
        } else if type == .keyUp {
            if isHotkeyDown {
                isHotkeyDown = false
                let release = onRelease
                Task { @MainActor in release?() }
            }
            return nil
        }

        return Unmanaged.passRetained(event)
    }

    deinit {
        stopListening()
    }
}
