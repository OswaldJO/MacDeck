package com.example.companion_app

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

/** Reads/writes Flutter [StreamControllerMappingStore] bindings in SharedPreferences. */
object PlayniteStreamMappingPrefs {
    private const val PREFS_NAME = "FlutterSharedPreferences"
    private const val BINDINGS_KEY = "flutter.stream.controller.bindings"

    fun loadBindingsJson(context: Context): String {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        return prefs.getString(BINDINGS_KEY, null).orEmpty()
    }

    fun saveBindingsJson(context: Context, json: String) {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putString(BINDINGS_KEY, json)
            .apply()
    }

    fun upsertPhysicalLink(
        context: Context,
        elementId: String,
        elementLabel: String,
        keyCode: Int,
        keyLabel: String,
    ): String {
        val array = try {
            JSONArray(loadBindingsJson(context).ifEmpty { "[]" })
        } catch (_: Exception) {
            JSONArray()
        }
        var found = false
        for (i in 0 until array.length()) {
            val item = array.optJSONObject(i) ?: continue
            if (item.optString("sourceElementId") != elementId) continue
            item.put("sourceLabel", elementLabel)
            item.put("physicalKeyCode", keyCode)
            item.put("manualPhysicalLink", true)
            item.put("targetLabel", keyLabel)
            found = true
            break
        }
        if (!found) {
            array.put(
                JSONObject()
                    .put("sourceElementId", elementId)
                    .put("sourceLabel", elementLabel)
                    .put("moonlightKeyCodes", JSONArray())
                    .put("targetLabel", keyLabel)
                    .put("physicalKeyCode", keyCode)
                    .put("manualPhysicalLink", true),
            )
        }
        val json = array.toString()
        saveBindingsJson(context, json)
        return json
    }

    fun targetLabelForElement(context: Context, elementId: String): String {
        val array = try {
            JSONArray(loadBindingsJson(context).ifEmpty { "[]" })
        } catch (_: Exception) {
            return "Unmapped"
        }
        for (i in 0 until array.length()) {
            val item = array.optJSONObject(i) ?: continue
            if (item.optString("sourceElementId") != elementId) continue
            val label = item.optString("targetLabel", "")
            if (label.isNotEmpty()) return label
            val keys = item.optJSONArray("moonlightKeyCodes")
            if (keys != null && keys.length() > 0) return "Keyboard chord"
            val physical = if (item.has("physicalKeyCode")) item.optInt("physicalKeyCode", -1) else -1
            if (physical >= 0) return GamepadKeyCodes.labelForKeyCode(physical)
        }
        return "Unmapped"
    }
}
