import Foundation

/// Named physical controls for extended gamepads (strings align with `GCExtendedGamepad` properties).
struct GamepadElementOption: Identifiable, Hashable, Sendable {
    var id: String { elementID }
    var elementID: String
    var label: String
}

enum GamepadElementCatalog {
    static let extendedGamepad: [GamepadElementOption] = [
        .init(elementID: "buttonA", label: "A"),
        .init(elementID: "buttonB", label: "B"),
        .init(elementID: "buttonX", label: "X"),
        .init(elementID: "buttonY", label: "Y"),
        .init(elementID: "leftShoulder", label: "Left shoulder"),
        .init(elementID: "rightShoulder", label: "Right shoulder"),
        .init(elementID: "leftTrigger", label: "Left trigger"),
        .init(elementID: "rightTrigger", label: "Right trigger"),
        .init(elementID: "leftThumbstickButton", label: "Left stick click"),
        .init(elementID: "rightThumbstickButton", label: "Right stick click"),
        .init(elementID: "dpadUp", label: "D-pad up"),
        .init(elementID: "dpadDown", label: "D-pad down"),
        .init(elementID: "dpadLeft", label: "D-pad left"),
        .init(elementID: "dpadRight", label: "D-pad right"),
        .init(elementID: "buttonMenu", label: "Menu"),
        .init(elementID: "buttonOptions", label: "Options")
    ]
}
