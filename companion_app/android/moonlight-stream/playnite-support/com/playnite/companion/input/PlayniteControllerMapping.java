package com.playnite.companion.input;

import android.content.Intent;
import android.util.Log;
import android.view.KeyEvent;

import com.limelight.nvstream.NvConnection;
import com.limelight.nvstream.input.KeyboardPacket;

import org.json.JSONArray;
import org.json.JSONObject;

import java.util.HashMap;
import java.util.Map;

/**
 * Companion-app controller → keyboard mappings applied during Moonlight streaming.
 */
public final class PlayniteControllerMapping {
    private static final String TAG = "PlayniteControllerMap";

    public static final String EXTRA_BINDINGS_JSON = "PlayniteControllerBindingsJson";
    public static final String EXTRA_AUTO_MOUSE_EMULATION = "PlayniteAutoMouseEmulation";

    private static final Map<String, Short> bindingsByElement = new HashMap<>();
    private static final Map<String, Boolean> triggerDownState = new HashMap<>();
    private static boolean autoMouseEmulation;

    private PlayniteControllerMapping() {}

    public static void configure(Intent intent) {
        bindingsByElement.clear();
        triggerDownState.clear();
        autoMouseEmulation = false;
        if (intent == null) {
            return;
        }

        autoMouseEmulation = intent.getBooleanExtra(EXTRA_AUTO_MOUSE_EMULATION, false);
        String json = intent.getStringExtra(EXTRA_BINDINGS_JSON);
        if (json == null || json.isEmpty()) {
            return;
        }

        try {
            JSONArray array = new JSONArray(json);
            for (int i = 0; i < array.length(); i++) {
                JSONObject item = array.getJSONObject(i);
                String elementId = item.optString("sourceElementId", "");
                int keyCode = item.optInt("moonlightKeyCode", 0);
                if (!elementId.isEmpty() && keyCode != 0) {
                    bindingsByElement.put(elementId, (short) keyCode);
                }
            }
        } catch (Exception e) {
            Log.w(TAG, "Failed to parse controller bindings JSON", e);
        }
    }

    public static boolean hasBindings() {
        return !bindingsByElement.isEmpty();
    }

    public static boolean shouldAutoEnableMouseEmulation() {
        return autoMouseEmulation;
    }

    public static boolean isAutoMouseEmulation() {
        return autoMouseEmulation;
    }

    public static boolean isMapped(String elementId) {
        Short mapped = bindingsByElement.get(elementId);
        return mapped != null && mapped != 0;
    }

    public static void trySendKeyboardForTrigger(NvConnection conn, String elementId, float axisValue) {
        if (conn == null || !isMapped(elementId)) {
            return;
        }

        boolean down = axisValue > 0.65f;
        Boolean previous = triggerDownState.get(elementId);
        if (previous != null && previous == down) {
            return;
        }
        triggerDownState.put(elementId, down);

        Short mapped = bindingsByElement.get(elementId);
        if (mapped == null) {
            return;
        }

        conn.sendKeyboardInput(
                mapped,
                down ? KeyboardPacket.KEY_DOWN : KeyboardPacket.KEY_UP,
                (byte) 0,
                (byte) 0);
    }

    public static boolean trySendKeyboardForKeyCode(NvConnection conn, int keyCode, boolean down) {
        if (conn == null || bindingsByElement.isEmpty()) {
            return false;
        }

        String elementId = elementIdForKeyCode(keyCode);
        if (elementId == null) {
            return false;
        }

        Short mapped = bindingsByElement.get(elementId);
        if (mapped == null || mapped == 0) {
            return false;
        }

        conn.sendKeyboardInput(
                mapped,
                down ? KeyboardPacket.KEY_DOWN : KeyboardPacket.KEY_UP,
                (byte) 0,
                (byte) 0);
        return true;
    }

    private static String elementIdForKeyCode(int keyCode) {
        switch (keyCode) {
            case KeyEvent.KEYCODE_BUTTON_A:
            case KeyEvent.KEYCODE_DPAD_CENTER:
                return "buttonA";
            case KeyEvent.KEYCODE_BUTTON_B:
                return "buttonB";
            case KeyEvent.KEYCODE_BUTTON_X:
                return "buttonX";
            case KeyEvent.KEYCODE_BUTTON_Y:
                return "buttonY";
            case KeyEvent.KEYCODE_BUTTON_L1:
                return "leftShoulder";
            case KeyEvent.KEYCODE_BUTTON_R1:
                return "rightShoulder";
            case KeyEvent.KEYCODE_BUTTON_L2:
                return "leftTrigger";
            case KeyEvent.KEYCODE_BUTTON_R2:
                return "rightTrigger";
            case KeyEvent.KEYCODE_BUTTON_THUMBL:
                return "leftThumbstickButton";
            case KeyEvent.KEYCODE_BUTTON_THUMBR:
                return "rightThumbstickButton";
            case KeyEvent.KEYCODE_DPAD_UP:
                return "dpadUp";
            case KeyEvent.KEYCODE_DPAD_DOWN:
                return "dpadDown";
            case KeyEvent.KEYCODE_DPAD_LEFT:
                return "dpadLeft";
            case KeyEvent.KEYCODE_DPAD_RIGHT:
                return "dpadRight";
            case KeyEvent.KEYCODE_BUTTON_START:
            case KeyEvent.KEYCODE_MENU:
                return "buttonMenu";
            case KeyEvent.KEYCODE_BUTTON_SELECT:
            case KeyEvent.KEYCODE_BACK:
                return "buttonOptions";
            default:
                return null;
        }
    }
}
