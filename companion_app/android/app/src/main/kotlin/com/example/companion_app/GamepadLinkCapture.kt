package com.example.companion_app

import android.view.KeyEvent
import java.util.concurrent.atomic.AtomicReference

/** One-shot capture of the next gamepad key press while assigning manual links in settings. */
object GamepadLinkCapture {
    private val pending = AtomicReference<((KeyEvent) -> Unit)?>(null)

    fun beginListening(onCaptured: (KeyEvent) -> Unit): Boolean {
        return pending.compareAndSet(null, onCaptured)
    }

    fun cancel() {
        pending.set(null)
    }

    fun isListening(): Boolean = pending.get() != null

    fun tryConsume(event: KeyEvent): Boolean {
        if (event.source and android.view.InputDevice.SOURCE_GAMEPAD == 0 &&
            event.source and android.view.InputDevice.SOURCE_JOYSTICK == 0
        ) {
            return false
        }
        if (event.action != KeyEvent.ACTION_DOWN) return false
        val handler = pending.getAndSet(null) ?: return false
        handler(event)
        return true
    }
}
