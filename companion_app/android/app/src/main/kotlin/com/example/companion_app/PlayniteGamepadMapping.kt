package com.example.companion_app

import android.util.Log
import android.view.KeyEvent
import org.json.JSONArray
import org.json.JSONObject

/**
 * Controller element → keyboard chord mappings for native Playnite streaming.
 * Manual physical key links override automatic Android keyCode → element detection.
 */
class PlayniteGamepadMapping(bindingsJson: String) {
    data class ElementBinding(
        val elementId: String,
        val moonlightKeyCodes: List<Int>,
        val physicalKeyCode: Int?,
        val manualPhysicalLink: Boolean,
    )

    private val bindingsByElement = mutableMapOf<String, ElementBinding>()
    private val physicalToElementManual = mutableMapOf<Int, String>()
    private val triggerDown = mutableMapOf<String, Boolean>()

    init {
        if (bindingsJson.isNotEmpty()) {
            try {
                val array = JSONArray(bindingsJson)
                for (i in 0 until array.length()) {
                    val item = array.getJSONObject(i)
                    val elementId = item.optString("sourceElementId", "")
                    if (elementId.isEmpty()) continue
                    val keys = parseKeyCodes(item)
                    if (keys.isEmpty()) continue
                    val physical = if (item.has("physicalKeyCode")) item.optInt("physicalKeyCode", -1) else -1
                    val manual = item.optBoolean("manualPhysicalLink", false)
                    val binding = ElementBinding(
                        elementId = elementId,
                        moonlightKeyCodes = keys,
                        physicalKeyCode = physical.takeIf { it >= 0 },
                        manualPhysicalLink = manual,
                    )
                    bindingsByElement[elementId] = binding
                    if (manual && physical >= 0) {
                        physicalToElementManual[physical] = elementId
                    }
                }
            } catch (e: Exception) {
                Log.w(TAG, "Failed to parse bindings", e)
            }
        }
    }


    fun hasBindings(): Boolean = bindingsByElement.isNotEmpty()

    fun handleKeyEvent(event: KeyEvent, keyboard: PlayniteKeyboardSender): Boolean {
        if (bindingsByElement.isEmpty()) return false
        val elementId = resolveElementId(event) ?: return false
        val binding = bindingsByElement[elementId] ?: return false
        val down = event.action == KeyEvent.ACTION_DOWN
        if (!down && event.action != KeyEvent.ACTION_UP) return true
        keyboard.sendChord(binding.moonlightKeyCodes, down)
        return true
    }

    fun handleTrigger(elementId: String, axisValue: Float, keyboard: PlayniteKeyboardSender): Boolean {
        val binding = bindingsByElement[elementId] ?: return false
        val down = axisValue > 0.65f
        val prev = triggerDown[elementId]
        if (prev != null && prev == down) return true
        triggerDown[elementId] = down
        keyboard.sendChord(binding.moonlightKeyCodes, down)
        return true
    }

    private fun resolveElementId(event: KeyEvent): String? {
        val keyCode = event.keyCode
        physicalToElementManual[keyCode]?.let { return it }
        return GamepadKeyCodes.elementIdForKeyCode(keyCode)
    }

    private fun parseKeyCodes(item: JSONObject): List<Int> {
        if (item.has("moonlightKeyCodes")) {
            val arr = item.optJSONArray("moonlightKeyCodes") ?: return emptyList()
            return (0 until arr.length()).mapNotNull { idx ->
                val code = arr.optInt(idx, 0)
                code.takeIf { it != 0 }
            }
        }
        val single = item.optInt("moonlightKeyCode", 0)
        return if (single != 0) listOf(single) else emptyList()
    }

    companion object {
        private const val TAG = "PlayniteGamepadMap"
    }
}

/** Shared keyCode ↔ logical gamepad element mapping. */
object GamepadKeyCodes {
    fun elementIdForKeyCode(keyCode: Int): String? = when (keyCode) {
        KeyEvent.KEYCODE_BUTTON_A, KeyEvent.KEYCODE_DPAD_CENTER -> "buttonA"
        KeyEvent.KEYCODE_BUTTON_B -> "buttonB"
        KeyEvent.KEYCODE_BUTTON_X -> "buttonX"
        KeyEvent.KEYCODE_BUTTON_Y -> "buttonY"
        KeyEvent.KEYCODE_BUTTON_L1 -> "leftShoulder"
        KeyEvent.KEYCODE_BUTTON_R1 -> "rightShoulder"
        KeyEvent.KEYCODE_BUTTON_L2 -> "leftTrigger"
        KeyEvent.KEYCODE_BUTTON_R2 -> "rightTrigger"
        KeyEvent.KEYCODE_BUTTON_THUMBL -> "leftThumbstickButton"
        KeyEvent.KEYCODE_BUTTON_THUMBR -> "rightThumbstickButton"
        KeyEvent.KEYCODE_DPAD_UP -> "dpadUp"
        KeyEvent.KEYCODE_DPAD_DOWN -> "dpadDown"
        KeyEvent.KEYCODE_DPAD_LEFT -> "dpadLeft"
        KeyEvent.KEYCODE_DPAD_RIGHT -> "dpadRight"
        KeyEvent.KEYCODE_BUTTON_START, KeyEvent.KEYCODE_MENU -> "buttonMenu"
        KeyEvent.KEYCODE_BUTTON_SELECT, KeyEvent.KEYCODE_BACK -> "buttonOptions"
        KeyEvent.KEYCODE_BUTTON_1 -> "macro1"
        KeyEvent.KEYCODE_BUTTON_2 -> "macro2"
        KeyEvent.KEYCODE_BUTTON_3 -> "macro3"
        KeyEvent.KEYCODE_BUTTON_4 -> "macro4"
        else -> null
    }

    fun labelForKeyCode(keyCode: Int): String = when (keyCode) {
        KeyEvent.KEYCODE_BUTTON_A -> "A"
        KeyEvent.KEYCODE_BUTTON_B -> "B"
        KeyEvent.KEYCODE_BUTTON_X -> "X"
        KeyEvent.KEYCODE_BUTTON_Y -> "Y"
        KeyEvent.KEYCODE_BUTTON_L1 -> "L1"
        KeyEvent.KEYCODE_BUTTON_R1 -> "R1"
        KeyEvent.KEYCODE_BUTTON_L2 -> "L2"
        KeyEvent.KEYCODE_BUTTON_R2 -> "R2"
        KeyEvent.KEYCODE_BUTTON_THUMBL -> "L3"
        KeyEvent.KEYCODE_BUTTON_THUMBR -> "R3"
        KeyEvent.KEYCODE_DPAD_UP -> "D-pad up"
        KeyEvent.KEYCODE_DPAD_DOWN -> "D-pad down"
        KeyEvent.KEYCODE_DPAD_LEFT -> "D-pad left"
        KeyEvent.KEYCODE_DPAD_RIGHT -> "D-pad right"
        KeyEvent.KEYCODE_BUTTON_START -> "Start"
        KeyEvent.KEYCODE_BUTTON_SELECT -> "Select"
        KeyEvent.KEYCODE_BUTTON_1 -> "Macro 1"
        KeyEvent.KEYCODE_BUTTON_2 -> "Macro 2"
        KeyEvent.KEYCODE_BUTTON_3 -> "Macro 3"
        KeyEvent.KEYCODE_BUTTON_4 -> "Macro 4"
        else -> "Key $keyCode"
    }

    val probeKeyCodes: List<Int> = listOf(
        KeyEvent.KEYCODE_BUTTON_A,
        KeyEvent.KEYCODE_BUTTON_B,
        KeyEvent.KEYCODE_BUTTON_X,
        KeyEvent.KEYCODE_BUTTON_Y,
        KeyEvent.KEYCODE_BUTTON_L1,
        KeyEvent.KEYCODE_BUTTON_R1,
        KeyEvent.KEYCODE_BUTTON_L2,
        KeyEvent.KEYCODE_BUTTON_R2,
        KeyEvent.KEYCODE_BUTTON_THUMBL,
        KeyEvent.KEYCODE_BUTTON_THUMBR,
        KeyEvent.KEYCODE_DPAD_UP,
        KeyEvent.KEYCODE_DPAD_DOWN,
        KeyEvent.KEYCODE_DPAD_LEFT,
        KeyEvent.KEYCODE_DPAD_RIGHT,
        KeyEvent.KEYCODE_BUTTON_START,
        KeyEvent.KEYCODE_BUTTON_SELECT,
        KeyEvent.KEYCODE_BUTTON_1,
        KeyEvent.KEYCODE_BUTTON_2,
        KeyEvent.KEYCODE_BUTTON_3,
        KeyEvent.KEYCODE_BUTTON_4,
    )
}
