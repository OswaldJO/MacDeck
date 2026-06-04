package com.example.companion_app

/** Moonlight short key codes: `(0x80 << 8) | windowsVk` — matches Flutter [moonlight_key_codes.dart]. */
data class MoonlightKeyboardKey(val label: String, val moonlightKeyCode: Int)

object MoonlightKeyboardKeys {
    private fun vk(windowsVk: Int): Int = (0x80 shl 8) or windowsVk

    val common: List<MoonlightKeyboardKey> = listOf(
        MoonlightKeyboardKey("A", vk(0x41)),
        MoonlightKeyboardKey("B", vk(0x42)),
        MoonlightKeyboardKey("C", vk(0x43)),
        MoonlightKeyboardKey("D", vk(0x44)),
        MoonlightKeyboardKey("E", vk(0x45)),
        MoonlightKeyboardKey("F", vk(0x46)),
        MoonlightKeyboardKey("G", vk(0x47)),
        MoonlightKeyboardKey("H", vk(0x48)),
        MoonlightKeyboardKey("Space", vk(0x20)),
        MoonlightKeyboardKey("Enter", vk(0x0D)),
        MoonlightKeyboardKey("Escape", vk(0x1B)),
        MoonlightKeyboardKey("Tab", vk(0x09)),
        MoonlightKeyboardKey("Shift", vk(0x10)),
        MoonlightKeyboardKey("Ctrl", vk(0x11)),
        MoonlightKeyboardKey("Option", vk(0xA4)),
        MoonlightKeyboardKey("Command", vk(0x5B)),
        MoonlightKeyboardKey("Up", vk(0x26)),
        MoonlightKeyboardKey("Down", vk(0x28)),
        MoonlightKeyboardKey("Left", vk(0x25)),
        MoonlightKeyboardKey("Right", vk(0x27)),
        MoonlightKeyboardKey("W", vk(0x57)),
        MoonlightKeyboardKey("S", vk(0x53)),
        MoonlightKeyboardKey("1", vk(0x31)),
        MoonlightKeyboardKey("2", vk(0x32)),
        MoonlightKeyboardKey("F1", vk(0x70)),
        MoonlightKeyboardKey("F2", vk(0x71)),
        MoonlightKeyboardKey("F3", vk(0x72)),
        MoonlightKeyboardKey("F4", vk(0x73)),
        MoonlightKeyboardKey("F5", vk(0x74)),
    )

    fun labelForCode(code: Int): String =
        common.firstOrNull { it.moonlightKeyCode == code }?.label ?: "Key"
}
