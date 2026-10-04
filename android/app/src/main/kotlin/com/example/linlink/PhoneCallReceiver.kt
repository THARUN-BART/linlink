package com.example.linlink

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.telephony.TelephonyManager

class PhoneCallReceiver : BroadcastReceiver() {
    companion object {
        var onCallStateListener: ((state: String, number: String) -> Unit)? = null
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == TelephonyManager.ACTION_PHONE_STATE_CHANGED) {
            val stateStr = intent.getStringExtra(TelephonyManager.EXTRA_STATE) ?: return
            val number = intent.getStringExtra(TelephonyManager.EXTRA_INCOMING_NUMBER) ?: "Unknown Caller"

            when (stateStr) {
                TelephonyManager.EXTRA_STATE_RINGING -> {
                    onCallStateListener?.invoke("ringing", number)
                    MainActivity.instance?.sendIncomingCallToFlutter("ringing", number)
                }
                TelephonyManager.EXTRA_STATE_OFFHOOK -> {
                    onCallStateListener?.invoke("in_call", number)
                    MainActivity.instance?.sendIncomingCallToFlutter("in_call", number)
                }
                TelephonyManager.EXTRA_STATE_IDLE -> {
                    onCallStateListener?.invoke("idle", number)
                    MainActivity.instance?.sendIncomingCallToFlutter("idle", number)
                }
            }
        }
    }
}
