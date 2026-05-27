import SwiftUI
import AppKit
import Carbon.HIToolbox

struct HotkeyCaptureField: NSViewRepresentable {
    @Binding var hotkey: Hotkey

    func makeNSView(context: Context) -> HotkeyCaptureNSView {
        let view = HotkeyCaptureNSView()
        view.hotkey = hotkey
        view.onCapture = { newHotkey in
            hotkey = newHotkey
        }
        return view
    }

    func updateNSView(_ nsView: HotkeyCaptureNSView, context: Context) {
        nsView.hotkey = hotkey
        nsView.needsDisplay = true
    }
}

class HotkeyCaptureNSView: NSView {
    var hotkey: Hotkey = .defaultHotkey
    var onCapture: ((Hotkey) -> Void)?
    private var isCapturing = false
    private var trackingArea: NSTrackingArea?

    override var acceptsFirstResponder: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: NSRect(x: 0, y: 0, width: 200, height: 28))
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 200, height: 28)
    }

    override func draw(_ dirtyRect: NSRect) {
        let bgColor: NSColor = isCapturing ? .controlAccentColor.withAlphaComponent(0.1) : .controlBackgroundColor
        bgColor.setFill()
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 6, yRadius: 6)
        path.fill()

        let borderColor: NSColor = isCapturing ? .controlAccentColor : .separatorColor
        borderColor.setStroke()
        path.lineWidth = 1
        path.stroke()

        let text: String = isCapturing ? "Press a key combination..." : hotkey.displayString
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13),
            .foregroundColor: isCapturing ? NSColor.secondaryLabelColor : NSColor.labelColor
        ]
        let attrString = NSAttributedString(string: text, attributes: attrs)
        let textSize = attrString.size()
        let textRect = NSRect(
            x: (bounds.width - textSize.width) / 2,
            y: (bounds.height - textSize.height) / 2,
            width: textSize.width,
            height: textSize.height
        )
        attrString.draw(in: textRect)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        isCapturing = true
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        guard isCapturing else { return }

        let keyCode = event.keyCode
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let modifierRaw = CGEventFlags(rawValue: UInt64(modifiers.rawValue)).rawValue

        let captured = Hotkey(keyCode: keyCode, modifiers: modifierRaw)
        hotkey = captured
        onCapture?(captured)
        isCapturing = false
        needsDisplay = true
    }

    override func flagsChanged(with event: NSEvent) {
        guard isCapturing else { return }

        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if modifiers.isEmpty { return }

        let deviceFlags = event.modifierFlags.rawValue
        var specificModifier: UInt64 = 0

        if deviceFlags & UInt(NX_DEVICERALTKEYMASK) != 0 {
            specificModifier = 0x00000040
        } else if deviceFlags & UInt(NX_DEVICELALTKEYMASK) != 0 {
            specificModifier = 0x00000020
        } else if deviceFlags & UInt(NX_DEVICERCTLKEYMASK) != 0 {
            specificModifier = UInt64(NX_DEVICERCTLKEYMASK)
        } else if deviceFlags & UInt(NX_DEVICELCTLKEYMASK) != 0 {
            specificModifier = UInt64(NX_DEVICELCTLKEYMASK)
        } else {
            specificModifier = UInt64(modifiers.rawValue)
        }

        let captured = Hotkey(keyCode: 0, modifiers: specificModifier)
        hotkey = captured
        onCapture?(captured)
        isCapturing = false
        needsDisplay = true
    }

    override func resignFirstResponder() -> Bool {
        isCapturing = false
        needsDisplay = true
        return super.resignFirstResponder()
    }
}
