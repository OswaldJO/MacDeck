/// Gamepad controls mappable during Moonlight streaming (matches Mac host catalog ids).
class GamepadElement {
  const GamepadElement({required this.id, required this.label});

  final String id;
  final String label;
}

const List<GamepadElement> kMappableGamepadElements = [
  GamepadElement(id: 'buttonA', label: 'A / Cross'),
  GamepadElement(id: 'buttonB', label: 'B / Circle'),
  GamepadElement(id: 'buttonX', label: 'X / Square'),
  GamepadElement(id: 'buttonY', label: 'Y / Triangle'),
  GamepadElement(id: 'leftShoulder', label: 'Left bumper (L1)'),
  GamepadElement(id: 'rightShoulder', label: 'Right bumper (R1)'),
  GamepadElement(id: 'leftTrigger', label: 'Left trigger (L2)'),
  GamepadElement(id: 'rightTrigger', label: 'Right trigger (R2)'),
  GamepadElement(id: 'leftThumbstickButton', label: 'Left stick click (L3)'),
  GamepadElement(id: 'leftStickUp', label: 'Left stick up'),
  GamepadElement(id: 'leftStickDown', label: 'Left stick down'),
  GamepadElement(id: 'leftStickLeft', label: 'Left stick left'),
  GamepadElement(id: 'leftStickRight', label: 'Left stick right'),
  GamepadElement(id: 'rightThumbstickButton', label: 'Right stick click (R3)'),
  GamepadElement(id: 'rightStickUp', label: 'Right stick up'),
  GamepadElement(id: 'rightStickDown', label: 'Right stick down'),
  GamepadElement(id: 'rightStickLeft', label: 'Right stick left'),
  GamepadElement(id: 'rightStickRight', label: 'Right stick right'),
  GamepadElement(id: 'dpadUp', label: 'D-pad up'),
  GamepadElement(id: 'dpadDown', label: 'D-pad down'),
  GamepadElement(id: 'dpadLeft', label: 'D-pad left'),
  GamepadElement(id: 'dpadRight', label: 'D-pad right'),
  GamepadElement(id: 'buttonMenu', label: 'Start / Menu'),
  GamepadElement(id: 'buttonOptions', label: 'Select / Options'),
  GamepadElement(id: 'macro1', label: 'Macro 1'),
  GamepadElement(id: 'macro2', label: 'Macro 2'),
  GamepadElement(id: 'macro3', label: 'Macro 3'),
  GamepadElement(id: 'macro4', label: 'Macro 4'),
];

GamepadElement? gamepadElementById(String id) {
  for (final element in kMappableGamepadElements) {
    if (element.id == id) return element;
  }
  return null;
}
