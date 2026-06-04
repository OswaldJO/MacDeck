package com.example.companion_app

import android.view.InputDevice
import android.view.KeyEvent
import android.view.MotionEvent

/**
 * Detects gamepad / joystick hardware so the companion can swallow events before Android
 * uses them for focus navigation (D-pad, A = activate, stick = scroll).
 */
object GamepadInputFilter {
    fun isGamepadKey(event: KeyEvent): Boolean {
        // System / gesture Back must reach the activity so the user can leave the stream view.
        if (event.keyCode == KeyEvent.KEYCODE_BACK) return false
        if (KeyEvent.isGamepadButton(event.keyCode)) return true
        return when (event.keyCode) {
            KeyEvent.KEYCODE_DPAD_UP,
            KeyEvent.KEYCODE_DPAD_DOWN,
            KeyEvent.KEYCODE_DPAD_LEFT,
            KeyEvent.KEYCODE_DPAD_RIGHT,
            KeyEvent.KEYCODE_DPAD_CENTER,
            KeyEvent.KEYCODE_BUTTON_START,
            KeyEvent.KEYCODE_BUTTON_SELECT,
            KeyEvent.KEYCODE_MENU,
            GamepadKeyCodes.KEYCODE_APP_COMPAT,
            -> true
            else -> hasGamepadSource(event.source)
        }
    }

    fun isGamepadMotion(event: MotionEvent): Boolean = hasGamepadSource(event.source)

    fun leftTriggerValue(event: MotionEvent): Float =
        readAxis(event, MotionEvent.AXIS_LTRIGGER, MotionEvent.AXIS_BRAKE, MotionEvent.AXIS_Z)

    fun rightTriggerValue(event: MotionEvent): Float =
        readAxis(event, MotionEvent.AXIS_RTRIGGER, MotionEvent.AXIS_GAS, MotionEvent.AXIS_RZ)

    private fun readAxis(event: MotionEvent, vararg axes: Int): Float {
        var max = 0f
        for (axis in axes) {
            max = maxOf(max, event.getAxisValue(axis))
        }
        return max.coerceIn(0f, 1f)
    }

    private fun hasGamepadSource(source: Int): Boolean {
        return (source and InputDevice.SOURCE_GAMEPAD) != 0 ||
            (source and InputDevice.SOURCE_JOYSTICK) != 0 ||
            (source and InputDevice.SOURCE_DPAD) != 0
    }
}
