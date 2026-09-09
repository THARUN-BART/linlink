package com.example.linlink

import android.content.Intent
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.linlink/foreground_service"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "startForegroundService" -> {
                    val deviceName = call.argument<String>("deviceName") ?: "Linux Workstation"
                    val host = call.argument<String>("host") ?: "Local Network"
                    val intent = Intent(this, LinLinkForegroundService::class.java).apply {
                        action = LinLinkForegroundService.ACTION_START
                        putExtra(LinLinkForegroundService.EXTRA_DEVICE_NAME, deviceName)
                        putExtra(LinLinkForegroundService.EXTRA_HOST, host)
                    }
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        startForegroundService(intent)
                    } else {
                        startService(intent)
                    }
                    result.success(true)
                }
                "updateNotification" -> {
                    val title = call.argument<String>("title") ?: "LinLink Active"
                    val text = call.argument<String>("text") ?: "Syncing"
                    val intent = Intent(this, LinLinkForegroundService::class.java).apply {
                        action = LinLinkForegroundService.ACTION_UPDATE
                        putExtra(LinLinkForegroundService.EXTRA_TITLE, title)
                        putExtra(LinLinkForegroundService.EXTRA_TEXT, text)
                    }
                    startService(intent)
                    result.success(true)
                }
                "stopForegroundService" -> {
                    val intent = Intent(this, LinLinkForegroundService::class.java).apply {
                        action = LinLinkForegroundService.ACTION_STOP
                    }
                    startService(intent)
                    result.success(true)
                }
                "isServiceRunning" -> {
                    result.success(LinLinkForegroundService.isRunning)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }
}
