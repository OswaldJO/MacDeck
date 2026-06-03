package com.example.companion_app

import java.nio.ByteBuffer
import java.nio.ByteOrder

object PlayniteStreamProtocols {
    const val VIDEO_MAGIC = 0x31564E50 // PNV1
    const val AUDIO_MAGIC = 0x31414E50 // PNA1
    const val AUDIO_SUBSCRIBE_MAGIC = 0x53414E50 // PNAS
    const val INPUT_MAGIC = 0x31494E50 // PNI1
    const val KEYBOARD_MAGIC = 0x314B4E50 // PNK1

    const val VIDEO_HEADER_SIZE = 13
    const val AUDIO_HEADER_SIZE = 11
    const val INPUT_PACKET_SIZE = 13
    const val KEYBOARD_PACKET_SIZE = 8

    fun buildInputPacket(
        type: Int,
        button: Int,
        xNorm: Int,
        yNorm: Int,
        scrollDelta: Short = 0,
    ): ByteArray {
        val buf = ByteBuffer.allocate(INPUT_PACKET_SIZE).order(ByteOrder.LITTLE_ENDIAN)
        buf.putInt(INPUT_MAGIC)
        buf.put(type.toByte())
        buf.put(button.toByte())
        buf.putShort(xNorm.toShort())
        buf.putShort(yNorm.toShort())
        buf.putShort(scrollDelta)
        return buf.array()
    }

    fun audioSubscribePacket(): ByteArray {
        return ByteBuffer.allocate(4).order(ByteOrder.LITTLE_ENDIAN)
            .putInt(AUDIO_SUBSCRIBE_MAGIC)
            .array()
    }

    fun buildKeyboardPacket(moonlightKeyCode: Int, down: Boolean): ByteArray {
        val buf = ByteBuffer.allocate(KEYBOARD_PACKET_SIZE).order(ByteOrder.LITTLE_ENDIAN)
        buf.putInt(KEYBOARD_MAGIC)
        buf.put(if (down) 1.toByte() else 0.toByte())
        buf.put(0)
        buf.putShort(moonlightKeyCode.toShort())
        return buf.array()
    }
}
