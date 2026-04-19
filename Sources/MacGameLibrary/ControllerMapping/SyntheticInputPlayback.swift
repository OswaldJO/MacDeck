import AppKit
import Carbon.HIToolbox
import CoreGraphics
import Foundation

/// Posts synthetic keyboard/mouse events. Requires **Accessibility** permission for global injection.
enum SyntheticInputPlayback {
    static func perform(_ action: MappedAction) {
        switch action {
        case .keyboardKey(let code):
            postKey(code, down: true)
            postKey(code, down: false)
        case .numpadDigit(let digit):
            guard let code = numpadVirtualKey(for: digit) else { return }
            postKey(code, down: true)
            postKey(code, down: false)
        case .mouseButton(let raw):
            postMouseClick(raw: raw)
        case .scrollVertical(let lines):
            postScroll(deltaY: lines)
        case .trackpadScrollVertical(let lines):
            postScroll(deltaY: lines)
        }
    }

    private static func postKey(_ code: CGKeyCode, down: Bool) {
        guard let e = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down) else { return }
        e.post(tap: .cghidEventTap)
    }

    private static func postMouseClick(raw: UInt32) {
        let loc = NSEvent.mouseLocation
        let button: CGMouseButton
        let downType: CGEventType
        let upType: CGEventType
        switch raw {
        case 0:
            button = .left
            downType = .leftMouseDown
            upType = .leftMouseUp
        case 1:
            button = .right
            downType = .rightMouseDown
            upType = .rightMouseUp
        case 2:
            button = .center
            downType = .otherMouseDown
            upType = .otherMouseUp
        default:
            button = .left
            downType = .leftMouseDown
            upType = .leftMouseUp
        }

        guard let down = CGEvent(mouseEventSource: nil, mouseType: downType, mouseCursorPosition: loc, mouseButton: button),
              let up = CGEvent(mouseEventSource: nil, mouseType: upType, mouseCursorPosition: loc, mouseButton: button) else { return }
        if raw == 2 {
            down.setIntegerValueField(.mouseEventButtonNumber, value: 2)
            up.setIntegerValueField(.mouseEventButtonNumber, value: 2)
        }
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    private static func postScroll(deltaY: Int) {
        guard let e = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: Int32(deltaY), wheel2: 0, wheel3: 0) else { return }
        e.post(tap: .cghidEventTap)
    }

    private static func numpadVirtualKey(for digit: Int) -> CGKeyCode? {
        switch digit {
        case 0: return CGKeyCode(kVK_ANSI_Keypad0)
        case 1: return CGKeyCode(kVK_ANSI_Keypad1)
        case 2: return CGKeyCode(kVK_ANSI_Keypad2)
        case 3: return CGKeyCode(kVK_ANSI_Keypad3)
        case 4: return CGKeyCode(kVK_ANSI_Keypad4)
        case 5: return CGKeyCode(kVK_ANSI_Keypad5)
        case 6: return CGKeyCode(kVK_ANSI_Keypad6)
        case 7: return CGKeyCode(kVK_ANSI_Keypad7)
        case 8: return CGKeyCode(kVK_ANSI_Keypad8)
        case 9: return CGKeyCode(kVK_ANSI_Keypad9)
        default: return nil
        }
    }
}
