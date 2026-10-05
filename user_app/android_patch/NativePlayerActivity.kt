package com.example.football_viewer

import android.app.Activity
import android.graphics.Color
import android.os.Build
import android.os.Bundle
import android.util.Base64
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.WindowInsets
import android.view.WindowInsetsController
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.PopupMenu
import android.widget.TextView
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.TrackSelectionOverride
import androidx.media3.common.Tracks
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.drm.DefaultDrmSessionManager
import androidx.media3.exoplayer.drm.FrameworkMediaDrm
import androidx.media3.exoplayer.drm.LocalMediaDrmCallback
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.exoplayer.trackselection.DefaultTrackSelector
import androidx.media3.ui.AspectRatioFrameLayout
import androidx.media3.ui.PlayerView
import org.json.JSONArray

@UnstableApi
class NativePlayerActivity : Activity() {
    private var player: ExoPlayer? = null
    private var trackSelector: DefaultTrackSelector? = null
    private lateinit var playerView: PlayerView
    private lateinit var qualityButton: TextView
    private lateinit var serverButton: TextView
    private lateinit var statusText: TextView

    private var sources = JSONArray()
    private var selectedServerIndex = 0
    private var qualityOptions = mutableListOf<QualityOption>()
    private var forcedQualityLabel: String? = null
    private var autoFallbackTried = mutableSetOf<Int>()

    private data class QualityOption(
        val label: String,
        val group: Tracks.Group,
        val trackIndex: Int,
        val height: Int,
        val bitrate: Int
    )

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        try {
            createPlayerScreen()
        } catch (t: Throwable) {
            val detail = buildString {
                append("Player UI failed")
                append("\n")
                append(t.javaClass.simpleName)
                val message = t.message?.trim().orEmpty()
                if (message.isNotEmpty()) {
                    append(": ")
                    append(message.take(180))
                }
            }
            showFatalError(detail)
        }
    }

    private fun createPlayerScreen() {
        // Parse the payload before doing any ExoPlayer work.
        val json = intent.getStringExtra("sourcesJson").orEmpty()
        if (json.isBlank()) {
            showFatalError("No stream source")
            return
        }

        sources = try {
            JSONArray(json)
        } catch (t: Throwable) {
            showFatalError("Invalid stream source")
            return
        }

        if (sources.length() == 0) {
            showFatalError("No stream source")
            return
        }

        selectedServerIndex = intent.getIntExtra("selectedIndex", 0)
            .coerceIn(0, sources.length() - 1)

        // Put a content view on screen first. Some Android 12 / OEM builds can
        // be fragile if immersive-window calls happen before a decor view exists.
        val root = FrameLayout(this).apply {
            setBackgroundColor(Color.BLACK)
        }
        setContentView(root)

        try {
            window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
            window.statusBarColor = Color.BLACK
            window.navigationBarColor = Color.BLACK
        } catch (_: Throwable) {
            // Window cosmetics must never stop playback from starting.
        }

        playerView = PlayerView(this).apply {
            setBackgroundColor(Color.BLACK)
            resizeMode = AspectRatioFrameLayout.RESIZE_MODE_ZOOM
            useController = true
            controllerAutoShow = true
            controllerShowTimeoutMs = 3000
        }
        root.addView(
            playerView,
            FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            )
        )

        val topBar = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(12), dp(10), dp(12), dp(6))
            setBackgroundColor(Color.argb(115, 0, 0, 0))
        }

        val back = overlayButton("←").apply {
            textSize = 28f
            contentDescription = "Back"
            setOnClickListener { finish() }
        }

        serverButton = overlayButton("Server").apply {
            textSize = 14f
            setPadding(dp(12), 0, dp(12), 0)
            setOnClickListener { showServerMenu() }
        }

        qualityButton = overlayButton("Auto").apply {
            textSize = 14f
            setPadding(dp(12), 0, dp(12), 0)
            setOnClickListener { showQualityMenu() }
        }

        topBar.addView(back, LinearLayout.LayoutParams(dp(48), dp(42)))
        topBar.addView(
            serverButton,
            LinearLayout.LayoutParams(0, dp(42), 1f)
        )
        topBar.addView(
            qualityButton,
            LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT,
                dp(42)
            )
        )

        root.addView(
            topBar,
            FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
                Gravity.TOP
            )
        )

        statusText = TextView(this).apply {
            setTextColor(Color.WHITE)
            textSize = 14f
            gravity = Gravity.CENTER
            setPadding(dp(14), dp(10), dp(14), dp(10))
            setBackgroundColor(Color.argb(165, 0, 0, 0))
            visibility = View.GONE
        }

        root.addView(
            statusText,
            FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
                Gravity.CENTER
            )
        )

        // Run immersive-mode and playback only after the view hierarchy exists.
        root.post {
            safeHideSystemBars()
            playServer(selectedServerIndex)
        }
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) safeHideSystemBars()
    }

    private fun playServer(index: Int) {
        if (index !in 0 until sources.length()) return
        val source = sources.optJSONObject(index) ?: return
        val url = source.optString("url").trim()
        if (url.isBlank()) {
            tryNextServer("Empty stream URL")
            return
        }

        selectedServerIndex = index
        forcedQualityLabel = null
        qualityOptions.clear()
        qualityButton.text = "Auto"
        serverButton.text = source.optString("label", "Server ${index + 1}")
        showStatus("Opening ${serverButton.text}…")

        playerView.player = null
        player?.release()
        player = null
        trackSelector = null

        try {
            val headers = mutableMapOf<String, String>()
            val referer = source.optString("referer").trim()
            val origin = source.optString("origin").trim()
            if (referer.isNotBlank()) headers["Referer"] = referer
            if (origin.isNotBlank()) headers["Origin"] = origin

            val httpFactory = DefaultHttpDataSource.Factory()
                .setAllowCrossProtocolRedirects(true)
                .setConnectTimeoutMs(12000)
                .setReadTimeoutMs(15000)
                .setDefaultRequestProperties(headers)

            val mediaSourceFactory = DefaultMediaSourceFactory(httpFactory)
            val itemBuilder = MediaItem.Builder().setUri(url)
            when (source.optString("streamType", "auto").lowercase()) {
                "dash", "mpd" -> itemBuilder.setMimeType(MimeTypes.APPLICATION_MPD)
                "hls", "m3u8" -> itemBuilder.setMimeType(MimeTypes.APPLICATION_M3U8)
            }

            val keyId = source.optString("keyId").trim()
            val keyData = source.optString("keyData").trim()
            if (keyId.isNotBlank() && keyData.isNotBlank()) {
                val clearKeyJson = "{\"keys\":[{\"kty\":\"oct\",\"kid\":\"${toBase64Url(keyId)}\",\"k\":\"${toBase64Url(keyData)}\"}],\"type\":\"temporary\"}"
                val callback = LocalMediaDrmCallback(clearKeyJson.toByteArray(Charsets.UTF_8))
                val drm = DefaultDrmSessionManager.Builder()
                    .setPlayClearSamplesWithoutKeys(true)
                    .setMultiSession(false)
                    .setUuidAndExoMediaDrmProvider(C.CLEARKEY_UUID, FrameworkMediaDrm.DEFAULT_PROVIDER)
                    .build(callback)
                mediaSourceFactory.setDrmSessionManagerProvider { drm }
                itemBuilder.setDrmConfiguration(MediaItem.DrmConfiguration.Builder(C.CLEARKEY_UUID).build())
            }

            val selector = DefaultTrackSelector(this)
            trackSelector = selector
            val exo = ExoPlayer.Builder(this)
                .setTrackSelector(selector)
                .setMediaSourceFactory(mediaSourceFactory)
                .build()

            exo.addListener(object : Player.Listener {
                override fun onTracksChanged(tracks: Tracks) {
                    rebuildQualityOptions(tracks)
                }

                override fun onPlaybackStateChanged(playbackState: Int) {
                    when (playbackState) {
                        Player.STATE_READY -> hideStatus()
                        Player.STATE_BUFFERING -> showStatus("Buffering…")
                        Player.STATE_ENDED -> showStatus("Stream ended")
                    }
                }

                override fun onPlayerError(error: PlaybackException) {
                    tryNextServer("Server unavailable")
                }
            })

            player = exo
            playerView.player = exo
            exo.setMediaItem(itemBuilder.build())
            exo.prepare()
            exo.playWhenReady = true
        } catch (_: Throwable) {
            tryNextServer("Server unavailable")
        }
    }

    private fun tryNextServer(message: String) {
        autoFallbackTried.add(selectedServerIndex)
        for (i in 0 until sources.length()) {
            if (!autoFallbackTried.contains(i)) {
                showStatus("$message • trying backup…")
                playerView.postDelayed({ playServer(i) }, 550)
                return
            }
        }
        showStatus("No working server\nTap Server to choose again")
        autoFallbackTried.clear()
    }

    private fun showServerMenu() {
        val popup = PopupMenu(this, serverButton)
        for (i in 0 until sources.length()) {
            val source = sources.optJSONObject(i)
            val label = source?.optString("label", "Server ${i + 1}") ?: "Server ${i + 1}"
            popup.menu.add(0, 12000 + i, i, label).apply { isChecked = i == selectedServerIndex }
        }
        popup.setOnMenuItemClickListener { item ->
            val i = item.itemId - 12000
            if (i in 0 until sources.length()) {
                autoFallbackTried.clear()
                playServer(i)
                true
            } else false
        }
        popup.show()
    }

    private fun rebuildQualityOptions(tracks: Tracks) {
        val best = linkedMapOf<Int, QualityOption>()
        for (group in tracks.groups) {
            if (group.type != C.TRACK_TYPE_VIDEO) continue
            for (trackIndex in 0 until group.length) {
                if (!group.isTrackSupported(trackIndex)) continue
                val format = group.getTrackFormat(trackIndex)
                val height = format.height
                if (height <= 0) continue
                val bitrate = format.bitrate
                val option = QualityOption("${height}p", group, trackIndex, height, bitrate)
                val old = best[height]
                if (old == null || bitrate > old.bitrate) best[height] = option
            }
        }
        qualityOptions = best.values.sortedByDescending { it.height }.toMutableList()
        runOnUiThread {
            qualityButton.text = forcedQualityLabel ?: "Auto"
            qualityButton.visibility = View.VISIBLE
        }
    }

    private fun showQualityMenu() {
        val selector = trackSelector ?: return
        val popup = PopupMenu(this, qualityButton)
        popup.menu.add(0, 9000, 0, "Auto").apply { isChecked = forcedQualityLabel == null }
        qualityOptions.forEachIndexed { index, option ->
            popup.menu.add(0, 9100 + index, index + 1, option.label).apply { isChecked = forcedQualityLabel == option.label }
        }
        popup.setOnMenuItemClickListener { item ->
            if (item.itemId == 9000) {
                selector.parameters = selector.buildUponParameters().clearOverridesOfType(C.TRACK_TYPE_VIDEO).build()
                forcedQualityLabel = null
                qualityButton.text = "Auto"
                true
            } else {
                val option = qualityOptions.getOrNull(item.itemId - 9100) ?: return@setOnMenuItemClickListener false
                val override = TrackSelectionOverride(option.group.mediaTrackGroup, option.trackIndex)
                selector.parameters = selector.buildUponParameters().clearOverridesOfType(C.TRACK_TYPE_VIDEO).setOverrideForType(override).build()
                forcedQualityLabel = option.label
                qualityButton.text = option.label
                true
            }
        }
        popup.show()
    }

    private fun showStatus(text: String) {
        runOnUiThread {
            if (::statusText.isInitialized) {
                statusText.text = text
                statusText.visibility = View.VISIBLE
            }
        }
    }

    private fun hideStatus() {
        runOnUiThread {
            if (::statusText.isInitialized) statusText.visibility = View.GONE
        }
    }

    private fun showFatalError(text: String) {
        val root = FrameLayout(this).apply { setBackgroundColor(Color.BLACK) }
        val message = TextView(this).apply {
            setTextColor(Color.WHITE)
            textSize = 18f
            gravity = Gravity.CENTER
            this.text = "$text\n\nTap to go back"
            setPadding(dp(24), dp(24), dp(24), dp(24))
            setOnClickListener { finish() }
        }
        root.addView(message, FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))
        setContentView(root)
    }

    private fun overlayButton(value: String): TextView {
        return TextView(this).apply {
            text = value
            setTextColor(Color.WHITE)
            gravity = Gravity.CENTER
            setBackgroundColor(Color.argb(150, 0, 0, 0))
            isClickable = true
            isFocusable = true
        }
    }

    private fun safeHideSystemBars() {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                window.setDecorFitsSystemWindows(false)
                window.insetsController?.let { c ->
                    c.hide(
                        WindowInsets.Type.statusBars() or
                            WindowInsets.Type.navigationBars()
                    )
                    c.systemBarsBehavior =
                        WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
                }
            } else {
                @Suppress("DEPRECATION")
                window.decorView.systemUiVisibility =
                    View.SYSTEM_UI_FLAG_FULLSCREEN or
                        View.SYSTEM_UI_FLAG_HIDE_NAVIGATION or
                        View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY or
                        View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN or
                        View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION or
                        View.SYSTEM_UI_FLAG_LAYOUT_STABLE
            }
        } catch (_: Throwable) {
            // Fullscreen behavior is optional; playback should still continue.
        }
    }

    override fun onDestroy() {
        if (::playerView.isInitialized) playerView.player = null
        player?.release()
        player = null
        trackSelector = null
        super.onDestroy()
    }

    private fun dp(value: Int): Int = (value * resources.displayMetrics.density).toInt()

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
