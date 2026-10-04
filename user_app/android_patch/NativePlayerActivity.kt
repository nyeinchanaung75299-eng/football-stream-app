package com.example.football_viewer

import android.app.Activity
import android.os.Bundle
import android.util.Base64
import android.view.View
import android.view.WindowManager
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.drm.DefaultDrmSessionManager
import androidx.media3.exoplayer.drm.FrameworkMediaDrm
import androidx.media3.exoplayer.drm.LocalMediaDrmCallback
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.ui.PlayerView

@UnstableApi
class NativePlayerActivity : Activity() {
    private var player: ExoPlayer? = null
    private lateinit var playerView: PlayerView

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        @Suppress("DEPRECATION")
        run {
            window.decorView.systemUiVisibility = View.SYSTEM_UI_FLAG_FULLSCREEN or
                View.SYSTEM_UI_FLAG_HIDE_NAVIGATION or View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
        }
        playerView = PlayerView(this)
        setContentView(playerView)

        val url = intent.getStringExtra("url").orEmpty()
        val streamType = intent.getStringExtra("streamType").orEmpty().lowercase()
        val referer = intent.getStringExtra("referer").orEmpty()
        val origin = intent.getStringExtra("origin").orEmpty()
        val keyId = intent.getStringExtra("keyId").orEmpty()
        val keyData = intent.getStringExtra("keyData").orEmpty()
        if (url.isBlank()) { finish(); return }

        try {
            val headers = mutableMapOf<String, String>()
            if (referer.isNotBlank()) headers["Referer"] = referer
            if (origin.isNotBlank()) headers["Origin"] = origin

            val httpFactory = DefaultHttpDataSource.Factory()
                .setAllowCrossProtocolRedirects(true)
                .setDefaultRequestProperties(headers)
            val mediaSourceFactory = DefaultMediaSourceFactory(httpFactory)
            val mediaItemBuilder = MediaItem.Builder().setUri(url)
            when (streamType) {
                "dash", "mpd" -> mediaItemBuilder.setMimeType(MimeTypes.APPLICATION_MPD)
                "hls", "m3u8" -> mediaItemBuilder.setMimeType(MimeTypes.APPLICATION_M3U8)
            }

            if (keyId.isNotBlank() && keyData.isNotBlank()) {
                val json = "{\"keys\":[{\"kty\":\"oct\",\"kid\":\"" + toBase64Url(keyId) +
                    "\",\"k\":\"" + toBase64Url(keyData) + "\"}],\"type\":\"temporary\"}"
                val callback = LocalMediaDrmCallback(json.toByteArray(Charsets.UTF_8))
                val drm = DefaultDrmSessionManager.Builder()
                    .setPlayClearSamplesWithoutKeys(true)
                    .setMultiSession(false)
                    .setUuidAndExoMediaDrmProvider(C.CLEARKEY_UUID, FrameworkMediaDrm.DEFAULT_PROVIDER)
                    .build(callback)
                mediaSourceFactory.setDrmSessionManagerProvider { drm }
                mediaItemBuilder.setDrmConfiguration(
                    MediaItem.DrmConfiguration.Builder(C.CLEARKEY_UUID).build()
                )
            }

            val exoPlayer = ExoPlayer.Builder(this).setMediaSourceFactory(mediaSourceFactory).build()
            player = exoPlayer
            playerView.player = exoPlayer
            exoPlayer.setMediaItem(mediaItemBuilder.build())
            exoPlayer.prepare()
            exoPlayer.playWhenReady = true
        } catch (_: Throwable) {
            finish()
        }
    }

    override fun onDestroy() {
        playerView.player = null
        player?.release()
        player = null
        super.onDestroy()
    }

    private fun toBase64Url(value: String): String {
        val clean = value.replace(" ", "").trim()
        if (clean.matches(Regex("^[0-9a-fA-F]+$")) && clean.length % 2 == 0) {
            val bytes = ByteArray(clean.length / 2)
            for (i in bytes.indices) {
                val p = i * 2
                bytes[i] = clean.substring(p, p + 2).toInt(16).toByte()
            }
            return Base64.encodeToString(bytes, Base64.URL_SAFE or Base64.NO_WRAP or Base64.NO_PADDING)
        }
        return clean.replace("+", "-").replace("/", "_").trimEnd('=')
    }
}
