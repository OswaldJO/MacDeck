import Carbon.HIToolbox
import Foundation

/// Preset keyboard targets for mapping UI (virtual key codes on macOS).
struct VirtualKeyOption: Identifiable, Hashable, Sendable {
    var id: String { "\(virtualKeyCode)" }
    var label: String
    var virtualKeyCode: CGKeyCode
}

enum VirtualKeyCatalog {
    static let common: [VirtualKeyOption] = {
        var rows: [VirtualKeyOption] = [
            .init(label: "Space", virtualKeyCode: CGKeyCode(kVK_Space)),
            .init(label: "Return", virtualKeyCode: CGKeyCode(kVK_Return)),
            .init(label: "Tab", virtualKeyCode: CGKeyCode(kVK_Tab)),
            .init(label: "Escape", virtualKeyCode: CGKeyCode(kVK_Escape)),
            .init(label: "Delete (backspace)", virtualKeyCode: CGKeyCode(kVK_Delete)),
            .init(label: "Forward delete", virtualKeyCode: CGKeyCode(kVK_ForwardDelete)),
        ]
        let letters = Array("WASD")
        for ch in letters {
            if let code = keyCodeForCharacter(ch) {
                rows.append(.init(label: String(ch).uppercased(), virtualKeyCode: code))
            }
        }
        let arrows: [(String, Int)] = [
            ("Arrow left", kVK_LeftArrow),
            ("Arrow right", kVK_RightArrow),
            ("Arrow down", kVK_DownArrow),
            ("Arrow up", kVK_UpArrow)
        ]
        for (label, v) in arrows {
            rows.append(.init(label: label, virtualKeyCode: CGKeyCode(v)))
        }
        let digitKeys: [CGKeyCode] = [
            CGKeyCode(kVK_ANSI_0), CGKeyCode(kVK_ANSI_1), CGKeyCode(kVK_ANSI_2), CGKeyCode(kVK_ANSI_3),
            CGKeyCode(kVK_ANSI_4), CGKeyCode(kVK_ANSI_5), CGKeyCode(kVK_ANSI_6), CGKeyCode(kVK_ANSI_7),
            CGKeyCode(kVK_ANSI_8), CGKeyCode(kVK_ANSI_9)
        ]
        for (i, code) in digitKeys.enumerated() {
            rows.append(.init(label: "Digit \(i)", virtualKeyCode: code))
        }
        for i in 1 ... 12 {
            rows.append(.init(label: "F\(i)", virtualKeyCode: CGKeyCode(kVK_F1 + (i - 1))))
        }
        return rows
    }()

    /// Main keyboard row + numpad keys for a single picker.
    static var allKeyboardAndNumpad: [VirtualKeyOption] {
        common + numpadDigits
    }

    static let numpadDigits: [VirtualKeyOption] = [
        .init(label: "Keypad 0", virtualKeyCode: CGKeyCode(kVK_ANSI_Keypad0)),
        .init(label: "Keypad 1", virtualKeyCode: CGKeyCode(kVK_ANSI_Keypad1)),
        .init(label: "Keypad 2", virtualKeyCode: CGKeyCode(kVK_ANSI_Keypad2)),
        .init(label: "Keypad 3", virtualKeyCode: CGKeyCode(kVK_ANSI_Keypad3)),
        .init(label: "Keypad 4", virtualKeyCode: CGKeyCode(kVK_ANSI_Keypad4)),
        .init(label: "Keypad 5", virtualKeyCode: CGKeyCode(kVK_ANSI_Keypad5)),
        .init(label: "Keypad 6", virtualKeyCode: CGKeyCode(kVK_ANSI_Keypad6)),
        .init(label: "Keypad 7", virtualKeyCode: CGKeyCode(kVK_ANSI_Keypad7)),
        .init(label: "Keypad 8", virtualKeyCode: CGKeyCode(kVK_ANSI_Keypad8)),
        .init(label: "Keypad 9", virtualKeyCode: CGKeyCode(kVK_ANSI_Keypad9)),
        .init(label: "Keypad Enter", virtualKeyCode: CGKeyCode(kVK_ANSI_KeypadEnter)),
        .init(label: "Keypad +", virtualKeyCode: CGKeyCode(kVK_ANSI_KeypadPlus)),
        .init(label: "Keypad −", virtualKeyCode: CGKeyCode(kVK_ANSI_KeypadMinus)),
        .init(label: "Keypad *", virtualKeyCode: CGKeyCode(kVK_ANSI_KeypadMultiply)),
        .init(label: "Keypad /", virtualKeyCode: CGKeyCode(kVK_ANSI_KeypadDivide)),
        .init(label: "Keypad .", virtualKeyCode: CGKeyCode(kVK_ANSI_KeypadDecimal)),
    ]

    private static func keyCodeForCharacter(_ ch: Character) -> CGKeyCode? {
        let upper = String(ch).uppercased()
        guard let first = upper.unicodeScalars.first else { return nil }
        let v = Int(first.value)
        if v >= Int(UnicodeScalar("A").value), v <= Int(UnicodeScalar("Z").value) {
            return CGKeyCode(kVK_ANSI_A + (v - Int(UnicodeScalar("A").value)))
        }
        return nil
    }
}
