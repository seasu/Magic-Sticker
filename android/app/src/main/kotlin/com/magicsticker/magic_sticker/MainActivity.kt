package com.magicsticker.magic_sticker

import android.os.Bundle
import androidx.activity.enableEdgeToEdge
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val channel = "com.magicmorning/background_removal"

    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            channel,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "removeBackground" -> {
                    val imageBytes = call.argument<ByteArray>("imageBytes")
                    if (imageBytes == null) {
                        result.error("INVALID_ARGUMENT", "imageBytes is null", null)
                        return@setMethodCallHandler
                    }
                    BackgroundRemover.remove(
                        context = applicationContext,
                        imageBytes = imageBytes,
                        onSuccess = { pngBytes -> result.success(pngBytes) },
                        onError = { e ->
                            result.error("SEGMENTATION_FAILED", e.message, null)
                        },
                    )
                }
                else -> result.notImplemented()
            }
        }
    }
}
