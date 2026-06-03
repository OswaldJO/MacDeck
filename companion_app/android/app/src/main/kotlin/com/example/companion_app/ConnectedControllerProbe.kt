package com.example.companion_app

import android.content.Context
import android.hardware.input.InputManager
import android.view.InputDevice

object ConnectedControllerProbe {
    fun list(context: Context): List<Map<String, Any>> {
        val inputManager = context.getSystemService(Context.INPUT_SERVICE) as InputManager
        val controllers = mutableListOf<Map<String, Any>>()

        for (deviceId in inputManager.inputDeviceIds) {
            val device = inputManager.getInputDevice(deviceId) ?: continue
            val sources = device.sources
            val isGamepad =
                sources and InputDevice.SOURCE_GAMEPAD == InputDevice.SOURCE_GAMEPAD ||
                    sources and InputDevice.SOURCE_JOYSTICK == InputDevice.SOURCE_JOYSTICK
            if (!isGamepad) continue

            controllers.add(
                mapOf(
                    "id" to deviceId.toString(),
                    "name" to (device.name ?: "Game controller"),
                    "vendor" to device.vendorId.toString(),
                ),
            )
        }

        return controllers
    }
}
