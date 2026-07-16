import CoreGraphics
import Foundation

/// What a controller element should synthesize (keyboard, numpad, mouse, or scroll).
enum MappedAction: Codable, Equatable, Hashable, Sendable {
    /// macOS virtual key code (`kVK_*` / `CGKeyCode`).
    case keyboardKey(CGKeyCode)
    /// Keypad 0–9 (mapped to keypad virtual keys at playback).
    case numpadDigit(Int)
    /// `CGMouseButton` raw value (0 = left, 1 = right, 2 = middle).
    case mouseButton(UInt32)
    /// Discrete vertical scroll steps (positive = up).
    case scrollVertical(Int)
    /// Labeled separately from mouse wheel for UI; playback may use the same mechanism.
    case trackpadScrollVertical(Int)

    enum CodingKeys: String, CodingKey {
        case kind, keyboardKeyCode, numpadDigit, mouseButton, scrollVertical, trackpadScrollVertical
    }

    enum Kind: String, Codable { case keyboardKey, numpadDigit, mouseButton, scrollVertical, trackpadScrollVertical }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try c.decode(Kind.self, forKey: .kind)
        switch kind {
        case .keyboardKey:
            self = .keyboardKey(try c.decode(CGKeyCode.self, forKey: .keyboardKeyCode))
        case .numpadDigit:
            self = .numpadDigit(try c.decode(Int.self, forKey: .numpadDigit))
        case .mouseButton:
            self = .mouseButton(try c.decode(UInt32.self, forKey: .mouseButton))
        case .scrollVertical:
            self = .scrollVertical(try c.decode(Int.self, forKey: .scrollVertical))
        case .trackpadScrollVertical:
            self = .trackpadScrollVertical(try c.decode(Int.self, forKey: .trackpadScrollVertical))
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .keyboardKey(let code):
            try c.encode(Kind.keyboardKey, forKey: .kind)
            try c.encode(code, forKey: .keyboardKeyCode)
        case .numpadDigit(let d):
            try c.encode(Kind.numpadDigit, forKey: .kind)
            try c.encode(d, forKey: .numpadDigit)
        case .mouseButton(let b):
            try c.encode(Kind.mouseButton, forKey: .kind)
            try c.encode(b, forKey: .mouseButton)
        case .scrollVertical(let y):
            try c.encode(Kind.scrollVertical, forKey: .kind)
            try c.encode(y, forKey: .scrollVertical)
        case .trackpadScrollVertical(let y):
            try c.encode(Kind.trackpadScrollVertical, forKey: .kind)
            try c.encode(y, forKey: .trackpadScrollVertical)
        }
    }
}

struct ControllerBinding: Codable, Equatable, Identifiable, Hashable, Sendable {
    var id: UUID
    /// Stable id from `GamepadElementCatalog` (e.g. `buttonA`).
    var sourceElementID: String
    var sourceLabel: String
    var action: MappedAction

    init(id: UUID = UUID(), sourceElementID: String, sourceLabel: String, action: MappedAction) {
        self.id = id
        self.sourceElementID = sourceElementID
        self.sourceLabel = sourceLabel
        self.action = action
    }
}

struct ControllerMappingProfile: Codable, Equatable, Identifiable, Hashable, Sendable {
    var id: UUID
    var name: String
    var bindings: [ControllerBinding]

    init(id: UUID = UUID(), name: String, bindings: [ControllerBinding] = []) {
        self.id = id
        self.name = name
        self.bindings = bindings
    }
}
