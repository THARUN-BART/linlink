package com.example.linlink

import android.content.Intent
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        var instance: MainActivity? = null
    }

    private val CHANNEL = "com.example.linlink/foreground_service"
    private var methodChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        instance = this

        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        methodChannel = channel

        channel.setMethodCallHandler { call, result ->
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
                "dialPhoneNumber" -> {
                    val number = call.argument<String>("phoneNumber") ?: ""
                    try {
                        val cleanNumber = number.replace(" ", "").replace("-", "")
                        val uri = android.net.Uri.parse("tel:$cleanNumber")
                        if (checkSelfPermission(android.Manifest.permission.CALL_PHONE) == android.content.pm.PackageManager.PERMISSION_GRANTED) {
                            val intent = Intent(Intent.ACTION_CALL, uri).apply {
                                flags = Intent.FLAG_ACTIVITY_NEW_TASK
                            }
                            startActivity(intent)
                            result.success(true)
                        } else {
                            val dialIntent = Intent(Intent.ACTION_DIAL, uri).apply {
                                flags = Intent.FLAG_ACTIVITY_NEW_TASK
                            }
                            startActivity(dialIntent)
                            result.success(true)
                        }
                    } catch (e: Exception) {
                        result.error("DIAL_ERROR", e.message, null)
                    }
                }
                "answerPhoneCall" -> {
                    try {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            val tm = getSystemService(android.telecom.TelecomManager::class.java)
                            if (checkSelfPermission(android.Manifest.permission.ANSWER_PHONE_CALLS) == android.content.pm.PackageManager.PERMISSION_GRANTED) {
                                tm.acceptRingingCall()
                                result.success(true)
                                return@setMethodCallHandler
                            }
                        }
                        // Fallback: Turn on speakerphone
                        val audioManager = getSystemService(android.media.AudioManager::class.java)
                        audioManager.isSpeakerphoneOn = true
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("ANSWER_ERROR", e.message, null)
                    }
                }
                "rejectPhoneCall" -> {
                    try {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                            val tm = getSystemService(android.telecom.TelecomManager::class.java)
                            if (checkSelfPermission(android.Manifest.permission.ANSWER_PHONE_CALLS) == android.content.pm.PackageManager.PERMISSION_GRANTED) {
                                tm.endCall()
                                result.success(true)
                                return@setMethodCallHandler
                            }
                        }
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("REJECT_ERROR", e.message, null)
                    }
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    fun sendIncomingCallToFlutter(state: String, number: String) {
        runOnUiThread {
            methodChannel?.invokeMethod("onPhoneCallStateChanged", mapOf(
                "state" to state,
                "number" to number
            ))
        }
    }

    override fun onDestroy() {
        if (instance == this) {
            instance = null
        }
        super.onDestroy()
    }
}
