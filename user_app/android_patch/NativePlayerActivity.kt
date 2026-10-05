package com.example.football_viewer

import android.app.Activity
import android.graphics.Color
import android.os.Build
import android.os.Bundle
import android.util.Base64
import android.view.Gravity
import android.view.MotionEvent
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
    private lateinit var displayModeButton: TextView

    private var sources = JSONArray()
    private var selectedServerIndex = 0
    private var qualityOptions = mutableListOf<QualityOption>()
    private var forcedQualityLabel: String? = null
    private var autoFallbackTried = mutableSetOf<Int>()
    private var playbackStartedServers = mutableSetOf<Int>()
    private var bufferingReportedServers = mutableSetOf<Int>()

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

    private fun emitPlaybackEvent(
        event: String,
        extra: Map<String, Any?> = emptyMap()
    ) {
        val source = sources.optJSONObject(selectedServerIndex)
        val base = mutableMapOf<String, Any?>(
            "selected_index" to selectedServerIndex,
            "line_count" to sources.length(),
            "stream_type" to (source?.optString("streamType", "auto") ?: "auto"),
            "resolution" to (source?.optString("resolution", "") ?: ""),
            "health_status" to (source?.optString("healthStatus", "unknown") ?: "unknown")
        )
        base.putAll(extra)
        MainActivity.emitPlayerEvent(event, base)
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
            // FILL uses the exact PlayerView size on every phone:
            // no letterbox bars and no crop/zoom. Aspect ratio may stretch slightly.
            resizeMode = AspectRatioFrameLayout.RESIZE_MODE_FILL
            useController = true
            // Keep the video clean. Controls appear only after the user taps.
            controllerAutoShow = false
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
            // Server name / quality / back button stay hidden until player
            // controls are shown by a tap.
            visibility = View.GONE
        }

        val back = overlayButton("←").apply {
            textSize = 28f
            contentDescription = "Back"
            setOnClickListener {
                emitPlaybackEvent("playback closed")
                finish()
            }
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

        displayModeButton = overlayButton("Fill").apply {
            textSize = 13f
            setPadding(dp(10), 0, dp(10), 0)
            setOnClickListener { toggleDisplayMode() }
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
        topBar.addView(
            displayModeButton,
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

        // Keep Server / Quality / Back completely hidden until the USER taps.
        // Media3 can briefly report its controller as visible during startup on
        // some Android/OEM builds, so controller visibility alone is not enough.
        var userRequestedControls = false

        playerView.setOnTouchListener { _, event ->
            if (event.action == MotionEvent.ACTION_UP) {
                userRequestedControls = true
            }
            false
        }

        playerView.setControllerVisibilityListener(
            PlayerView.ControllerVisibilityListener { visibility ->
                if (visibility == View.VISIBLE && userRequestedControls) {
                    topBar.visibility = View.VISIBLE
                } else {
                    topBar.visibility = View.GONE
                }

                if (visibility != View.VISIBLE) {
                    userRequestedControls = false
                }
            }
        )

        // Force a clean video surface on entry. Controls appear on the first tap.
        playerView.post {
            playerView.hideController()
            topBar.visibility = View.GONE
        }

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
                        Player.STATE_READY -> {
                            hideStatus()
                            if (playbackStartedServers.add(selectedServerIndex)) {
                                emitPlaybackEvent("playback started")
                            }
                        }
                        Player.STATE_BUFFERING -> {
                            showStatus("Buffering…")
                            if (bufferingReportedServers.add(selectedServerIndex)) {
                                emitPlaybackEvent("playback buffering")
                            }
                        }
                        Player.STATE_ENDED -> {
                            showStatus("Stream ended")
                            emitPlaybackEvent("playback ended")
                        }
                    }
                }

                override fun onPlayerError(error: PlaybackException) {
                    emitPlaybackEvent(
                        "playback line failed",
                        mapOf("error_code" to error.errorCodeName)
                    )
                    tryNextServer("Server unavailable")
                }
            })

            player = exo
            playerView.player = exo
            exo.setMediaItem(itemBuilder.build())
            exo.prepare()
            exo.playWhenReady = true
        } catch (t: Throwable) {
            emitPlaybackEvent(
                "playback line failed",
                mapOf("error_code" to t.javaClass.simpleName)
            )
            tryNextServer("Server unavailable")
        }
    }

    private fun tryNextServer(message: String) {
        autoFallbackTried.add(selectedServerIndex)
        for (i in 0 until sources.length()) {
            if (!autoFallbackTried.contains(i)) {
                val from = selectedServerIndex
                emitPlaybackEvent(
                    "playback auto fallback",
                    mapOf(
                        "from_index" to from,
                        "to_index" to i
                    )
                )
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
                MainActivity.emitPlayerEvent(
                    "playback line selected",
                    mapOf(
                        "selected_index" to i,
                        "line_count" to sources.length()
                    )
                )
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
                emitPlaybackEvent(
                    "playback quality selected",
                    mapOf("quality" to "auto")
                )
                true
            } else {
                val option = qualityOptions.getOrNull(item.itemId - 9100) ?: return@setOnMenuItemClickListener false
                val override = TrackSelectionOverride(option.group.mediaTrackGroup, option.trackIndex)
                selector.parameters = selector.buildUponParameters().clearOverridesOfType(C.TRACK_TYPE_VIDEO).setOverrideForType(override).build()
                forcedQualityLabel = option.label
                qualityButton.text = option.label
                emitPlaybackEvent(
                    "playback quality selected",
                    mapOf("quality" to option.label)
                )
                true
            }
        }
        popup.show()
    }

    private fun toggleDisplayMode() {
        if (!::playerView.isInitialized || !::displayModeButton.isInitialized) return

        if (playerView.resizeMode == AspectRatioFrameLayout.RESIZE_MODE_FILL) {
            // FIT preserves the original aspect ratio and can show bars.
            playerView.resizeMode = AspectRatioFrameLayout.RESIZE_MODE_FIT
            displayModeButton.text = "Fit"
        } else {
            // FILL stretches to the exact screen bounds: no crop, no zoom, no bars.
            playerView.resizeMode = AspectRatioFrameLayout.RESIZE_MODE_FILL
            displayModeButton.text = "Fill"
        }
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
        MainActivity.emitPlayerEvent(
            "playback fatal error",
            mapOf("reason" to text.lineSequence().firstOrNull().orEmpty().take(80))
        )
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
