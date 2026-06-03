package com.example.companion_app

import android.app.Activity
import android.app.AlertDialog
import android.graphics.Color
import android.view.Gravity
import android.view.ViewGroup
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import android.widget.Toast

/**
 * Semi-transparent mapping overlay shown on top of the live stream.
 * Supports quick gamepad button linking; full chord editing stays in the Flutter Controller tab.
 */
class PlayniteControllerMappingOverlay(
    private val activity: Activity,
    private val onBindingsJsonChanged: (String) -> Unit,
) {
    data class MappableElement(val id: String, val label: String)

    private var dialog: AlertDialog? = null

    fun show() {
        if (dialog?.isShowing == true) return
        val elements = mappableElements()
        val scroll = ScrollView(activity).apply {
            setBackgroundColor(Color.parseColor("#E6000000"))
            layoutParams = ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
            )
        }
        val list = LinearLayout(activity).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(32, 24, 32, 24)
        }
        val title = TextView(activity).apply {
            text = "Controller mapping"
            setTextColor(Color.WHITE)
            textSize = 20f
            setPadding(0, 0, 0, 16)
        }
        list.addView(title)
        val hint = TextView(activity).apply {
            text = "Tap Link, then press a gamepad button. Keyboard chords: Controller tab in the app."
            setTextColor(Color.parseColor("#B3FFFFFF"))
            textSize = 13f
            setPadding(0, 0, 0, 20)
        }
        list.addView(hint)

        for (element in elements) {
            val row = LinearLayout(activity).apply {
                orientation = LinearLayout.VERTICAL
                setPadding(0, 12, 0, 12)
            }
            val name = TextView(activity).apply {
                text = element.label
                setTextColor(Color.WHITE)
                textSize = 16f
            }
            val mapped = TextView(activity).apply {
                text = PlayniteStreamMappingPrefs.targetLabelForElement(activity, element.id)
                setTextColor(Color.parseColor("#99FFFFFF"))
                textSize = 13f
            }
            val link = TextView(activity).apply {
                text = "Link gamepad button"
                setTextColor(Color.parseColor("#FF8AB4FF"))
                textSize = 14f
                setPadding(0, 8, 0, 0)
                setOnClickListener { startLink(element) }
            }
            row.addView(name)
            row.addView(mapped)
            row.addView(link)
            list.addView(row)
        }
        scroll.addView(list)

        dialog = AlertDialog.Builder(activity, android.R.style.Theme_DeviceDefault_Dialog_NoActionBar)
            .setView(scroll)
            .setNegativeButton("Close") { d, _ -> d.dismiss() }
            .create()
        dialog?.window?.setLayout(
            ViewGroup.LayoutParams.MATCH_PARENT,
            (activity.resources.displayMetrics.heightPixels * 0.82f).toInt(),
        )
        dialog?.window?.setGravity(Gravity.CENTER)
        dialog?.setOnDismissListener { GamepadLinkCapture.cancel() }
        dialog?.show()
    }

    fun dismiss() {
        GamepadLinkCapture.cancel()
        dialog?.dismiss()
        dialog = null
    }

    private fun startLink(element: MappableElement) {
        if (!GamepadLinkCapture.beginListening { event ->
            activity.runOnUiThread {
                val label = GamepadKeyCodes.labelForKeyCode(event.keyCode)
                val json = PlayniteStreamMappingPrefs.upsertPhysicalLink(
                    activity,
                    element.id,
                    element.label,
                    event.keyCode,
                    label,
                )
                PlayniteStreamSession.controllerBindingsJson = json
                onBindingsJsonChanged(json)
                Toast.makeText(activity, "${element.label} → $label", Toast.LENGTH_SHORT).show()
                dismiss()
                show()
            }
        }) {
            Toast.makeText(activity, "Already waiting for a button press", Toast.LENGTH_SHORT).show()
        }
    }

    companion object {
        fun mappableElements(): List<MappableElement> = listOf(
            MappableElement("buttonA", "A / Cross"),
            MappableElement("buttonB", "B / Circle"),
            MappableElement("buttonX", "X / Square"),
            MappableElement("buttonY", "Y / Triangle"),
            MappableElement("leftShoulder", "Left bumper (L1)"),
            MappableElement("rightShoulder", "Right bumper (R1)"),
            MappableElement("leftTrigger", "Left trigger (L2)"),
            MappableElement("rightTrigger", "Right trigger (R2)"),
            MappableElement("leftThumbstickButton", "Left stick click (L3)"),
            MappableElement("rightThumbstickButton", "Right stick click (R3)"),
            MappableElement("dpadUp", "D-pad up"),
            MappableElement("dpadDown", "D-pad down"),
            MappableElement("dpadLeft", "D-pad left"),
            MappableElement("dpadRight", "D-pad right"),
            MappableElement("buttonMenu", "Start / Menu"),
            MappableElement("buttonOptions", "Select / Options"),
            MappableElement("macro1", "Macro 1"),
            MappableElement("macro2", "Macro 2"),
            MappableElement("macro3", "Macro 3"),
            MappableElement("macro4", "Macro 4"),
        )
    }
}
