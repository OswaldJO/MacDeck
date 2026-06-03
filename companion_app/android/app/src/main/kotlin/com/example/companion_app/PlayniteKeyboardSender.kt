package com.example.companion_app

import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetSocketAddress
import java.util.concurrent.Executors

/** Sends `PNK1` keyboard events to the Mac input port (native stream). */
class PlayniteKeyboardSender(
    private val host: String,
    private val port: Int,
) {
    private val socket = DatagramSocket()
    private val executor = Executors.newSingleThreadExecutor()

    fun sendKey(moonlightKeyCode: Int, down: Boolean) {
        val payload = PlayniteStreamProtocols.buildKeyboardPacket(moonlightKeyCode, down)
        executor.execute {
            try {
                socket.send(
                    DatagramPacket(
                        payload,
                        payload.size,
                        InetSocketAddress(host, port),
                    ),
                )
            } catch (_: Exception) {
            }
        }
    }

    fun sendChord(moonlightKeyCodes: List<Int>, down: Boolean) {
        if (moonlightKeyCodes.isEmpty()) return
        val order = if (down) moonlightKeyCodes else moonlightKeyCodes.asReversed()
        for (code in order) {
            sendKey(code, down)
        }
    }

    fun close() {
        executor.shutdown()
        runCatching { socket.close() }
    }
}
