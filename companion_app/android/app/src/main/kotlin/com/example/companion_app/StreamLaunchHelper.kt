package com.example.companion_app

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.util.Base64
import com.limelight.Game
import com.limelight.nvstream.http.NvHTTP
import org.bouncycastle.asn1.pkcs.PrivateKeyInfo
import org.bouncycastle.openssl.PEMKeyPair
import org.bouncycastle.openssl.PEMParser
import org.bouncycastle.openssl.jcajce.JcaPEMKeyConverter
import java.io.File
import java.io.StringReader

object StreamLaunchHelper {
    private var activeGame: Activity? = null

    fun startStream(activity: Activity, args: Map<String, Any?>): Boolean {
        val host = args["hostAddress"] as? String ?: return false
        val httpPort = (args["httpPort"] as? Number)?.toInt() ?: NvHTTP.DEFAULT_HTTP_PORT
        val httpsPort = (args["httpsPort"] as? Number)?.toInt() ?: 47984
        val appId = (args["appId"] as? Number)?.toInt() ?: return false
        val appName = args["appName"] as? String ?: "Desktop"
        val pcName = args["pcName"] as? String ?: host
        val uniqueId = args["uniqueId"] as? String ?: "0123456789ABCDEF"
        val serverCertB64 = args["serverCertDerBase64"] as? String ?: return false
        val clientCertPem = args["clientCertPem"] as? String ?: return false
        val clientKeyPem = args["clientKeyPem"] as? String ?: return false

        syncMoonlightIdentity(activity, clientCertPem, clientKeyPem, uniqueId)

        val serverCertDer = Base64.decode(serverCertB64, Base64.DEFAULT)

        val intent = Intent(activity, Game::class.java).apply {
            putExtra(Game.EXTRA_HOST, host)
            putExtra(Game.EXTRA_PORT, httpPort)
            putExtra(Game.EXTRA_HTTPS_PORT, httpsPort)
            putExtra(Game.EXTRA_APP_NAME, appName)
            putExtra(Game.EXTRA_APP_ID, appId)
            putExtra(Game.EXTRA_UNIQUEID, uniqueId)
            putExtra(Game.EXTRA_PC_NAME, pcName)
            putExtra(Game.EXTRA_PC_UUID, host)
            putExtra(Game.EXTRA_APP_HDR, false)
            putExtra(Game.EXTRA_SERVER_CERT, serverCertDer)
        }
        activity.startActivity(intent)
        return true
    }

    fun stopStream() {
        activeGame?.finish()
        activeGame = null
    }

    fun trackGameActivity(activity: Activity) {
        activeGame = activity
    }

    private fun syncMoonlightIdentity(
        context: Context,
        clientCertPem: String,
        clientKeyPem: String,
        uniqueId: String,
    ) {
        val certFile = File(context.filesDir, "client.crt")
        certFile.writeText(clientCertPem.replace("\r", ""))

        val parser = PEMParser(StringReader(clientKeyPem))
        val keyObject = parser.readObject()
        val converter = JcaPEMKeyConverter()
        val privateKey = when (keyObject) {
            is PEMKeyPair -> converter.getPrivateKey(keyObject.privateKeyInfo)
            is PrivateKeyInfo -> converter.getPrivateKey(keyObject)
            else -> throw IllegalArgumentException("Unsupported client key PEM")
        }
        File(context.filesDir, "client.key").writeBytes(privateKey.encoded)

        context.openFileOutput("uniqueid", Context.MODE_PRIVATE).use { out ->
            out.write(uniqueId.toByteArray(Charsets.US_ASCII))
        }
    }
}
