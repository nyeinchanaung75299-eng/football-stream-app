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
            if (call.method != "openPlayer") {
                result.notImplemented()
                return@setMethodCallHandler
            }

            val sourcesJson = call.argument<String>("sourcesJson").orEmpty()
            if (sourcesJson.isBlank()) {
                result.error("EMPTY_SOURCES", "No player sources.", null)
                return@setMethodCallHandler
            }

            startActivity(Intent(this, NativePlayerActivity::class.java).apply {
                putExtra("sourcesJson", sourcesJson)
                putExtra(
                    "selectedIndex",
                    call.argument<Int>("selectedIndex") ?: 0
                )
                putExtra("title", call.argument<String>("title").orEmpty())
            })

            result.success(null)
        }
    }
}
