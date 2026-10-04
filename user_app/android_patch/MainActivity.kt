package com.example.football_viewer

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "football_stream/native_player"
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                if (call.method != "openPlayer") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val url = call.argument<String>("url").orEmpty()
                if (url.isBlank()) {
                    result.error("EMPTY_URL", "Stream URL is empty.", null)
                    return@setMethodCallHandler
                }
                startActivity(Intent(this, NativePlayerActivity::class.java).apply {
                    putExtra("url", url)
                    putExtra("streamType", call.argument<String>("streamType").orEmpty())
                    putExtra("referer", call.argument<String>("referer").orEmpty())
                    putExtra("origin", call.argument<String>("origin").orEmpty())
                    putExtra("keyId", call.argument<String>("keyId").orEmpty())
                    putExtra("keyData", call.argument<String>("keyData").orEmpty())
                    putExtra("title", call.argument<String>("title").orEmpty())
                })
                result.success(null)
            }
    }
}
