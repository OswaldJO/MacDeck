package com.example.companion_app

import java.net.HttpURLConnection
import java.net.URL

/** Minimal HTTP client for Playnite stream control plane (port 28765). */
object PlayniteHostControlClient {
    private const val DEFAULT_CONTROL_PORT = 28765

    fun stopStreamOnHost(host: String, controlPort: Int = DEFAULT_CONTROL_PORT) {
        if (host.isEmpty()) return
        Thread {
            try {
                val url = URL("http://$host:$controlPort/playnite/v1/stream/stop")
                val connection = url.openConnection() as HttpURLConnection
                connection.requestMethod = "POST"
                connection.connectTimeout = 4_000
                connection.readTimeout = 4_000
                connection.connect()
                connection.disconnect()
            } catch (_: Exception) {
            }
        }.start()
    }
}
