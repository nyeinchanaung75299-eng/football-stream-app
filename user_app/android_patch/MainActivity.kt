package com.example.football_viewer

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "football_stream/native_player"

    companion object {
        private var playerEventChannel: MethodChannel? = null

        fun emitPlayerEvent(
            event: String,
            properties: Map<String, Any?> = emptyMap()
        ) {
            playerEventChannel?.invokeMethod(
                "playerEvent",
                mapOf(
                    "event" to event,
                    "properties" to properties
                )
            )
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val channel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            channelName
        )
        playerEventChannel = channel

        channel.setMethodCallHandler { call, result ->
            if (call.method == "updatePlayerSources") {
                val sessionId = call.argument<String>("sessionId").orEmpty()
                val sourcesJson = call.argument<String>("sourcesJson").orEmpty()
                result.success(NativePlayerActivity.appendSources(sessionId, sourcesJson))
                return@setMethodCallHandler
            }
            if (call.method != "openPlayer") {
                result.notImplemented()
                return@setMethodCallHandler
            }

            val sourcesJson = call.argument<String>("sourcesJson").orEmpty()
            if (sourcesJson.isBlank()) {
                result.error("EMPTY_SOURCES", "No player sources.", null)
                return@setMethodCallHandler
            }

            val sessionId = call.argument<String>("sessionId").orEmpty()
            NativePlayerActivity.prepareOpeningSession(sessionId)
            try {
                startActivity(Intent(this, NativePlayerActivity::class.java).apply {
                    putExtra("sourcesJson", sourcesJson)
                    putExtra(
                        "selectedIndex",
                        call.argument<Int>("selectedIndex") ?: 0
                    )
                    putExtra("title", call.argument<String>("title").orEmpty())
                    putExtra("matchId", call.argument<String>("matchId").orEmpty())
                    putExtra("sessionId", sessionId)
                })
            } catch (_: Exception) {
                NativePlayerActivity.cancelOpeningSession(sessionId)
                result.error("PLAYER_OPEN_FAILED", "Could not open player.", null)
                return@setMethodCallHandler
            }

            result.success(null)
        }
    }
}
