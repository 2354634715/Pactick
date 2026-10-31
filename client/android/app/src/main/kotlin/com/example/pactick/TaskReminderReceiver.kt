package com.example.pactick

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

class TaskReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        try {
            when (intent.action) {
                Intent.ACTION_LOCALE_CHANGED -> {
                    TaskReminderManager.refreshLocalization(context)
                    FocusTimerService.refreshLanguage()
                }
                Intent.ACTION_BOOT_COMPLETED,
                Intent.ACTION_MY_PACKAGE_REPLACED,
                Intent.ACTION_TIME_CHANGED,
                Intent.ACTION_TIMEZONE_CHANGED -> {
                    TaskReminderManager.refresh(context)
                    TaskReminderManager.refreshSchedule(context)
                }
                TaskReminderManager.ACTION_SCHEDULED_REMINDER ->
                    TaskReminderManager.refreshSchedule(context)
            }
        } catch (error: Exception) {
            // A system notification failure must not crash the application.
            Log.w("TaskReminderReceiver", "Could not update task reminder", error)
        }
    }
}
