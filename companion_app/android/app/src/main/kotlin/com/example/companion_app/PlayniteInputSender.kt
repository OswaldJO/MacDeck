package com.example.companion_app

import android.view.MotionEvent
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetSocketAddress
import java.util.concurrent.Executors

/**
 * Sends `PNI1` touch events to the Mac input port (background thread — never on UI thread).
 */
class PlayniteInputSender(
    private val host: String,
    private val port: Int,
    private val viewWidth: () -> Int,
    private val viewHeight: () -> Int,
) {
    private val socket = DatagramSocket()
    private val executor = Executors.newSingleThreadExecutor()
    private var packetsSent = 0
    private var lastMoveSentMs = 0L
    @Volatile private var loggedSendFailure = false

    fun handleTouch(event: MotionEvent): Boolean {
        val w = viewWidth()
        val h = viewHeight()
        if (w <= 0 || h <= 0) return false

        val (type, button) = when (event.actionMasked) {
            MotionEvent.ACTION_DOWN, MotionEvent.ACTION_POINTER_DOWN -> 1 to 0
            MotionEvent.ACTION_UP, MotionEvent.ACTION_POINTER_UP -> 2 to 0
            MotionEvent.ACTION_MOVE -> 0 to 0
            else -> return false
        }

        if (type == 0) {
            val now = System.currentTimeMillis()
            if (now - lastMoveSentMs < 16) return true
            lastMoveSentMs = now
        }

        val xNorm = ((event.x / w) * 65535f).toInt().coerceIn(0, 65535)
        val yNorm = ((event.y / h) * 65535f).toInt().coerceIn(0, 65535)
        val payload = PlayniteStreamProtocols.buildInputPacket(type, button, xNorm, yNorm)
        executor.execute { sendPayload(payload, type, xNorm, yNorm) }
        return true
    }

    private fun sendPayload(payload: ByteArray, type: Int, xNorm: Int, yNorm: Int) {
        try {
            socket.send(
                DatagramPacket(
                    payload,
                    payload.size,
                    InetSocketAddress(host, port),
                ),
            )
            packetsSent++
            if (packetsSent == 1 || packetsSent % 50 == 0) {
                PlayniteStreamLog.i("Input UDP #$packetsSent type=$type x=$xNorm y=$yNorm → $host:$port")
            }
            loggedSendFailure = false
        } catch (e: Exception) {
            if (!loggedSendFailure) {
                loggedSendFailure = true
                PlayniteStreamLog.w(
                    "Input send failed: ${e.javaClass.simpleName}: ${e.message}",
                )
            }
        }
    }

    fun close() {
        executor.shutdownNow()
        runCatching { socket.close() }
    }
}
