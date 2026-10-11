package com.example.pactick

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat

/** Keeps a small reminder snapshot; task data remains in the Flutter database. */
object TaskReminderManager {
    const val CHANNEL_ID = "task_reminders"
    const val ACTION_OPEN_TASKS = "com.example.pactick.task_reminders.OPEN_TASKS"

    private const val PREFERENCES = "task_reminders"
    private const val KEY_ENABLED = "enabled"
    private const val KEY_OPEN_TASK_COUNT = "open_task_count"
    private const val KEY_WORKSPACE_ID = "workspace_id"
    private const val KEY_PERMISSION_REQUESTED = "permission_requested"
    private const val NOTIFICATION_ID = 1301
    private const val OPEN_TASKS_REQUEST_CODE = 1302

    fun update(context: Context, enabled: Boolean, openTaskCount: Int, workspaceId: String): Boolean {
        val preferences = preferences(context)
        val workspaceChanged = preferences.getString(KEY_WORKSPACE_ID, null) != workspaceId
        preferences.edit()
            .putBoolean(KEY_ENABLED, enabled)
            .putInt(KEY_OPEN_TASK_COUNT, openTaskCount.coerceAtLeast(0))
            .putString(KEY_WORKSPACE_ID, workspaceId)
            .apply()
        if (workspaceChanged) notificationManager(context).cancel(NOTIFICATION_ID)
        return refresh(context)
    }

    fun hasAutomaticallyRequestedPermission(context: Context): Boolean =
        preferences(context).getBoolean(KEY_PERMISSION_REQUESTED, false)

    fun markPermissionRequested(context: Context) {
        preferences(context).edit().putBoolean(KEY_PERMISSION_REQUESTED, true).apply()
    }

    fun notificationsAllowed(context: Context): Boolean {
        createNotificationChannel(context)
        val manager = notificationManager(context)
        val channel = manager.getNotificationChannel(CHANNEL_ID)
        return manager.areNotificationsEnabled() &&
            (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
                ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) ==
                PackageManager.PERMISSION_GRANTED) &&
            channel != null && channel.importance != NotificationManager.IMPORTANCE_NONE
    }

    fun refresh(context: Context): Boolean {
        val allowed = notificationsAllowed(context)
        if (hasOpenTasks(context) && allowed) {
            showNotification(context, preferences(context).getInt(KEY_OPEN_TASK_COUNT, 0))
        } else {
            notificationManager(context).cancel(NOTIFICATION_ID)
        }
        return allowed
    }

    private fun hasOpenTasks(context: Context): Boolean {
        val preferences = preferences(context)
        return preferences.getBoolean(KEY_ENABLED, false) &&
            preferences.getInt(KEY_OPEN_TASK_COUNT, 0) > 0 &&
            !preferences.getString(KEY_WORKSPACE_ID, null).isNullOrEmpty()
    }

    private fun showNotification(context: Context, count: Int) {
        val openTasks = Intent(context, MainActivity::class.java).apply {
            action = ACTION_OPEN_TASKS
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val openTasksPendingIntent = PendingIntent.getActivity(
            context,
            OPEN_TASKS_REQUEST_CODE,
            openTasks,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_focus_notification)
            .setContentTitle("给自己一点完成任务的时间")
            .setContentText("还有 $count 项待办，先从一件小事开始吧。")
            .setContentIntent(openTasksPendingIntent)
            .setCategory(NotificationCompat.CATEGORY_REMINDER)
            .setVisibility(NotificationCompat.VISIBILITY_PRIVATE)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setOnlyAlertOnce(true)
            .setSilent(true)
            .setOngoing(true)
            .setAutoCancel(false)
            .build()
        notificationManager(context).notify(NOTIFICATION_ID, notification)
    }

    private fun createNotificationChannel(context: Context) {
        val channel = NotificationChannel(CHANNEL_ID, "任务温馨提醒", NotificationManager.IMPORTANCE_LOW).apply {
            description = "有待办时在通知栏显示一条静默提醒，不显示任务标题"
            setSound(null, null)
            enableVibration(false)
            setShowBadge(false)
        }
        notificationManager(context).createNotificationChannel(channel)
    }

    private fun notificationManager(context: Context): NotificationManager =
        context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

    private fun preferences(context: Context) = context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
}
