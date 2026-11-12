package com.safeher.safeher

import android.app.Activity
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.media.AudioAttributes
import android.media.Ringtone
import android.media.RingtoneManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.telephony.SmsManager
import android.telephony.SubscriptionManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.atomic.AtomicInteger

/**
 * Sends SOS texts with SmsManager and reports what the radio said about each one.
 *
 * "sent" only means the SMS left this phone. Android's delivery reports are unreliable
 * across Bangladeshi operators, so the app never claims "delivered".
 *
 * Dual-SIM phones often have one SIM without signal. If the default SMS SIM fails,
 * the other SIMs are tried in turn (listing them needs READ_PHONE_STATE).
 */
class MainActivity : FlutterActivity() {
    private val requestIds = AtomicInteger(0)
    private val mainHandler = Handler(Looper.getMainLooper())

    private data class Sim(val subId: Int, val label: String)

    // Fake Call: the phone's own ringtone and vibration, so it sounds like a real call.
    private var ringtone: Ringtone? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "safeher/sms").setMethodCallHandler { call, result ->
            when (call.method) {
                "send" -> {
                    val phone = call.argument<String>("phone")
                    val message = call.argument<String>("message")
                    if (phone.isNullOrBlank() || message.isNullOrBlank()) {
                        result.error("bad_args", "phone and message are required", null)
                    } else {
                        sendWithFailover(phone, message, candidateSims(), null) { outcome -> result.success(outcome) }
                    }
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "safeher/ringer").setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> { startRinging(); result.success(null) }
                "stop" -> { stopRinging(); result.success(null) }
                else -> result.notImplemented()
            }
        }
    }

    private fun vibrator(): Vibrator? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
        getSystemService(VibratorManager::class.java)?.defaultVibrator
    } else {
        @Suppress("DEPRECATION")
        getSystemService(Vibrator::class.java)
    }

    /** Follows the phone's ring mode: silent phones stay silent, like a real call. */
    private fun startRinging() {
        stopRinging()
        try {
            val uri = RingtoneManager.getActualDefaultRingtoneUri(this, RingtoneManager.TYPE_RINGTONE)
                ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)
            ringtone = RingtoneManager.getRingtone(this, uri)?.apply {
                audioAttributes = AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build()
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) isLooping = true
                play()
            }
        } catch (_: Exception) {
            ringtone = null
        }
        // Ring pattern: 1 s on, 1 s off, repeating.
        val pattern = longArrayOf(0, 1000, 1000)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            vibrator()?.vibrate(VibrationEffect.createWaveform(pattern, 0))
        } else {
            @Suppress("DEPRECATION")
            vibrator()?.vibrate(pattern, 0)
        }
    }

    private fun stopRinging() {
        ringtone?.stop()
        ringtone = null
        vibrator()?.cancel()
    }

    override fun onDestroy() {
        stopRinging()
        super.onDestroy()
    }

    /** Default SMS SIM first, then any other active SIM. */
    private fun candidateSims(): List<Sim> {
        val defaultId = SmsManager.getDefaultSmsSubscriptionId()
        val active = try {
            getSystemService(SubscriptionManager::class.java)?.activeSubscriptionInfoList.orEmpty()
                .map { Sim(it.subscriptionId, it.carrierName?.toString().orEmpty()) }
        } catch (e: SecurityException) {
            emptyList() // No READ_PHONE_STATE: only the default SIM can be used.
        }
        val sims = mutableListOf<Sim>()
        val defaultSim = active.firstOrNull { it.subId == defaultId }
        if (defaultSim != null) {
            sims.add(defaultSim)
        } else if (defaultId != SubscriptionManager.INVALID_SUBSCRIPTION_ID) {
            sims.add(Sim(defaultId, ""))
        }
        sims.addAll(active.filter { it.subId != defaultId })
        if (sims.isEmpty()) sims.add(Sim(SubscriptionManager.INVALID_SUBSCRIPTION_ID, ""))
        return sims
    }

    /**
     * Results sent back to Dart: "sent|<carrier>", "waiting|<carrier>" or "failed|<reason>".
     * "waiting" is not retried on another SIM, because the first may still send it.
     */
    private fun sendWithFailover(phone: String, message: String, sims: List<Sim>, lastFailure: String?, done: (String) -> Unit) {
        if (sims.isEmpty()) {
            done("failed|${lastFailure ?: "no_sim"}")
            return
        }
        val sim = sims.first()
        sendOnce(sim, phone, message) { outcome, reason ->
            when (outcome) {
                "sent", "waiting" -> done("$outcome|${sim.label}")
                else -> sendWithFailover(phone, message, sims.drop(1), reason, done)
            }
        }
    }

    private fun smsManagerFor(subId: Int): SmsManager? = try {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val base = getSystemService(SmsManager::class.java)
            if (subId == SubscriptionManager.INVALID_SUBSCRIPTION_ID) base else base?.createForSubscriptionId(subId)
        } else {
            @Suppress("DEPRECATION")
            if (subId == SubscriptionManager.INVALID_SUBSCRIPTION_ID) SmsManager.getDefault()
            else SmsManager.getSmsManagerForSubscriptionId(subId)
        }
    } catch (e: Exception) {
        null
    }

    private fun sendOnce(sim: Sim, phone: String, message: String, done: (String, String?) -> Unit) {
        val smsManager = smsManagerFor(sim.subId)
        if (smsManager == null) {
            done("failed", "no_sms")
            return
        }

        val parts = smsManager.divideMessage(message)
        val action = "com.safeher.SMS_SENT_${requestIds.incrementAndGet()}"
        var remaining = parts.size
        var failure: String? = null
        var finished = false

        lateinit var receiver: BroadcastReceiver
        fun finish(outcome: String, reason: String?) {
            if (finished) return
            finished = true
            try {
                unregisterReceiver(receiver)
            } catch (_: IllegalArgumentException) {
            }
            done(outcome, reason)
        }

        receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) {
                if (resultCode != Activity.RESULT_OK && failure == null) failure = reasonFor(resultCode)
                remaining -= 1
                if (remaining <= 0) {
                    val f = failure
                    if (f == null) finish("sent", null) else finish("failed", f)
                }
            }
        }
        val filter = IntentFilter(action)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(receiver, filter)
        }

        val sentIntents = ArrayList<PendingIntent>()
        for (i in parts.indices) {
            val intent = Intent(action).setPackage(packageName)
            sentIntents.add(PendingIntent.getBroadcast(this, i, intent, PendingIntent.FLAG_IMMUTABLE))
        }

        try {
            smsManager.sendMultipartTextMessage(phone, null, parts, sentIntents, null)
        } catch (e: Exception) {
            finish("failed", "error")
            return
        }
        // No answer from the radio in time: report "waiting" rather than guessing.
        mainHandler.postDelayed({ finish("waiting", null) }, 45_000)
    }

    private fun reasonFor(code: Int): String = when (code) {
        SmsManager.RESULT_ERROR_NO_SERVICE, SmsManager.RESULT_ERROR_RADIO_OFF -> "no_service"
        SmsManager.RESULT_ERROR_LIMIT_EXCEEDED -> "limit"
        else -> "error"
    }
}
