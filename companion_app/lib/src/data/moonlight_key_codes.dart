/// Windows virtual-key codes sent to the Mac via Moonlight (0x80 prefix applied natively).
class MoonlightKeyOption {
  const MoonlightKeyOption({required this.label, required this.windowsVk});

  final String label;
  final int windowsVk;

  /// Moonlight short key code: `(0x80 << 8) | windowsVk`.
  int get moonlightKeyCode => (0x80 << 8) | windowsVk;
}

const List<MoonlightKeyOption> kMoonlightKeyboardKeys = [
  MoonlightKeyOption(label: 'A', windowsVk: 0x41),
  MoonlightKeyOption(label: 'B', windowsVk: 0x42),
  MoonlightKeyOption(label: 'C', windowsVk: 0x43),
  MoonlightKeyOption(label: 'D', windowsVk: 0x44),
  MoonlightKeyOption(label: 'E', windowsVk: 0x45),
  MoonlightKeyOption(label: 'F', windowsVk: 0x46),
  MoonlightKeyOption(label: 'G', windowsVk: 0x47),
  MoonlightKeyOption(label: 'H', windowsVk: 0x48),
  MoonlightKeyOption(label: 'I', windowsVk: 0x49),
  MoonlightKeyOption(label: 'J', windowsVk: 0x4A),
  MoonlightKeyOption(label: 'K', windowsVk: 0x4B),
  MoonlightKeyOption(label: 'L', windowsVk: 0x4C),
  MoonlightKeyOption(label: 'M', windowsVk: 0x4D),
  MoonlightKeyOption(label: 'N', windowsVk: 0x4E),
  MoonlightKeyOption(label: 'O', windowsVk: 0x4F),
  MoonlightKeyOption(label: 'P', windowsVk: 0x50),
  MoonlightKeyOption(label: 'Q', windowsVk: 0x51),
  MoonlightKeyOption(label: 'R', windowsVk: 0x52),
  MoonlightKeyOption(label: 'S', windowsVk: 0x53),
  MoonlightKeyOption(label: 'T', windowsVk: 0x54),
  MoonlightKeyOption(label: 'U', windowsVk: 0x55),
  MoonlightKeyOption(label: 'V', windowsVk: 0x56),
  MoonlightKeyOption(label: 'W', windowsVk: 0x57),
  MoonlightKeyOption(label: 'X', windowsVk: 0x58),
  MoonlightKeyOption(label: 'Y', windowsVk: 0x59),
  MoonlightKeyOption(label: 'Z', windowsVk: 0x5A),
  MoonlightKeyOption(label: '0', windowsVk: 0x30),
  MoonlightKeyOption(label: '1', windowsVk: 0x31),
  MoonlightKeyOption(label: '2', windowsVk: 0x32),
  MoonlightKeyOption(label: '3', windowsVk: 0x33),
  MoonlightKeyOption(label: '4', windowsVk: 0x34),
  MoonlightKeyOption(label: '5', windowsVk: 0x35),
  MoonlightKeyOption(label: '6', windowsVk: 0x36),
  MoonlightKeyOption(label: '7', windowsVk: 0x37),
  MoonlightKeyOption(label: '8', windowsVk: 0x38),
  MoonlightKeyOption(label: '9', windowsVk: 0x39),
  MoonlightKeyOption(label: 'Space', windowsVk: 0x20),
  MoonlightKeyOption(label: 'Enter', windowsVk: 0x0D),
  MoonlightKeyOption(label: 'Escape', windowsVk: 0x1B),
  MoonlightKeyOption(label: 'Tab', windowsVk: 0x09),
  MoonlightKeyOption(label: 'Backspace', windowsVk: 0x08),
  MoonlightKeyOption(label: 'Shift', windowsVk: 0x10),
  MoonlightKeyOption(label: 'Ctrl', windowsVk: 0x11),
  MoonlightKeyOption(label: 'Alt', windowsVk: 0x12),
  MoonlightKeyOption(label: 'Up arrow', windowsVk: 0x26),
  MoonlightKeyOption(label: 'Down arrow', windowsVk: 0x28),
  MoonlightKeyOption(label: 'Left arrow', windowsVk: 0x25),
  MoonlightKeyOption(label: 'Right arrow', windowsVk: 0x27),
  MoonlightKeyOption(label: 'F1', windowsVk: 0x70),
  MoonlightKeyOption(label: 'F2', windowsVk: 0x71),
  MoonlightKeyOption(label: 'F3', windowsVk: 0x72),
  MoonlightKeyOption(label: 'F4', windowsVk: 0x73),
  MoonlightKeyOption(label: 'F5', windowsVk: 0x74),
  MoonlightKeyOption(label: 'F6', windowsVk: 0x75),
  MoonlightKeyOption(label: 'F7', windowsVk: 0x76),
  MoonlightKeyOption(label: 'F8', windowsVk: 0x77),
  MoonlightKeyOption(label: 'F9', windowsVk: 0x78),
  MoonlightKeyOption(label: 'F10', windowsVk: 0x79),
  MoonlightKeyOption(label: 'F11', windowsVk: 0x7A),
  MoonlightKeyOption(label: 'F12', windowsVk: 0x7B),
];

MoonlightKeyOption? moonlightKeyByCode(int moonlightKeyCode) {
  for (final key in kMoonlightKeyboardKeys) {
    if (key.moonlightKeyCode == moonlightKeyCode) return key;
  }
  return null;
}
