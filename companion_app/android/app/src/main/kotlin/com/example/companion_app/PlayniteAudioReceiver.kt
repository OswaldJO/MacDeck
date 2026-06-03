package com.example.companion_app

import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTrack
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetSocketAddress
import java.net.PortUnreachableException
import java.net.SocketTimeoutException
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Receives `PNA1` PCM from the Mac after sending `PNAS` subscribe.
 */
class PlayniteAudioReceiver(
    private val host: String,
    private val port: Int,
) {
    private val running = AtomicBoolean(false)
    private var thread: Thread? = null
    private var socket: DatagramSocket? = null
    private var track: AudioTrack? = null
    private var trackRate = 0
    private var trackChannels = 0

    fun start() {
        if (!running.compareAndSet(false, true)) return
        thread = Thread {
            var packetsHeard = 0
            try {
                val sock = DatagramSocket(null)
                sock.reuseAddress = true
                sock.soTimeout = 3_000
                sock.bind(InetSocketAddress(0))
                socket = sock
                sendSubscribe(sock)

                val header = ByteArray(PlayniteStreamProtocols.AUDIO_HEADER_SIZE)
                val packet = DatagramPacket(ByteArray(64 * 1024), 64 * 1024)
                var lastSubscribeMs = System.currentTimeMillis()
                while (running.get()) {
                    try {
                        packet.length = packet.data.size
                        sock.receive(packet)
                    } catch (e: SocketTimeoutException) {
                        val now = System.currentTimeMillis()
                        if (now - lastSubscribeMs >= 2_000) {
                            sendSubscribe(sock)
                            lastSubscribeMs = now
                        }
                        continue
                    } catch (e: PortUnreachableException) {
                        PlayniteStreamLog.w(
                            "Audio UDP port unreachable (retry subscribe): ${e.message}",
                        )
                        sendSubscribe(sock)
                        lastSubscribeMs = System.currentTimeMillis()
                        continue
                    }
                    if (packet.length < PlayniteStreamProtocols.AUDIO_HEADER_SIZE) continue
                    System.arraycopy(packet.data, 0, header, 0, header.size)
                    val buf = ByteBuffer.wrap(header).order(ByteOrder.LITTLE_ENDIAN)
                    val magic = buf.int
                    if (magic != PlayniteStreamProtocols.AUDIO_MAGIC) continue
                    val payloadLen = buf.int
                    val sampleRate = buf.short.toInt() and 0xFFFF
                    val channels = buf.get().toInt() and 0xFF
                    if (payloadLen <= 0 || packet.length < header.size + payloadLen) continue
                    val pcm = packet.data.copyOfRange(header.size, header.size + payloadLen)
                    playPcm(pcm, sampleRate, channels)
                    packetsHeard++
                    if (packetsHeard == 1) {
                        PlayniteStreamLog.i("First audio packet $payloadLen bytes")
                    }
                }
            } catch (e: Exception) {
                if (running.get()) {
                    PlayniteStreamLog.e(
                        "Audio receiver ended: ${e.javaClass.simpleName}: ${e.message}",
                        e,
                    )
                }
            } finally {
                track?.stop()
                track?.release()
                track = null
                runCatching { socket?.close() }
                socket = null
            }
        }.also { it.start() }
    }

    private fun sendSubscribe(sock: DatagramSocket) {
        val subscribe = PlayniteStreamProtocols.audioSubscribePacket()
        sock.send(
            DatagramPacket(
                subscribe,
                subscribe.size,
                InetSocketAddress(host, port),
            ),
        )
        PlayniteStreamLog.i("Audio subscribed to $host:$port localPort=${sock.localPort}")
    }

    fun stop() {
        running.set(false)
        runCatching { socket?.close() }
        thread?.join(1_500)
        thread = null
    }

    private fun playPcm(pcm: ByteArray, sampleRate: Int, channels: Int) {
        val ch = if (channels == 1) AudioFormat.CHANNEL_OUT_MONO else AudioFormat.CHANNEL_OUT_STEREO
        val rate = when {
            sampleRate in 8_000..96_000 -> sampleRate
            else -> 48_000
        }
        var local = track
        if (local == null || trackRate != rate || trackChannels != channels) {
            local?.release()
            val minBuf = AudioTrack.getMinBufferSize(
                rate,
                ch,
                AudioFormat.ENCODING_PCM_16BIT,
            ).coerceAtLeast(pcm.size * 4)
            if (minBuf <= 0) {
                PlayniteStreamLog.w("AudioTrack min buffer size invalid: $minBuf")
                return
            }
            local = AudioTrack.Builder()
                .setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_MEDIA)
                        .setContentType(AudioAttributes.CONTENT_TYPE_MOVIE)
                        .build(),
                )
                .setAudioFormat(
                    AudioFormat.Builder()
                        .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                        .setSampleRate(rate)
                        .setChannelMask(ch)
                        .build(),
                )
                .setBufferSizeInBytes(minBuf)
                .setTransferMode(AudioTrack.MODE_STREAM)
                .build()
            local.play()
            track = local
            trackRate = rate
            trackChannels = channels
            PlayniteStreamLog.i("AudioTrack started ${rate}Hz ch=$channels")
        }
        local.write(pcm, 0, pcm.size)
    }
}
