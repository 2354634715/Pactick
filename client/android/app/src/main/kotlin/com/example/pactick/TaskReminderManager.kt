package com.example.pactick

import android.Manifest
import android.app.NotificationChannel
import android.app.AlarmManager
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import org.json.JSONArray
import org.json.JSONException
import org.json.JSONObject

/** Keeps a small reminder snapshot; task data remains in the Flutter database. */
object TaskReminderManager {
    const val CHANNEL_ID = "task_reminders"
    const val ACTION_OPEN_TASKS = "com.example.pactick.task_reminders.OPEN_TASKS"
    const val SCHEDULED_CHANNEL_ID = "scheduled_task_reminders"
    const val ACTION_SCHEDULED_REMINDER = "com.example.pactick.task_reminders.SCHEDULED"

    private const val PREFERENCES = "task_reminders"
    private const val KEY_ENABLED = "enabled"
    private const val KEY_OPEN_TASK_COUNT = "open_task_count"
    private const val KEY_WORKSPACE_ID = "workspace_id"
    private const val KEY_PERMISSION_REQUESTED = "permission_requested"
    private const val NOTIFICATION_ID = 1301
    private const val OPEN_TASKS_REQUEST_CODE = 1302
    private const val SCHEDULED_NOTIFICATION_ID = 1303
    private const val SCHEDULED_ALARM_REQUEST_CODE = 1304
    private const val KEY_SCHEDULE_ENABLED = "schedule_enabled"
    private const val KEY_SCHEDULE_WORKSPACE = "schedule_workspace"
    private const val KEY_SCHEDULE_EVENTS = "schedule_events"
    private const val KEY_DELIVERED = "schedule_delivered"

    private data class ScheduledReminder(val id: String, val atMillis: Long, val kind: String) {
        val signature: String get() = "$id@$atMillis"
        fun toJson() = JSONObject().put("id", id).put("atMillis", atMillis).put("kind", kind)
    }

    /** Only opaque IDs, timestamps, and event types cross into native storage. */
    @Synchronized
    fun updateSchedule(
        context: Context,
        enabled: Boolean,
        workspaceId: String,
        reminders: List<Map<String, Any?>>,
    ): Boolean {
        val preferences = preferences(context)
        val sameWorkspace = preferences.getString(KEY_SCHEDULE_WORKSPACE, null) == workspaceId
        val previous = if (sameWorkspace) readScheduledReminders(context) else emptyList()
        val previousSignatures = previous.map { it.signature }.toSet()
        val events = if (enabled && workspaceId.isNotEmpty()) reminders.mapNotNull { item ->
            val id = item["id"] as? String ?: return@mapNotNull null
            val timestamp = (item["atMillis"] as? Number)?.toLong() ?: return@mapNotNull null
            val kind = item["kind"] as? String ?: return@mapNotNull null
            if (id.isBlank() || timestamp <= 0 || (kind != "deadline" && kind != "plan")) null
            else ScheduledReminder(id, timestamp, kind)
        }.distinctBy { it.signature }.sortedBy { it.atMillis } else emptyList()
        val signatures = events.map { it.signature }.toSet()
        val previousDelivered = if (sameWorkspace)
            preferences.getStringSet(KEY_DELIVERED, emptySet()).orEmpty().toSet() else emptySet()
        val delivered = previousDelivered.intersect(signatures).toMutableSet()
        val now = System.currentTimeMillis()
        // Opening an old task or enabling reminders does not alert for its past deadlines.
        events.filter { it.atMillis <= now && it.signature !in previousSignatures }
            .forEach { delivered.add(it.signature) }
        val json = JSONArray()
        events.forEach { json.put(it.toJson()) }
        check(preferences.edit()
            .putBoolean(KEY_SCHEDULE_ENABLED, enabled)
            .putString(KEY_SCHEDULE_WORKSPACE, workspaceId)
            .putString(KEY_SCHEDULE_EVENTS, json.toString())
            .putStringSet(KEY_DELIVERED, delivered)
            .commit()) { "Could not persist task reminder schedule" }
        if (!sameWorkspace || !enabled || !delivered.containsAll(previousDelivered)) {
            notificationManager(context).cancel(SCHEDULED_NOTIFICATION_ID)
        }
        return refreshSchedule(context)
    }

    @Synchronized
    fun refreshSchedule(context: Context): Boolean {
        val preferences = preferences(context)
        val allowed = scheduledNotificationsAllowed(context)
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val pending = scheduledAlarm(context)
        alarmManager.cancel(pending)
        if (!preferences.getBoolean(KEY_SCHEDULE_ENABLED, false) ||
            preferences.getString(KEY_SCHEDULE_WORKSPACE, null).isNullOrEmpty()
        ) {
            notificationManager(context).cancel(SCHEDULED_NOTIFICATION_ID)
            return allowed
        }
        val events = readScheduledReminders(context)
        val delivered = preferences.getStringSet(KEY_DELIVERED, emptySet()).orEmpty().toMutableSet()
        val now = System.currentTimeMillis()
        val due = events.filter { it.atMillis <= now && it.signature !in delivered }
        if (due.isNotEmpty()) {
            delivered.addAll(due.map { it.signature })
            check(preferences.edit().putStringSet(KEY_DELIVERED, delivered).commit()) {
                "Could not persist delivered task reminders"
            }
            if (allowed) showScheduledNotification(context, due)
        }
        val next = events.firstOrNull { it.atMillis > now && it.signature !in delivered }
        if (next != null) {
            // Inexact by design; no SCHEDULE_EXACT_ALARM permission or background polling.
            alarmManager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, next.atMillis, pending)
        }
        return allowed
    }

    fun scheduledNotificationsAllowed(context: Context): Boolean {
        createScheduledNotificationChannel(context)
        val manager = notificationManager(context)
        val channel = manager.getNotificationChannel(SCHEDULED_CHANNEL_ID)
        return appNotificationsAllowed(context) &&
            channel != null && channel.importance != NotificationManager.IMPORTANCE_NONE
    }

    private fun readScheduledReminders(context: Context): List<ScheduledReminder> {
        return try {
            val json = JSONArray(preferences(context).getString(KEY_SCHEDULE_EVENTS, "[]"))
            (0 until json.length()).mapNotNull { index ->
                val item = json.optJSONObject(index) ?: return@mapNotNull null
                val id = item.optString("id")
                val atMillis = item.optLong("atMillis")
                val kind = item.optString("kind")
                if (id.isBlank() || atMillis <= 0 || (kind != "deadline" && kind != "plan")) null
                else ScheduledReminder(id, atMillis, kind)
            }.sortedBy { it.atMillis }
        } catch (_: JSONException) {
            // The next Flutter update can reconstruct this non-authoritative snapshot.
            emptyList()
        }
    }

    private fun scheduledAlarm(context: Context): PendingIntent = PendingIntent.getBroadcast(
        context,
        SCHEDULED_ALARM_REQUEST_CODE,
        Intent(context, TaskReminderReceiver::class.java).setAction(ACTION_SCHEDULED_REMINDER),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )

    private fun showScheduledNotification(context: Context, due: List<ScheduledReminder>) {
        val title = when {
            due.all { it.kind == "deadline" } -> PactickStrings.text(context, R.string.task_deadline_title)
            due.all { it.kind == "plan" } -> PactickStrings.text(context, R.string.task_plan_title)
            else -> PactickStrings.text(context, R.string.task_schedule_title)
        }
        val openTasks = Intent(context, MainActivity::class.java).apply {
            action = ACTION_OPEN_TASKS
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val openTasksPendingIntent = PendingIntent.getActivity(
            context, OPEN_TASKS_REQUEST_CODE, openTasks,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val notification = NotificationCompat.Builder(context, SCHEDULED_CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_focus_notification)
            .setContentTitle(title)
            .setContentText(PactickStrings.text(context, R.string.task_schedule_text, due.size))
            .addExtras(Bundle().apply {
                putInt("pactick_reminder_count", due.size)
                putString("pactick_reminder_kind", when {
                    due.all { it.kind == "deadline" } -> "deadline"
                    due.all { it.kind == "plan" } -> "plan"
                    else -> "mixed"
                })
            })
            .setContentIntent(openTasksPendingIntent)
            .setCategory(NotificationCompat.CATEGORY_REMINDER)
            .setVisibility(NotificationCompat.VISIBILITY_PRIVATE)
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .setAutoCancel(true)
            .build()
        notificationManager(context).notify(SCHEDULED_NOTIFICATION_ID, notification)
    }

    private fun createScheduledNotificationChannel(context: Context) {
        notificationManager(context).createNotificationChannel(
            NotificationChannel(SCHEDULED_CHANNEL_ID, PactickStrings.text(context, R.string.task_schedule_channel), NotificationManager.IMPORTANCE_DEFAULT).apply {
                description = PactickStrings.text(context, R.string.task_schedule_channel_description)
                setShowBadge(false)
            },
        )
    }

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
        return appNotificationsAllowed(context) &&
            channel != null && channel.importance != NotificationManager.IMPORTANCE_NONE
    }

    private fun appNotificationsAllowed(context: Context): Boolean =
        notificationManager(context).areNotificationsEnabled() &&
            (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
                ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) ==
                PackageManager.PERMISSION_GRANTED)

    fun refresh(context: Context): Boolean {
        val allowed = notificationsAllowed(context)
        if (hasOpenTasks(context) && allowed) {
            showNotification(context, preferences(context).getInt(KEY_OPEN_TASK_COUNT, 0))
        } else {
            notificationManager(context).cancel(NOTIFICATION_ID)
        }
        return allowed
    }

    fun refreshLocalization(context: Context) {
        refresh(context)
        createScheduledNotificationChannel(context)
        val manager = notificationManager(context)
        val current = manager.activeNotifications
            .firstOrNull { it.id == SCHEDULED_NOTIFICATION_ID }?.notification ?: return
        val count = current.extras.getInt("pactick_reminder_count", 0)
        if (count <= 0) return
        val titleResource = when (current.extras.getString("pactick_reminder_kind")) {
            "deadline" -> R.string.task_deadline_title
            "plan" -> R.string.task_plan_title
            else -> R.string.task_schedule_title
        }
        manager.notify(SCHEDULED_NOTIFICATION_ID, NotificationCompat.Builder(context, current)
            .setContentTitle(PactickStrings.text(context, titleResource))
            .setContentText(PactickStrings.text(context, R.string.task_schedule_text, count))
            .setOnlyAlertOnce(true).setSilent(true).build())
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
            .setContentTitle(PactickStrings.text(context, R.string.task_reminder_title))
            .setContentText(PactickStrings.text(context, R.string.task_reminder_text, count))
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
        val channel = NotificationChannel(CHANNEL_ID, PactickStrings.text(context, R.string.task_reminder_channel), NotificationManager.IMPORTANCE_LOW).apply {
            description = PactickStrings.text(context, R.string.task_reminder_channel_description)
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
