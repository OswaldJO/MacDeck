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
                if (packetsLogged < 16) {
                    packetsLogged++
                    PlayniteStreamLog.i(
                        "Keyboard PNK1 ${if (down) "down" else "up"} " +
                            "key=0x${moonlightKeyCode.toString(16)} → $host:$port",
                    )
                }
            } catch (e: Exception) {
                PlayniteStreamLog.w("Keyboard send failed key=0x${moonlightKeyCode.toString(16)}: ${e.message}")
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

    @Volatile
    private var packetsLogged = 0

    fun close() {
        executor.shutdown()
        runCatching { socket.close() }
    }
}
