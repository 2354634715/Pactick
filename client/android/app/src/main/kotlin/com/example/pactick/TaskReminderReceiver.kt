package com.example.pactick

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

class TaskReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        try {
            when (intent.action) {
                Intent.ACTION_BOOT_COMPLETED,
                Intent.ACTION_MY_PACKAGE_REPLACED -> TaskReminderManager.refresh(context)
            }
        } catch (error: Exception) {
            // A system notification failure must not crash the application.
            Log.w("TaskReminderReceiver", "Could not update task reminder", error)
        }
    }
}
