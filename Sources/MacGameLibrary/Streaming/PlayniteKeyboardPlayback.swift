import AppKit
import CoreGraphics
import Foundation

/// Posts keyboard events from companion `PNK1` packets (Windows VK in Moonlight short codes).
enum PlayniteKeyboardPlayback {
    private nonisolated(unsafe) static var loggedMissingTrust = false

    static func handle(_ event: PlayniteKeyboardEventFormat.Event) {
        guard AXIsProcessTrusted() else {
            if !loggedMissingTrust {
                loggedMissingTrust = true
                print(
                    "[PlayniteInput] Accessibility not granted — keyboard mapping requires " +
                        "“\(AccessibilityPermission.settingsAppName)” in Accessibility settings."
                )
            }
            return
        }
        loggedMissingTrust = false

        let vk = UInt16(event.moonlightKeyCode & 0xFF)
        guard let keyCode = cgKeyCode(forWindowsVK: vk) else { return }
        guard let keyEvent = CGEvent(
            keyboardEventSource: nil,
            virtualKey: keyCode,
            keyDown: event.down
        ) else { return }
        keyEvent.post(tap: .cghidEventTap)
    }

    private static func cgKeyCode(forWindowsVK vk: UInt16) -> CGKeyCode? {
        switch vk {
        case 0x41 ... 0x5A: return CGKeyCode(vk - 0x41) // A-Z
        case 0x30 ... 0x39: return CGKeyCode(vk - 0x30 + 29) // 0-9
        case 0x20: return 49 // space
        case 0x0D: return 36 // return
        case 0x1B: return 53 // escape
        case 0x09: return 48 // tab
        case 0x08: return 51 // backspace
        case 0x10: return 56 // left shift
        case 0x11: return 59 // left control
        case 0x12: return 58 // legacy Alt → left option
        case 0xA4: return 58 // left option (VK_LMENU)
        case 0xA5: return 61 // right option (VK_RMENU)
        case 0x5B: return 55 // left command (VK_LWIN, Moonlight → Mac)
        case 0x5C: return 54 // right command (VK_RWIN)
        case 0x26: return 126 // up
        case 0x28: return 125 // down
        case 0x25: return 123 // left
        case 0x27: return 124 // right
        case 0x70 ... 0x7B: return CGKeyCode(vk - 0x70 + 122) // F1-F12
        default:
            return nil
        }
    }
}
