package com.example.pactick

import android.content.Context
import android.media.AudioAttributes
import android.os.Build
import android.os.VibrationAttributes
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager

/** Local preference shared by the activity and the focus foreground service. */
object FocusFeedback {
    private const val PREFERENCES = "focus_feedback"

    fun configure(context: Context, enabled: Boolean, notificationMode: String) {
        context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE).edit()
            .putBoolean("enabled", enabled)
            .putString("mode", notificationMode)
            .apply()
    }

    fun play(context: Context, event: String) {
        val preferences = context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
        if (!preferences.getBoolean("enabled", true) ||
            preferences.getString("mode", "vibrate") !in setOf("vibrate", "sound_and_vibrate")) return
        runCatching {
            val vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                context.getSystemService(VibratorManager::class.java).defaultVibrator
            } else {
                @Suppress("DEPRECATION")
                context.getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
            }
            if (!vibrator.hasVibrator()) return
            val pattern = when (event) {
                "target" -> longArrayOf(0, 160, 100, 160, 100, 240)
                "completed" -> longArrayOf(0, 70, 70, 100)
                "guard" -> longArrayOf(0, 70, 70, 70)
                "started", "resumed" -> longArrayOf(0, 45)
                "paused", "abandoned" -> longArrayOf(0, 70)
                else -> return
            }
            val effect = VibrationEffect.createWaveform(pattern, -1)
            val isReminder = event == "target" || event == "guard"
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                vibrator.vibrate(effect, VibrationAttributes.Builder().setUsage(
                    if (isReminder) VibrationAttributes.USAGE_NOTIFICATION
                    else VibrationAttributes.USAGE_TOUCH,
                ).build())
            } else {
                @Suppress("DEPRECATION")
                vibrator.vibrate(effect, AudioAttributes.Builder().setUsage(
                    if (isReminder) AudioAttributes.USAGE_NOTIFICATION_EVENT
                    else AudioAttributes.USAGE_ASSISTANCE_SONIFICATION,
                ).build())
            }
        }
        // Missing hardware, denied permission or system suppression never changes a session.
    }
}
