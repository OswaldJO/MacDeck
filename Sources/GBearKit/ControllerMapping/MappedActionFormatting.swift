import Foundation

extension MappedAction {
    /// Short label for lists and accessibility.
    var summary: String {
        switch self {
        case .keyboardKey(let code):
            if let match = VirtualKeyCatalog.allKeyboardAndNumpad.first(where: { $0.virtualKeyCode == code }) {
                return "Keyboard: \(match.label)"
            }
            return "Keyboard (key code \(code))"
        case .numpadDigit(let d):
            return "Numpad: \(d)"
        case .mouseButton(let b):
            let name: String
            switch b {
            case 0: name = "Left click"
            case 1: name = "Right click"
            case 2: name = "Middle click"
            default: name = "Mouse button \(b)"
            }
            return "Mouse: \(name)"
        case .scrollVertical(let y):
            return y >= 0 ? "Mouse wheel: up ×\(y)" : "Mouse wheel: down ×\(-y)"
        case .trackpadScrollVertical(let y):
            return y >= 0 ? "Trackpad: scroll up ×\(y)" : "Trackpad: scroll down ×\(-y)"
        }
    }
}
