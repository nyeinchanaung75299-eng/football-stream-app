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
import android.widget.PopupMenu
import android.widget.TextView
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
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

    private var sources = JSONArray()
    private var selectedServerIndex = 0
    private var qualityOptions = mutableListOf<QualityOption>()
    private var forcedQualityLabel: String? = null

    private data class QualityOption(
        val label: String,
        val group: Tracks.Group,
        val trackIndex: Int,
        val height: Int,
        val bitrate: Int
    )

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        window.statusBarColor = Color.BLACK
        window.navigationBarColor = Color.BLACK
        hideSystemBars()

        val json = intent.getStringExtra("sourcesJson").orEmpty()
        if (json.isBlank()) {
            finish()
            return
        }

        try {
            sources = JSONArray(json)
        } catch (_: Throwable) {
            finish()
            return
        }

        if (sources.length() == 0) {
            finish()
            return
        }

        selectedServerIndex = intent.getIntExtra("selectedIndex", 0)
            .coerceIn(0, sources.length() - 1)

        val root = FrameLayout(this).apply {
            setBackgroundColor(Color.BLACK)
        }

        playerView = PlayerView(this).apply {
            setBackgroundColor(Color.BLACK)
            resizeMode = AspectRatioFrameLayout.RESIZE_MODE_ZOOM
            useController = true
            controllerAutoShow = true
        }

        root.addView(
            playerView,
            FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            )
        )

        val back = overlayButton("←").apply {
            contentDescription = "Back"
            setOnClickListener { finish() }
        }

        root.addView(
            back,
            FrameLayout.LayoutParams(
                dp(52),
                dp(46),
                Gravity.TOP or Gravity.START
            ).apply {
                leftMargin = dp(14)
                topMargin = dp(14)
            }
        )

        qualityButton = overlayButton("Auto ▾").apply {
            textSize = 15f
            setPadding(dp(14), 0, dp(14), 0)
            contentDescription = "Quality"
            setOnClickListener { showQualityMenu() }
        }

        root.addView(
            qualityButton,
            FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT,
                dp(46),
                Gravity.TOP or Gravity.END
            ).apply {
                rightMargin = dp(14)
                topMargin = dp(14)
            }
        )

        setContentView(root)
        playServer(selectedServerIndex)
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) hideSystemBars()
    }

    private fun playServer(index: Int) {
        val source = sources.getJSONObject(index)
        val url = source.optString("url")
        if (url.isBlank()) return

        selectedServerIndex = index
        forcedQualityLabel = null
        qualityOptions.clear()
        qualityButton.text = "Auto ▾"

        player?.release()
        player = null
        trackSelector = null

        try {
            val headers = mutableMapOf<String, String>()
            val referer = source.optString("referer")
            val origin = source.optString("origin")
            if (referer.isNotBlank()) headers["Referer"] = referer
            if (origin.isNotBlank()) headers["Origin"] = origin

            val httpFactory = DefaultHttpDataSource.Factory()
                .setAllowCrossProtocolRedirects(true)
                .setDefaultRequestProperties(headers)

            val mediaSourceFactory = DefaultMediaSourceFactory(httpFactory)
            val item = MediaItem.Builder().setUri(url)

            when (source.optString("streamType", "auto").lowercase()) {
                "dash", "mpd" -> item.setMimeType(MimeTypes.APPLICATION_MPD)
                "hls", "m3u8" -> item.setMimeType(MimeTypes.APPLICATION_M3U8)
                // FLV / MP4 / direct:
                // Let Media3 progressive extraction detect the format.
            }

            val keyId = source.optString("keyId")
            val keyData = source.optString("keyData")

            if (keyId.isNotBlank() && keyData.isNotBlank()) {
                val clearKeyJson =
                    "{\"keys\":[{\"kty\":\"oct\",\"kid\":\"" +
                        toBase64Url(keyId) +
                        "\",\"k\":\"" +
                        toBase64Url(keyData) +
                        "\"}],\"type\":\"temporary\"}"

                val callback = LocalMediaDrmCallback(
                    clearKeyJson.toByteArray(Charsets.UTF_8)
                )

                val drm = DefaultDrmSessionManager.Builder()
                    .setPlayClearSamplesWithoutKeys(true)
                    .setMultiSession(false)
                    .setUuidAndExoMediaDrmProvider(
                        C.CLEARKEY_UUID,
                        FrameworkMediaDrm.DEFAULT_PROVIDER
                    )
                    .build(callback)

                mediaSourceFactory.setDrmSessionManagerProvider { drm }

                item.setDrmConfiguration(
                    MediaItem.DrmConfiguration.Builder(
                        C.CLEARKEY_UUID
                    ).build()
                )
            }

            val selector = DefaultTrackSelector(this)
            trackSelector = selector

            val exoPlayer = ExoPlayer.Builder(this)
                .setTrackSelector(selector)
                .setMediaSourceFactory(mediaSourceFactory)
                .build()

            exoPlayer.addListener(
                object : Player.Listener {
                    override fun onTracksChanged(tracks: Tracks) {
                        rebuildQualityOptions(tracks)
                    }
                }
            )

            player = exoPlayer
            playerView.player = exoPlayer
            exoPlayer.setMediaItem(item.build())
            exoPlayer.prepare()
            exoPlayer.playWhenReady = true
        } catch (_: Throwable) {
            // Keep this screen open so the user can go back and choose another server.
        }
    }

    private fun rebuildQualityOptions(tracks: Tracks) {
        val bestByHeight = linkedMapOf<Int, QualityOption>()

        for (group in tracks.groups) {
            if (group.type != C.TRACK_TYPE_VIDEO) continue

            for (trackIndex in 0 until group.length) {
                if (!group.isTrackSupported(trackIndex)) continue

                val format = group.getTrackFormat(trackIndex)
                val height = format.height
                if (height <= 0) continue

                val bitrate = format.bitrate
                val option = QualityOption(
                    label = "${height}p",
                    group = group,
                    trackIndex = trackIndex,
                    height = height,
                    bitrate = bitrate
                )

                val existing = bestByHeight[height]
                if (existing == null || bitrate > existing.bitrate) {
                    bestByHeight[height] = option
                }
            }
        }

        qualityOptions = bestByHeight.values
            .sortedByDescending { it.height }
            .toMutableList()

        runOnUiThread {
            qualityButton.visibility =
                if (qualityOptions.size > 1) View.VISIBLE else View.VISIBLE

            qualityButton.text =
                (forcedQualityLabel ?: "Auto") + " ▾"
        }
    }

    private fun showQualityMenu() {
        val selector = trackSelector ?: return
        val popup = PopupMenu(this, qualityButton)

        popup.menu.add(0, QUALITY_AUTO_ID, 0, "Auto").apply {
            isCheckable = true
            isChecked = forcedQualityLabel == null
        }

        qualityOptions.forEachIndexed { index, option ->
            popup.menu.add(
                0,
                QUALITY_BASE_ID + index,
                index + 1,
                option.label
            ).apply {
                isCheckable = true
                isChecked = forcedQualityLabel == option.label
            }
        }

        popup.setOnMenuItemClickListener { menuItem ->
            if (menuItem.itemId == QUALITY_AUTO_ID) {
                selector.parameters = selector
                    .buildUponParameters()
                    .clearOverridesOfType(C.TRACK_TYPE_VIDEO)
                    .build()

                forcedQualityLabel = null
                qualityButton.text = "Auto ▾"
                return@setOnMenuItemClickListener true
            }

            val index = menuItem.itemId - QUALITY_BASE_ID
            val option = qualityOptions.getOrNull(index)
                ?: return@setOnMenuItemClickListener false

            val override = TrackSelectionOverride(
                option.group.mediaTrackGroup,
                option.trackIndex
            )

            selector.parameters = selector
                .buildUponParameters()
                .clearOverridesOfType(C.TRACK_TYPE_VIDEO)
                .setOverrideForType(override)
                .build()

            forcedQualityLabel = option.label
            qualityButton.text = "${option.label} ▾"
            true
        }

        popup.show()
    }

    private fun overlayButton(textValue: String): TextView {
        return TextView(this).apply {
            text = textValue
            setTextColor(Color.WHITE)
            textSize = 28f
            gravity = Gravity.CENTER
            setBackgroundColor(Color.argb(150, 0, 0, 0))
            isClickable = true
            isFocusable = true
        }
    }

    private fun hideSystemBars() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            window.setDecorFitsSystemWindows(false)
            window.insetsController?.let { controller ->
                controller.hide(
                    WindowInsets.Type.statusBars() or
                        WindowInsets.Type.navigationBars()
                )
                controller.systemBarsBehavior =
                    WindowInsetsController
                        .BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
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
    }

    override fun onDestroy() {
        playerView.player = null
        player?.release()
        player = null
        trackSelector = null
        super.onDestroy()
    }

    private fun dp(value: Int): Int {
        return (value * resources.displayMetrics.density).toInt()
    }

    private fun toBase64Url(value: String): String {
        val clean = value.replace(" ", "").trim()

        if (
            clean.matches(Regex("^[0-9a-fA-F]+$")) &&
            clean.length % 2 == 0
        ) {
            val bytes = ByteArray(clean.length / 2)
            for (i in bytes.indices) {
                val p = i * 2
                bytes[i] =
                    clean.substring(p, p + 2).toInt(16).toByte()
            }

            return Base64.encodeToString(
                bytes,
                Base64.URL_SAFE or
                    Base64.NO_WRAP or
                    Base64.NO_PADDING
            )
        }

        return clean
            .replace("+", "-")
            .replace("/", "_")
            .trimEnd('=')
    }

    companion object {
        private const val QUALITY_AUTO_ID = 9000
        private const val QUALITY_BASE_ID = 9100
    }
}
