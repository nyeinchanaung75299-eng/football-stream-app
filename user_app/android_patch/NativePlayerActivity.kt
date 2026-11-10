package com.example.football_viewer

import android.app.Activity
import android.content.pm.ActivityInfo
import android.content.res.Configuration
import android.graphics.Color
import android.content.res.ColorStateList
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.Bundle
import android.os.SystemClock
import android.text.TextUtils
import android.util.Base64
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import android.view.WindowInsets
import android.view.WindowInsetsController
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.HorizontalScrollView
import android.widget.LinearLayout
import android.widget.PopupMenu
import android.widget.SeekBar
import android.widget.ScrollView
import android.widget.TextView
import androidx.media3.common.C
import androidx.media3.common.AudioAttributes
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.TrackSelectionOverride
import androidx.media3.common.Tracks
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.DefaultLoadControl
import androidx.media3.exoplayer.drm.DefaultDrmSessionManager
import androidx.media3.exoplayer.drm.FrameworkMediaDrm
import androidx.media3.exoplayer.drm.LocalMediaDrmCallback
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.exoplayer.trackselection.DefaultTrackSelector
import androidx.media3.ui.AspectRatioFrameLayout
import androidx.media3.ui.PlayerView
import org.json.JSONArray
import java.net.URI
import java.lang.ref.WeakReference
import java.util.Locale

// Uses elapsed time only while playback is expected. Seeking, pausing and
// backgrounding reset the progress baseline rather than consuming a deadline.
internal class PlaybackProgressWatchdog(
    private val startupTimeoutMs: Long = 20000L,
    private val progressTimeoutMs: Long = 25000L
) {
    var started = false
        private set
    private var lastProgressAt = 0L
    private var lastPosition = 0L
    private var initialized = false

    fun resetBaseline(now: Long, position: Long) {
        initialized = true
        lastProgressAt = now
        lastPosition = position
    }

    fun rendered(now: Long, position: Long) {
        started = true
        resetBaseline(now, position)
    }

    fun stalledForMs(now: Long): Long = (now - lastProgressAt).coerceAtLeast(0L)

    // Positive position changes are progress only after discontinuity listeners
    // have reset the baseline; a seek itself must never count as a first frame.
    fun sample(now: Long, position: Long, active: Boolean): Boolean {
        if (!initialized || !active) {
            resetBaseline(now, position)
            return false
        }
        if (position > lastPosition) {
            started = true
            lastProgressAt = now
        } else if (position < lastPosition) {
            lastProgressAt = now
        }
        lastPosition = position
        val timeout = if (started) progressTimeoutMs else startupTimeoutMs
        return now - lastProgressAt >= timeout
    }
}

@UnstableApi
class NativePlayerActivity : Activity() {
    companion object {
        private var activePlayer = WeakReference<NativePlayerActivity>(null)
        private val sourceSessions = PlaybackSourceSessions()

        fun prepareOpeningSession(sessionId: String) {
            sourceSessions.begin(sessionId)
        }

        fun cancelOpeningSession(sessionId: String) {
            sourceSessions.close(sessionId)
        }

        fun appendSources(sessionId: String, json: String): Boolean {
            if (sessionId.isBlank() || json.isBlank() || !sourceSessions.isCurrent(sessionId)) return false
            val activity = activePlayer.get()
            if (activity == null || sessionId != activity.sessionId ||
                activity.isFinishing || activity.isDestroyed) {
                return sourceSessions.enqueueIfOpening(sessionId, json)
            }
            activity.runOnUiThread {
                if (activePlayer.get() === activity && sessionId == activity.sessionId &&
                    sourceSessions.isCurrent(sessionId) && !activity.isFinishing && !activity.isDestroyed) {
                    activity.appendSessionSources(json)
                }
            }
            return true
        }
    }

    private var player: ExoPlayer? = null
    private var trackSelector: DefaultTrackSelector? = null
    private lateinit var playerView: PlayerView
    private lateinit var qualityButton: TextView
    private lateinit var settingsButton: TextView
    private lateinit var serverButton: TextView
    private lateinit var serverRail: LinearLayout
    private lateinit var serverRailScroll: HorizontalScrollView
    private lateinit var statusText: TextView
    private lateinit var compactControls: LinearLayout
    private lateinit var compactPlay: TextView
    private lateinit var compactTime: TextView
    private lateinit var compactSeek: SeekBar
    private lateinit var displayModeButton: TextView
    private lateinit var settingsPanel: LinearLayout
    private lateinit var settingsScroll: ScrollView
    private lateinit var settingsItems: LinearLayout
    private var settingsSection = "video"
    private var selectedAudioLabel: String? = null
    private var selectedSubtitleLabel: String? = null
    private var displayMode = 0 // 0=Fit, 1=Full, 2=Zoom

    private var sources = JSONArray()
    private var selectedServerIndex = 0
    private var matchId = ""
    private var sessionId = ""
    private var qualityOptions = mutableListOf<QualityOption>()
    private var forcedQualityLabel: String? = null
    private var autoFallbackTried = mutableSetOf<Int>()
    private var pendingFallback: Runnable? = null
    private var progressCheck: Runnable? = null
    private var playbackGeneration = 0
    private var activityResumed = false
    private var progressWatchdog = PlaybackProgressWatchdog()
    private var sameLineRecoveryUsed = false
    private var openingStartedAt = 0L
    private var startedReported = false
    private var bufferingStartedAt: Long? = null
    private var bufferingPhase = "startup"
    private var suspendedAt: Long? = null

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
        val streamType = when (source?.optString("streamType").orEmpty().lowercase(Locale.ROOT)) {
            "m3u8", "hls" -> "hls"
            "mpd", "dash" -> "dash"
            "mp4" -> "mp4"
            "flv" -> "flv"
            "auto", "" -> "auto"
            else -> "unknown"
        }
        val resolution = source?.optString("resolution").orEmpty().lowercase(Locale.ROOT)
        val healthStatus = source?.optString("healthStatus").orEmpty().lowercase(Locale.ROOT)
        val base = mutableMapOf<String, Any?>(
            "selected_index" to selectedServerIndex,
            "line_count" to sources.length(),
            "stream_type" to streamType,
            "resolution" to if (resolution.matches(Regex("^(\\d{3,4}p|auto|hd|sd|fhd|uhd|4k)$"))) resolution else "unknown",
            "health_status" to if (healthStatus in setOf("healthy", "unknown", "slow", "failed")) healthStatus else "unknown"
        )
        if (matchId.matches(Regex("^[a-zA-Z0-9_:-]{1,128}$"))) {
            base["match_id"] = matchId
        }
        val lineId = sequenceOf("id", "lineId", "linkId")
            .map { source?.optString(it).orEmpty() }
            .firstOrNull { it.matches(Regex("^[a-zA-Z0-9_:-]{1,128}$")) }
        if (lineId != null) base["line_id"] = lineId
        // Never send protected paths, query tokens, headers or ClearKey values.
        val routeHost = try {
            URI(source?.optString("url").orEmpty())
                .takeIf { it.scheme?.lowercase(Locale.ROOT) in setOf("http", "https") }
                ?.host?.lowercase(Locale.ROOT)
        } catch (_: Exception) { null }
        if (!routeHost.isNullOrBlank()) base["route"] = routeHost
        base.putAll(extra)
        MainActivity.emitPlayerEvent(event, base)
    }

    private fun createPlayerScreen() {
        // Parse the payload before doing any ExoPlayer work.
        matchId = intent.getStringExtra("matchId").orEmpty()
        sessionId = intent.getStringExtra("sessionId").orEmpty()
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
        if (sessionId.isNotBlank() && !sourceSessions.isCurrent(sessionId)) {
            finish()
            return
        }
        activePlayer = WeakReference(this)
        sourceSessions.register(sessionId)?.let { appendSessionSources(it) }

        selectedServerIndex = intent.getIntExtra("selectedIndex", 0)
            .coerceIn(0, sources.length() - 1)

        val portraitStart = sources.optJSONObject(selectedServerIndex)?.optBoolean("portraitStart", false) == true
        // Start with the compact top-aligned portrait player; Rotate enters
        // full landscape playback. Preserve a manual turn across recreation.
        requestedOrientation = if (intent.getBooleanExtra("nca_landscape", false))
            ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE else ActivityInfo.SCREEN_ORIENTATION_PORTRAIT

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
            resizeMode = AspectRatioFrameLayout.RESIZE_MODE_FIT
            // Native Media3 default controls are oversized and show unwanted
            // Previous / Next buttons. Use one slim, accessible transport row.
            useController = false
        }
        // The player controls and progress/time belong to the VIDEO box, not
        // the bottom of an otherwise empty portrait phone screen.
        val videoHost = FrameLayout(this).apply { setBackgroundColor(Color.BLACK) }
        videoHost.addView(playerView,
            FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))
        root.addView(videoHost, FrameLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT,
            Gravity.TOP or Gravity.CENTER_HORIZONTAL))

        val topBar = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(7), dp(4), dp(7), dp(4))
            setBackgroundColor(Color.rgb(21, 21, 30))
            // Server name / quality / back button stay hidden until player
            // controls are shown by a tap.
            visibility = View.GONE
        }

        val back = overlayButton("←").apply {
            textSize = 21f
            contentDescription = "Back"
            setOnClickListener {
                emitPlaybackEvent("playback closed")
                finish()
            }
        }

        val safeTitle = intent.getStringExtra("title")
            .orEmpty()
            .trim()
            .take(120)
            .ifEmpty { "Football Live" }
        val titleText = TextView(this).apply {
            text = safeTitle
            setTextColor(Color.WHITE)
            textSize = 12f
            typeface = Typeface.create("sans-serif", Typeface.BOLD)
            maxLines = 2
            ellipsize = TextUtils.TruncateAt.END
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(6), 0, dp(6), 0)
            contentDescription = "Match: $safeTitle"
        }

        serverButton = overlayButton("≡").apply {
            textSize = 19f
            maxWidth = dp(38)
            setSingleLine(true)
            ellipsize = TextUtils.TruncateAt.END
            setPadding(dp(4), 0, dp(4), 0)
            contentDescription = "Show all lines"
            setOnClickListener { showServerMenu() }
        }

        qualityButton = overlayButton("Auto").apply {
            textSize = 14f
            setPadding(dp(12), 0, dp(12), 0)
            setOnClickListener { openSettingsMenu("video") }
        }

        displayModeButton = overlayButton("Fit").apply {
            contentDescription = "Original aspect ratio; tap for Full"
            textSize = 11f
            setPadding(dp(2), 0, dp(2), 0)
            setOnClickListener { toggleDisplayMode() }
        }

        val rotateButton = overlayButton("↻").apply {
            contentDescription = "Rotate video"
            setOnClickListener {
                val landscape = resources.configuration.orientation != Configuration.ORIENTATION_LANDSCAPE
                intent.putExtra("nca_landscape", landscape)
                requestedOrientation = if (landscape) ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE
                    else ActivityInfo.SCREEN_ORIENTATION_PORTRAIT
            }
        }
        if (visibleServerIndices().size == 1) serverButton.visibility = View.GONE
        topBar.addView(back, LinearLayout.LayoutParams(dp(36), dp(36)))
        topBar.addView(
            titleText,
            LinearLayout.LayoutParams(0, dp(36), 1f)
        )
        topBar.addView(
            displayModeButton,
            LinearLayout.LayoutParams(
                dp(34),
                dp(34)
            )
        )

        topBar.addView(rotateButton, LinearLayout.LayoutParams(dp(36), dp(36)))

        root.addView(
            topBar,
            FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
                Gravity.TOP
            )
        )

        serverRail = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(12), dp(5), dp(12), dp(5))
        }
        serverRailScroll = HorizontalScrollView(this).apply {
            isHorizontalScrollBarEnabled = false
            setBackgroundColor(Color.rgb(16, 16, 24))
            addView(
                serverRail,
                FrameLayout.LayoutParams(
                    ViewGroup.LayoutParams.WRAP_CONTENT,
                    ViewGroup.LayoutParams.MATCH_PARENT
                )
            )
            visibility = View.GONE
        }
        root.addView(
            serverRailScroll,
            FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(50), Gravity.TOP)
        )
        // One compact bottom transport row. Line switching belongs OUTSIDE
        // videoHost in serverRailScroll; no Previous/Next server shortcuts.
        compactControls = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(4), 0, dp(4), 0)
            setBackgroundColor(Color.argb(90, 0, 0, 0))
            visibility = View.GONE
        }
        fun transportButton(label: String, description: String): TextView =
            TextView(this).apply {
                text = label
                contentDescription = description
                textSize = 12f
                setTextColor(Color.WHITE)
                gravity = Gravity.CENTER
                setPadding(0, 0, 0, 0)
                background = null
            }
        val rewind = transportButton("↶5", "Back 5 seconds").apply {
            setOnClickListener {
                val exo = player ?: return@setOnClickListener
                exo.seekTo((exo.currentPosition - 5000L).coerceAtLeast(0L))
                updateCompactControls()
            }
        }
        compactPlay = transportButton("Ⅱ", "Play or pause").apply {
            textSize = 16f
            setOnClickListener {
                val exo = player ?: return@setOnClickListener
                if (exo.isPlaying) exo.pause() else exo.play()
                updateCompactControls()
            }
        }
        val forward = transportButton("15↷", "Forward 15 seconds").apply {
            setOnClickListener {
                val exo = player ?: return@setOnClickListener
                val max = exo.duration
                val target = exo.currentPosition + 15000L
                exo.seekTo(if (max != C.TIME_UNSET && max > 0) target.coerceAtMost(max) else target)
                updateCompactControls()
            }
        }
        compactTime = transportButton("LIVE", "Playback time").apply {
            textSize = 10f
            typeface = Typeface.create("sans-serif", Typeface.BOLD)
            setSingleLine(true)
            setPadding(dp(2), 0, dp(2), 0)
            maxWidth = dp(110)
        }
        compactSeek = SeekBar(this).apply {
            max = 1000
            progress = 0
            progressTintList = ColorStateList.valueOf(Color.rgb(71, 229, 158))
            thumbTintList = ColorStateList.valueOf(Color.rgb(71, 229, 158))
            progressBackgroundTintList = ColorStateList.valueOf(Color.rgb(112, 119, 115))
            contentDescription = "Seek video"
            setOnSeekBarChangeListener(object : SeekBar.OnSeekBarChangeListener {
                override fun onProgressChanged(seekBar: SeekBar?, value: Int, fromUser: Boolean) {}
                override fun onStartTrackingTouch(seekBar: SeekBar?) {}
                override fun onStopTrackingTouch(seekBar: SeekBar?) {
                    val exo = player ?: return
                    val duration = exo.duration
                    if (duration != C.TIME_UNSET && duration > 0) {
                        exo.seekTo(duration * progress / 1000L)
                    }
                }
            })
        }
        settingsButton = overlayButton("⚙").apply {
            textSize = 18f
            background = null
            visibility = View.VISIBLE
            contentDescription = "Resolution audio and playback speed"
            setOnClickListener { showPlaybackSettings() }
        }
        for (view in listOf(rewind, compactPlay, forward)) {
            compactControls.addView(view, LinearLayout.LayoutParams(dp(35), dp(35)))
        }
        compactControls.addView(compactTime, LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.WRAP_CONTENT, dp(35)))
        compactControls.addView(compactSeek, LinearLayout.LayoutParams(0, dp(35), 1f))
        compactControls.addView(settingsButton, LinearLayout.LayoutParams(dp(35), dp(35)))
        videoHost.addView(compactControls, FrameLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT, dp(35), Gravity.BOTTOM
        ))
        val ticker = object : Runnable {
            override fun run() {
                if (isFinishing || isDestroyed) return
                updateCompactControls()
                playerView.postDelayed(this, 450L)
            }
        }
        playerView.post(ticker)
        fun layoutPlayer() {
            if (root.width <= 0 || root.height <= 0) return
            val landscape = root.width > root.height
            val hasLines = visibleServerIndices().size > 1
            val railHeight = if (hasLines) dp(50) else 0
            val headerHeight = dp(44)
            val portraitHeight = (root.width * 9f / 16f).toInt()
                .coerceAtMost((root.height - headerHeight - railHeight).coerceAtLeast(dp(120)))
            // Web reference: portrait player begins at TOP. Empty space belongs
            // below the video. Landscape header overlays, not pushes, video.
            topBar.layoutParams = (topBar.layoutParams as FrameLayout.LayoutParams).apply {
                gravity = Gravity.TOP
                topMargin = 0
            }
            topBar.background = if (landscape) GradientDrawable(
                GradientDrawable.Orientation.TOP_BOTTOM,
                intArrayOf(Color.argb(190, 0, 0, 0), Color.argb(25, 0, 0, 0))
            ) else GradientDrawable().apply { setColor(Color.rgb(21, 21, 30)) }
            topBar.visibility = View.VISIBLE
            videoHost.layoutParams = (videoHost.layoutParams as FrameLayout.LayoutParams).apply {
                width = ViewGroup.LayoutParams.MATCH_PARENT
                height = if (landscape) (root.height - railHeight).coerceAtLeast(dp(120))
                    else portraitHeight
                gravity = Gravity.TOP
                topMargin = if (landscape) 0 else headerHeight
            }
            serverRailScroll.layoutParams =
                (serverRailScroll.layoutParams as FrameLayout.LayoutParams).apply {
                    gravity = Gravity.TOP
                    topMargin = if (landscape) root.height - railHeight
                        else headerHeight + portraitHeight
                }
            serverRailScroll.visibility = if (hasLines) View.VISIBLE else View.GONE
            if (::settingsPanel.isInitialized) positionSettingsPanel(root, landscape)
        }
        root.addOnLayoutChangeListener { _, _, _, _, _, _, _, _, _ -> layoutPlayer() }
        root.post { layoutPlayer(); applyDisplayMode() }
        renderServerRail()

        // Transport controls are small and anchored at the picture bottom.
        // Touching the video toggles them; source line chips stay below video.
        playerView.setOnTouchListener { _, event ->
            if (event.action == MotionEvent.ACTION_UP) {
                if (::settingsPanel.isInitialized && settingsPanel.visibility == View.VISIBLE) {
                    closeSettingsMenu()
                } else {
                    compactControls.visibility =
                        if (compactControls.visibility == View.VISIBLE) View.GONE else View.VISIBLE
                }
            }
            true
        }
        playerView.post {
            topBar.visibility = View.VISIBLE
            compactControls.visibility = View.GONE
            serverRailScroll.visibility =
                if (visibleServerIndices().size > 1) View.VISIBLE else View.GONE
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

        // Web-style settings are a dark native overlay, not Android PopupMenu.
        // Add last so the panel remains above playback/status without replacing Media3.
        buildSettingsPanel(root)

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

    private fun updateCompactControls() {
        if (!::compactControls.isInitialized) return
        val exo = player ?: return
        compactPlay.text = if (exo.isPlaying) "Ⅱ" else "▶"
        val duration = exo.duration
        val position = exo.currentPosition.coerceAtLeast(0)
        fun time(milliseconds: Long): String {
            val seconds = milliseconds.coerceAtLeast(0) / 1000
            return if (seconds >= 3600) String.format(
                Locale.US, "%d:%02d:%02d", seconds / 3600, (seconds / 60) % 60, seconds % 60
            ) else String.format(Locale.US, "%d:%02d", seconds / 60, seconds % 60)
        }
        if (duration == C.TIME_UNSET || duration <= 0) {
            compactTime.text = "● LIVE"
            compactSeek.isEnabled = false
            compactSeek.progress = 0
        } else {
            compactTime.text = "${time(position)} / ${time(duration)}"
            compactSeek.isEnabled = true
            compactSeek.progress = ((position * 1000L) / duration).toInt().coerceIn(0, 1000)
        }
    }

    private fun playServer(index: Int, recoveringSameLine: Boolean = false) {
        if (index !in 0 until sources.length()) return
        pendingFallback?.let { if (::playerView.isInitialized) playerView.removeCallbacks(it) }
        pendingFallback = null
        stopProgressCheck()
        playbackGeneration += 1
        selectedServerIndex = index
        renderServerRail()
        val source = sources.optJSONObject(index) ?: return
        val url = source.optString("url").trim()
        if (url.isBlank()) {
            tryNextServer("Empty stream URL")
            return
        }

        sameLineRecoveryUsed = recoveringSameLine
        progressWatchdog = PlaybackProgressWatchdog()
        openingStartedAt = SystemClock.elapsedRealtime()
        progressWatchdog.resetBaseline(openingStartedAt, 0L)
        startedReported = false
        bufferingStartedAt = null
        suspendedAt = if (activityResumed) null else openingStartedAt
        forcedQualityLabel = null
        selectedAudioLabel = null
        selectedSubtitleLabel = null
        closeSettingsMenu()
        qualityOptions.clear()
        qualityButton.text = "Auto"
        showStatus("Opening ${serverLabel(index)}…")

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
                // Start after one second of media, then build a bounded live
                // buffer. Rebuffering still waits longer to absorb mobile jitter.
                .setLoadControl(DefaultLoadControl.Builder()
                    .setBufferDurationsMs(15000, 30000, 1000, 2500)
                    .build())
                .setMediaSourceFactory(mediaSourceFactory)
                .setAudioAttributes(AudioAttributes.DEFAULT, true)
                .setHandleAudioBecomingNoisy(true)
                .build()

            val generation = playbackGeneration
            fun currentPlayback() = generation == playbackGeneration && player === exo && pendingFallback == null &&
                !isFinishing && !isDestroyed

            exo.addListener(object : Player.Listener {
                override fun onTracksChanged(tracks: Tracks) {
                    if (!currentPlayback()) return
                    rebuildQualityOptions(tracks)
                }

                override fun onRenderedFirstFrame() {
                    if (!currentPlayback()) return
                    val active = activityResumed && exo.playWhenReady &&
                        exo.playbackSuppressionReason == Player.PLAYBACK_SUPPRESSION_REASON_NONE
                    updatePlaybackTiming(active)
                    progressWatchdog.rendered(SystemClock.elapsedRealtime(), exo.currentPosition)
                    if (active) reportPlaybackProgress()
                }

                override fun onPositionDiscontinuity(
                    oldPosition: Player.PositionInfo,
                    newPosition: Player.PositionInfo,
                    reason: Int
                ) {
                    if (!currentPlayback()) return
                    progressWatchdog.resetBaseline(SystemClock.elapsedRealtime(), exo.currentPosition)
                    lastSamplePosition = exo.currentPosition
                }

                override fun onPlayWhenReadyChanged(playWhenReady: Boolean, reason: Int) {
                    if (!currentPlayback()) return
                    updatePlaybackTiming(activityResumed && playWhenReady)
                    progressWatchdog.resetBaseline(SystemClock.elapsedRealtime(), exo.currentPosition)
                }

                override fun onPlaybackStateChanged(playbackState: Int) {
                    if (!currentPlayback()) return
                    when (playbackState) {
                        Player.STATE_READY -> {
                            if (progressWatchdog.started) hideStatus()
                        }
                        Player.STATE_BUFFERING -> {
                            showStatus("Buffering…")
                            beginBuffering()
                        }
                        Player.STATE_ENDED -> {
                            showStatus("Stream ended")
                            emitPlaybackEvent("playback ended")
                            stopProgressCheck()
                            // Finite videos may end normally. Only a confirmed
                            // live timeline is recovered automatically.
                            if (activityResumed && exo.playWhenReady && exo.isCurrentMediaItemLive) {
                                recoverOrFallback("Live stream ended")
                            }
                        }
                    }
                }

                override fun onPlayerError(error: PlaybackException) {
                    if (!currentPlayback()) return
                    emitPlaybackEvent(
                        "playback line failed",
                        mapOf("error_code" to error.errorCode)
                    )
                    tryNextServer("Server unavailable")
                }
            })

            player = exo
            playerView.player = exo
            exo.setMediaItem(itemBuilder.build())
            exo.prepare()
            exo.playWhenReady = true
            startProgressCheck(exo, generation)
        } catch (t: Throwable) {
            emitPlaybackEvent(
                "playback line failed",
                mapOf("error_code" to t.javaClass.simpleName)
            )
            tryNextServer("Server unavailable")
        }
    }

    private fun beginBuffering() {
        if (!activityResumed || player?.playWhenReady != true || bufferingStartedAt != null) return
        bufferingStartedAt = SystemClock.elapsedRealtime()
        bufferingPhase = if (startedReported) "rebuffer" else "startup"
        emitPlaybackEvent("playback buffering", mapOf("phase" to bufferingPhase))
    }

    private fun appendSessionSources(json: String) {
        val updated = try { JSONArray(json) } catch (_: Exception) { return }
        if (updated.length() <= sources.length()) return
        // Late backups can extend the chooser only. Keep the current player,
        // selection and existing source credentials unchanged.
        val identityFields = arrayOf("id", "lineId", "linkId", "url", "streamType", "referer", "origin", "keyId", "keyData")
        for (i in 0 until sources.length()) {
            val before = sources.optJSONObject(i) ?: return
            val after = updated.optJSONObject(i) ?: return
            if (identityFields.any { before.optString(it) != after.optString(it) }) return
        }
        val additions = mutableListOf<org.json.JSONObject>()
        for (i in sources.length() until updated.length()) {
            val source = updated.optJSONObject(i) ?: return
            if (source.optString("url").isBlank()) return
            additions.add(source)
        }
        additions.forEach { sources.put(it) }
        renderServerRail()
    }

    private fun reportPlaybackProgress() {
        val now = SystemClock.elapsedRealtime()
        if (!startedReported) {
            startedReported = true
            emitPlaybackEvent("playback started", mapOf("startup_ms" to (now - openingStartedAt).coerceAtLeast(0L)))
        }
        bufferingStartedAt?.let {
            emitPlaybackEvent("playback buffering ended", mapOf(
                "phase" to bufferingPhase,
                "buffering_ms" to (now - it).coerceAtLeast(0L)
            ))
            bufferingStartedAt = null
        }
        hideStatus()
    }

    private fun updatePlaybackTiming(active: Boolean) {
        val now = SystemClock.elapsedRealtime()
        if (!active) {
            if (suspendedAt == null) suspendedAt = now
        } else {
            suspendedAt?.let {
                val inactiveMs = (now - it).coerceAtLeast(0L)
                openingStartedAt += inactiveMs
                bufferingStartedAt = bufferingStartedAt?.plus(inactiveMs)
            }
            suspendedAt = null
        }
    }

    private fun startProgressCheck(exo: ExoPlayer, generation: Int) {
        stopProgressCheck()
        val check = object : Runnable {
            override fun run() {
                if (generation != playbackGeneration || player !== exo || isFinishing || isDestroyed) return
                val active = activityResumed && exo.playWhenReady &&
                    exo.playbackSuppressionReason == Player.PLAYBACK_SUPPRESSION_REASON_NONE
                updatePlaybackTiming(active)
                val position = exo.currentPosition
                val beforeStarted = progressWatchdog.started
                val progressed = position > lastSamplePosition
                val timedOut = progressWatchdog.sample(SystemClock.elapsedRealtime(), position, active)
                lastSamplePosition = position
                if (active && progressWatchdog.started && (!beforeStarted || progressed)) reportPlaybackProgress()
                if (active && exo.playbackState == Player.STATE_BUFFERING) beginBuffering()
                if (active && progressWatchdog.started && progressWatchdog.stalledForMs(SystemClock.elapsedRealtime()) >= 2000L) {
                    beginBuffering()
                }
                if (active && timedOut) {
                    beginBuffering()
                    recoverOrFallback(if (startedReported) "Playback stalled" else "Stream startup timed out")
                    return
                }
                playerView.postDelayed(this, 1000L)
            }
        }
        lastSamplePosition = exo.currentPosition
        progressCheck = check
        playerView.postDelayed(check, 1000L)
    }

    private var lastSamplePosition = 0L

    private fun stopProgressCheck() {
        progressCheck?.let { if (::playerView.isInitialized) playerView.removeCallbacks(it) }
        progressCheck = null
    }

    private fun recoverOrFallback(reason: String) {
        stopProgressCheck()
        if (!sameLineRecoveryUsed) {
            emitPlaybackEvent("playback recovery", mapOf(
                "reason" to reason,
                "phase" to if (startedReported) "rebuffer" else "startup",
                "attempt" to 1
            ))
            showStatus("$reason • reconnecting…")
            playServer(selectedServerIndex, recoveringSameLine = true)
        } else {
            emitPlaybackEvent("playback line failed", mapOf(
                "error_code" to if (reason == "Live stream ended") "LIVE_STREAM_ENDED" else "PLAYBACK_PROGRESS_TIMEOUT",
                "phase" to if (startedReported) "rebuffer" else "startup"
            ))
            tryNextServer(reason)
        }
    }

    private fun tryNextServer(message: String) {
        stopProgressCheck()
        autoFallbackTried.add(selectedServerIndex)
        renderServerRail()
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
                val generation = playbackGeneration
                val fallback = object : Runnable {
                    override fun run() {
                        if (generation != playbackGeneration || isFinishing || isDestroyed) return
                        if (!activityResumed || player?.playWhenReady == false) {
                            playerView.postDelayed(this, 1000L)
                            return
                        }
                        pendingFallback = null
                        playServer(i)
                    }
                }
                pendingFallback?.let { playerView.removeCallbacks(it) }
                pendingFallback = fallback
                playerView.postDelayed(fallback, 550)
                return
            }
        }
        showStatus("No working server\nTap Server to choose again")
        autoFallbackTried.clear()
        renderServerRail()
    }

    private fun visibleServerIndices(): List<Int> =
        (0 until sources.length()).filter { index ->
            sources.optJSONObject(index)?.optString("transport") != "vercel-fallback"
        }

    private fun showServerMenu() {
        val popup = PopupMenu(this, serverButton)
        for (i in visibleServerIndices()) {
            popup.menu.add(0, 12000 + i, i, serverLabel(i)).apply {
                isChecked = i == selectedServerIndex
            }
        }
        popup.setOnMenuItemClickListener { item ->
            val i = item.itemId - 12000
            if (i in 0 until sources.length()) {
                selectServer(i)
                true
            } else false
        }
        popup.show()
    }

    private fun selectServer(index: Int) {
        if (index !in 0 until sources.length() || index == selectedServerIndex) return
        autoFallbackTried.clear()
        MainActivity.emitPlayerEvent(
            "playback line selected",
            mapOf(
                "selected_index" to index,
                "line_count" to sources.length()
            )
        )
        playServer(index)
    }

    private fun serverLabel(index: Int): String {
        val source = sources.optJSONObject(index)
        val raw = source?.optString("label")
            ?.trim()
            .orEmpty()
            .ifEmpty { source?.optString("resolution")?.trim().orEmpty() }
        val unsafe = raw.length > 80 ||
            Regex("[/?:=&@\\\\]").containsMatchIn(raw) ||
            Regex("(?i)\\b(?:referer|origin|authorization|token|key|kid)\\s*[:=]")
                .containsMatchIn(raw) ||
            Regex("(?i)\\b[0-9a-f]{24,}\\b").containsMatchIn(raw)
        return if (raw.isEmpty() || unsafe) "Line ${index + 1}"
            else raw.replaceFirst(Regex("""(?i)^\s*([^·•|]+?)\s*[·•|]\s*\1(?=\s*[·•|]|$)"""), "$1").trim()
    }

    private fun renderServerRail() {
        if (!::serverRail.isInitialized || !::serverRailScroll.isInitialized) return
        serverRail.removeAllViews()
        var selectedChip: View? = null
        for (i in visibleServerIndices()) {
            val selected = i == selectedServerIndex
            val failed = autoFallbackTried.contains(i)
            val chip = TextView(this).apply {
                text = when {
                    selected -> "✓ ${serverLabel(i)}"
                    failed -> "! ${serverLabel(i)}"
                    else -> serverLabel(i)
                }
                setTextColor(
                    when {
                        selected -> Color.rgb(82, 224, 154)
                        failed -> Color.rgb(255, 145, 145)
                        else -> Color.WHITE
                    }
                )
                textSize = 11f
                typeface = Typeface.create("sans-serif", Typeface.BOLD)
                gravity = Gravity.CENTER
                setSingleLine(true)
                ellipsize = TextUtils.TruncateAt.END
                maxWidth = dp(165)
                minWidth = dp(70)
                setPadding(dp(10), 0, dp(10), 0)
                isSelected = selected
                contentDescription = if (selected) {
                    "${serverLabel(i)}, selected line"
                } else {
                    "${serverLabel(i)}, line"
                }
                background = GradientDrawable().apply {
                    shape = GradientDrawable.RECTANGLE
                    cornerRadius = dp(7).toFloat()
                    setColor(
                        if (selected) Color.rgb(22, 60, 45)
                        else Color.rgb(23, 26, 25)
                    )
                    setStroke(
                        if (selected) dp(2) else dp(1),
                        when {
                            selected -> Color.rgb(82, 224, 154)
                            failed -> Color.rgb(220, 94, 94)
                            else -> Color.rgb(100, 100, 100)
                        }
                    )
                }
                setOnClickListener { selectServer(i) }
            }
            serverRail.addView(
                chip,
                LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.WRAP_CONTENT,
                    dp(40)
                ).apply {
                    marginEnd = dp(8)
                }
            )
            if (selected) selectedChip = chip
        }
        selectedChip?.let { chip ->
            serverRailScroll.post {
                serverRailScroll.smoothScrollTo((chip.left - dp(12)).coerceAtLeast(0), 0)
            }
        }
    }

    private fun rebuildQualityOptions(tracks: Tracks) {
        val best = linkedMapOf<String, QualityOption>()
        for (group in tracks.groups) {
            if (group.type != C.TRACK_TYPE_VIDEO) continue
            for (trackIndex in 0 until group.length) {
                if (!group.isTrackSupported(trackIndex)) continue
                val format = group.getTrackFormat(trackIndex)
                val height = format.height
                if (height <= 0) continue
                val bitrate = format.bitrate
                val width = format.width.coerceAtLeast(0)
                val label = if (bitrate > 0)
                    "${width} × ${height} • ${String.format(Locale.US, "%.2f", bitrate / 1000000.0)} Mbps"
                    else "${height}p"
                val option = QualityOption(label, group, trackIndex, height, bitrate)
                best["${width}x${height}@${bitrate}"] = option
            }
        }
        qualityOptions = best.values.sortedWith(
            compareByDescending<QualityOption> { it.height }.thenByDescending { it.bitrate }
        ).toMutableList()
        runOnUiThread {
            qualityButton.text = forcedQualityLabel ?: "Auto"
            qualityButton.visibility = View.VISIBLE
        }
    }

    // Web reference: dark, compact, tabbed PLAYER SETTINGS dialog with a
    // real close X, compact system-font rows and selected green checkmarks.
    // Only the controls are native views; Media3 and its track selector stay intact.
    private fun buildSettingsPanel(root: FrameLayout) {
        settingsPanel = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            visibility = View.GONE
            elevation = dp(14).toFloat()
            background = GradientDrawable().apply {
                cornerRadius = dp(16).toFloat()
                setColor(Color.rgb(18, 18, 18))
                setStroke(dp(1), Color.rgb(71, 72, 83))
            }
            clipToPadding = false
            contentDescription = "Player settings"
        }

        val header = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(9), dp(7), dp(9), dp(4))
        }
        val back = overlayButton("←").apply {
            textSize = 16f
            contentDescription = "Back to video settings"
            setOnClickListener {
                if (settingsSection == "video") closeSettingsMenu()
                else openSettingsMenu("video")
            }
        }
        val heading = TextView(this).apply {
            text = "PLAYER SETTINGS"
            textSize = 12f
            typeface = Typeface.create("sans-serif", Typeface.BOLD)
            letterSpacing = 0.02f
            setTextColor(Color.rgb(189, 189, 189))
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(6), 0, dp(6), 0)
        }
        val close = overlayButton("✕").apply {
            textSize = 16f
            contentDescription = "Close player settings"
            setOnClickListener { closeSettingsMenu() }
        }
        header.addView(back, LinearLayout.LayoutParams(dp(34), dp(34)))
        header.addView(heading, LinearLayout.LayoutParams(0, dp(34), 1f))
        header.addView(close, LinearLayout.LayoutParams(dp(34), dp(34)))
        settingsPanel.addView(header, LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT, dp(45)))

        settingsItems = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(7), dp(3), dp(7), dp(7))
        }
        settingsScroll = ScrollView(this).apply {
            isVerticalScrollBarEnabled = false
            isFillViewport = false
            addView(settingsItems, ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT))
        }
        settingsPanel.addView(settingsScroll, LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT))
        root.addView(settingsPanel, FrameLayout.LayoutParams(
            dp(335), ViewGroup.LayoutParams.WRAP_CONTENT, Gravity.TOP or Gravity.END
        ).apply {
            topMargin = dp(54)
            rightMargin = dp(8)
        })
    }

    private fun positionSettingsPanel(root: FrameLayout, landscape: Boolean) {
        if (!::settingsPanel.isInitialized) return
        val widthAvailable = (root.width - dp(16)).coerceAtLeast(dp(160))
        val width = if (landscape) {
            minOf(dp(335), widthAvailable, (root.width * 0.48f).toInt().coerceAtLeast(dp(180)))
        } else minOf(dp(335), widthAvailable)
        settingsPanel.layoutParams = (settingsPanel.layoutParams as FrameLayout.LayoutParams).apply {
            this.width = width
            this.height = ViewGroup.LayoutParams.WRAP_CONTENT
            gravity = Gravity.TOP or Gravity.END
            topMargin = if (landscape) dp(50) else dp(54)
            rightMargin = dp(8)
        }
    }

    private fun settingsBackground(selected: Boolean, radius: Int = 8): GradientDrawable =
        GradientDrawable().apply {
            cornerRadius = dp(radius).toFloat()
            setColor(if (selected) Color.rgb(23, 49, 40) else Color.rgb(29, 29, 29))
            setStroke(dp(1), if (selected) Color.rgb(56, 185, 121)
                else Color.rgb(65, 65, 65))
        }

    private fun addSettingsChoice(
        label: String,
        subtitle: String,
        selected: Boolean,
        enabled: Boolean = true,
        onSelect: () -> Unit
    ) {
        val row = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            minimumHeight = dp(36)
            setPadding(dp(8), dp(5), dp(8), dp(5))
            background = settingsBackground(selected)
            alpha = if (enabled) 1f else 0.48f
            isClickable = enabled
            isFocusable = enabled
            contentDescription = label + if (selected) ", selected" else ""
            if (enabled) setOnClickListener {
                onSelect()
                closeSettingsMenu()
                updateCompactControls()
            }
        }
        val textColumn = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_VERTICAL
        }
        textColumn.addView(TextView(this).apply {
            text = label
            textSize = 12f
            typeface = Typeface.create("sans-serif", Typeface.BOLD)
            setTextColor(Color.WHITE)
            maxLines = 1
            ellipsize = TextUtils.TruncateAt.END
        })
        textColumn.addView(TextView(this).apply {
            text = subtitle
            textSize = 10f
            typeface = Typeface.create("sans-serif", Typeface.NORMAL)
            setTextColor(Color.rgb(189, 189, 189))
            maxLines = 1
            ellipsize = TextUtils.TruncateAt.END
        })
        row.addView(textColumn, LinearLayout.LayoutParams(0,
            ViewGroup.LayoutParams.WRAP_CONTENT, 1f))
        if (selected) row.addView(TextView(this).apply {
            text = "✓"
            textSize = 11f
            typeface = Typeface.create("sans-serif", Typeface.BOLD)
            setTextColor(Color.rgb(143, 227, 185))
            gravity = Gravity.CENTER
        }, LinearLayout.LayoutParams(dp(26), dp(24)))
        settingsItems.addView(row, LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT
        ).apply {
            topMargin = dp(3)
            bottomMargin = dp(3)
        })
    }

    private fun showPlaybackSettings() {
        if (!::settingsPanel.isInitialized) return
        if (settingsPanel.visibility == View.VISIBLE) closeSettingsMenu()
        else openSettingsMenu("video")
    }

    private fun closeSettingsMenu() {
        if (::settingsPanel.isInitialized) settingsPanel.visibility = View.GONE
    }

    private fun openSettingsMenu(section: String) {
        if (!::settingsPanel.isInitialized || isFinishing || isDestroyed) return
        settingsSection = section
        settingsItems.removeAllViews()
        val tabs = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(0, dp(3), 0, dp(5))
        }
        for ((key, label) in listOf(
            "video" to "VIDEO", "audio" to "AUDIO",
            "subtitles" to "SUBTITLES", "speed" to "SPEED"
        )) {
            val active = section == key
            val tab = overlayButton(label).apply {
                textSize = 10f
                background = settingsBackground(active, 7)
                setTextColor(if (active) Color.rgb(143, 227, 185) else Color.WHITE)
                setPadding(dp(2), 0, dp(2), 0)
                contentDescription = label + if (active) ", selected tab" else " tab"
                setOnClickListener { openSettingsMenu(key) }
            }
            tabs.addView(tab, LinearLayout.LayoutParams(0, dp(34), 1f).apply {
                marginEnd = if (key != "speed") dp(3) else 0
            })
        }
        settingsItems.addView(tabs, LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT, dp(42)))
        var choices = 0
        fun choice(label: String, subtitle: String, selected: Boolean,
            enabled: Boolean = true, select: () -> Unit) {
            addSettingsChoice(label, subtitle, selected, enabled, select)
            choices++
        }

        when (section) {
            "video" -> {
                val selector = trackSelector
                val generation = playbackGeneration
                choice("Auto", "Adaptive quality", forcedQualityLabel == null) {
                    if (generation != playbackGeneration || selector == null) return@choice
                    selector.parameters = selector.buildUponParameters()
                        .clearOverridesOfType(C.TRACK_TYPE_VIDEO).build()
                    forcedQualityLabel = null
                    qualityButton.text = "Auto"
                    emitPlaybackEvent("playback quality selected", mapOf("quality" to "auto"))
                }
                qualityOptions.forEach { option ->
                    choice(option.label, "Video track", forcedQualityLabel == option.label) {
                        if (generation != playbackGeneration || selector == null) return@choice
                        val override = TrackSelectionOverride(option.group.mediaTrackGroup, option.trackIndex)
                        selector.parameters = selector.buildUponParameters()
                            .clearOverridesOfType(C.TRACK_TYPE_VIDEO)
                            .setOverrideForType(override).build()
                        forcedQualityLabel = option.label
                        qualityButton.text = option.label
                        emitPlaybackEvent("playback quality selected",
                            mapOf("quality" to option.label))
                    }
                }
                if (qualityOptions.isEmpty()) {
                    choice("Auto only", "No manual video track exposed by stream.", false, false) {}
                }
            }
            "audio" -> {
                val selector = trackSelector
                choice("Auto", "Default audio", selectedAudioLabel == null) {
                    if (selector == null) return@choice
                    selector.parameters = selector.buildUponParameters()
                        .clearOverridesOfType(C.TRACK_TYPE_AUDIO).build()
                    selectedAudioLabel = null
                }
                player?.currentTracks?.groups?.forEach { group ->
                    if (group.type != C.TRACK_TYPE_AUDIO) return@forEach
                    for (i in 0 until group.length) {
                        if (!group.isTrackSupported(i)) continue
                        val format = group.getTrackFormat(i)
                        val language = format.language?.takeIf { it.isNotBlank() } ?: "Track"
                        val label = listOfNotNull(
                            format.label?.takeIf { it.isNotBlank() }, language
                        ).distinct().joinToString(" • ")
                        choice(label, "Audio track", selectedAudioLabel == label) {
                            if (selector == null) return@choice
                            selector.parameters = selector.buildUponParameters()
                                .clearOverridesOfType(C.TRACK_TYPE_AUDIO)
                                .setOverrideForType(TrackSelectionOverride(group.mediaTrackGroup, i))
                                .build()
                            selectedAudioLabel = label
                        }
                    }
                }
            }
            "subtitles" -> {
                val selector = trackSelector
                choice("Off", "Disable subtitles", selectedSubtitleLabel == null) {
                    if (selector == null) return@choice
                    selector.parameters = selector.buildUponParameters()
                        .clearOverridesOfType(C.TRACK_TYPE_TEXT)
                        .setTrackTypeDisabled(C.TRACK_TYPE_TEXT, true).build()
                    selectedSubtitleLabel = null
                }
                player?.currentTracks?.groups?.forEach { group ->
                    if (group.type != C.TRACK_TYPE_TEXT) return@forEach
                    for (i in 0 until group.length) {
                        if (!group.isTrackSupported(i)) continue
                        val format = group.getTrackFormat(i)
                        val label = format.label?.takeIf { it.isNotBlank() }
                            ?: format.language?.takeIf { it.isNotBlank() }
                            ?: "Subtitles " + (i + 1)
                        choice(label, "Subtitle track", selectedSubtitleLabel == label) {
                            if (selector == null) return@choice
                            selector.parameters = selector.buildUponParameters()
                                .setTrackTypeDisabled(C.TRACK_TYPE_TEXT, false)
                                .clearOverridesOfType(C.TRACK_TYPE_TEXT)
                                .setOverrideForType(TrackSelectionOverride(group.mediaTrackGroup, i))
                                .build()
                            selectedSubtitleLabel = label
                        }
                    }
                }
            }
            else -> {
                val exo = player
                for (speed in listOf(0.5f, 0.75f, 1f, 1.25f, 1.5f, 2f)) {
                    val label = if (speed == 1f) "Normal · 1×" else speed.toString() + "×"
                    choice(label, "Playback speed",
                        exo != null && kotlin.math.abs(exo.playbackParameters.speed - speed) < 0.01f) {
                        exo?.setPlaybackSpeed(speed)
                    }
                }
            }
        }
        settingsPanel.visibility = View.VISIBLE
        // Up to 455dp like Web. Short option lists do not create a blank box.
        val root = settingsPanel.parent as? FrameLayout
        val heightAvailable = root?.height?.takeIf { it > 0 }
            ?: resources.displayMetrics.heightPixels
        val isLandscape = resources.configuration.orientation == Configuration.ORIENTATION_LANDSCAPE
        if (root != null && root.width > 0) positionSettingsPanel(root, isLandscape)
        val maxScroll = minOf(dp(455), (heightAvailable * 0.61f).toInt()
            .coerceAtLeast(dp(90)))
        settingsScroll.layoutParams = (settingsScroll.layoutParams as LinearLayout.LayoutParams).apply {
            height = minOf(maxScroll, dp(42) + choices * dp(49))
        }
        settingsScroll.scrollTo(0, 0)
        compactControls.visibility = View.VISIBLE
    }

    @Deprecated("Deprecated in Android SDK")
    override fun onBackPressed() {
        if (::settingsPanel.isInitialized && settingsPanel.visibility == View.VISIBLE) {
            closeSettingsMenu()
        } else {
            super.onBackPressed()
        }
    }

    private fun toggleDisplayMode() {
        if (!::playerView.isInitialized || !::displayModeButton.isInitialized) return
        displayMode = (displayMode + 1) % 3
        applyDisplayMode()
    }

    private fun applyDisplayMode() {
        if (!::playerView.isInitialized) return
        // Do not crop the score overlay by default; the video host remains a
        // 16:9 frame in portrait, and fullscreen in landscape.
        playerView.resizeMode = when (displayMode) {
            0 -> AspectRatioFrameLayout.RESIZE_MODE_FIT
            1 -> AspectRatioFrameLayout.RESIZE_MODE_FILL
            else -> AspectRatioFrameLayout.RESIZE_MODE_ZOOM
        }
        if (::displayModeButton.isInitialized) {
            displayModeButton.text = when (displayMode) {
                0 -> "Fit"
                1 -> "Full"
                else -> "Zoom"
            }
            displayModeButton.contentDescription = when (displayMode) {
                0 -> "Fit video; tap for Full"
                1 -> "Stretch to fill; tap for Zoom"
                else -> "Crop to fill; tap for Fit"
            }
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
        sourceSessions.close(sessionId)
        if (activePlayer.get() === this) activePlayer.clear()
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
            textSize = 12f
            typeface = Typeface.create("sans-serif", Typeface.BOLD)
            setTextColor(Color.WHITE)
            gravity = Gravity.CENTER
            background = GradientDrawable().apply {
                cornerRadius = dp(7).toFloat()
                setColor(Color.rgb(30, 30, 41))
                setStroke(dp(1), Color.rgb(57, 57, 69))
            }
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
        sourceSessions.close(sessionId)
        if (activePlayer.get() === this) activePlayer.clear()
        stopProgressCheck()
        pendingFallback?.let { if (::playerView.isInitialized) playerView.removeCallbacks(it) }
        pendingFallback = null
        playbackGeneration += 1
        if (::playerView.isInitialized) playerView.player = null
        player?.release()
        player = null
        trackSelector = null
        super.onDestroy()
    }

    override fun onPause() {
        activityResumed = false
        updatePlaybackTiming(false)
        stopProgressCheck()
        pendingFallback?.let { if (::playerView.isInitialized) playerView.removeCallbacks(it) }
        player?.let { progressWatchdog.resetBaseline(SystemClock.elapsedRealtime(), it.currentPosition) }
        super.onPause()
    }

    override fun onResume() {
        super.onResume()
        activityResumed = true
        val exo = player ?: return
        updatePlaybackTiming(exo.playWhenReady)
        progressWatchdog.resetBaseline(SystemClock.elapsedRealtime(), exo.currentPosition)
        val fallback = pendingFallback
        if (fallback != null) {
            playerView.removeCallbacks(fallback)
            playerView.postDelayed(fallback, 550L)
        } else if (exo.playbackState == Player.STATE_ENDED) {
            if (exo.playWhenReady && exo.isCurrentMediaItemLive) recoverOrFallback("Live stream ended")
        } else {
            startProgressCheck(exo, playbackGeneration)
        }
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
