package com.example.pactick

import android.app.KeyguardManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.PixelFormat
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.provider.Settings
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import androidx.core.content.ContextCompat
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledFuture
import java.util.concurrent.TimeUnit

class FocusTimerService : Service() {
    private val handler = Handler(Looper.getMainLooper())
    private val monitorExecutor = Executors.newSingleThreadScheduledExecutor()
    private var monitorFuture: ScheduledFuture<*>? = null

    @Volatile private var title: String = ""
    @Volatile private var mode: String = "normal"
    @Volatile private var endsAtEpochMillis: Long = 0
    @Volatile private var pausedRemainingMillis: Long = 0
    @Volatile private var paused = false
    @Volatile private var allowedPackageNames: Set<String> = emptySet()
    @Volatile private var taskTypeName: String = "收集箱"
    @Volatile private var maxAppExits: Int? = null
    @Volatile private var appExitCount = 0
    @Volatile private var interruptionCount = 0
    @Volatile private var sessionId: String? = null
    @Volatile private var guardMonitorGeneration = 0L
    @Volatile private var lastForegroundPackage: String? = null

    private var overlayView: View? = null
    private var dismissingOverlayView: View? = null
    private var overlayMessage: TextView? = null
    private var lastNotifiedPackage: String? = null

    private val targetReached = Runnable {
        val notification = baseNotification()
            .setContentTitle("目标时间已到")
            .setContentText(title)
            .setOngoing(true)
            .build()
        notificationManager.notify(NOTIFICATION_ID, notification)
    }

    override fun onCreate() {
        super.onCreate()
        createNotificationChannels()
        restoreState()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> {
                val requestedSessionId = intent.getStringExtra(EXTRA_SESSION_ID)
                val sameSession = requestedSessionId != null && requestedSessionId == sessionId
                handler.removeCallbacks(targetReached)
                stopGuardMonitoring()
                removeGuardReminderImmediately()
                title = intent.getStringExtra(EXTRA_TITLE) ?: getString(R.string.app_name)
                mode = intent.getStringExtra(EXTRA_MODE) ?: "normal"
                endsAtEpochMillis = intent.getLongExtra(
                    EXTRA_ENDS_AT,
                    System.currentTimeMillis(),
                )
                allowedPackageNames = intent
                    .getStringArrayListExtra(EXTRA_ALLOWED_PACKAGES)
                    ?.toSet()
                    .orEmpty()
                taskTypeName = intent.getStringExtra(EXTRA_TASK_TYPE_NAME) ?: "收集箱"
                maxAppExits = if (intent.hasExtra(EXTRA_MAX_APP_EXITS)) {
                    intent.getIntExtra(EXTRA_MAX_APP_EXITS, 0)
                } else {
                    null
                }
                paused = intent.getBooleanExtra(EXTRA_PAUSED, false)
                pausedRemainingMillis = if (paused) {
                    (endsAtEpochMillis - System.currentTimeMillis()).coerceAtLeast(0)
                } else 0
                appExitCount = maxOf(
                    if (sameSession) appExitCount else 0,
                    intent.getIntExtra(EXTRA_APP_EXIT_COUNT, 0),
                )
                interruptionCount = maxOf(
                    if (sameSession) interruptionCount else 0,
                    intent.getIntExtra(EXTRA_INTERRUPTION_COUNT, 0),
                )
                sessionId = requestedSessionId
                lastForegroundPackage = packageName
                persistState(active = true)
                startAsForeground(if (paused) buildPausedNotification() else buildRunningNotification())
                if (!paused) {
                    scheduleTargetReached()
                    startGuardMonitoring()
                }
            }

            ACTION_PAUSE -> pauseTimer()
            ACTION_RESUME -> {
                endsAtEpochMillis = intent.getLongExtra(
                    EXTRA_ENDS_AT,
                    System.currentTimeMillis() + pausedRemainingMillis,
                )
                paused = false
                pausedRemainingMillis = 0
                lastForegroundPackage = packageName
                persistState(active = true)
                notificationManager.notify(NOTIFICATION_ID, buildRunningNotification())
                scheduleTargetReached()
                startGuardMonitoring()
            }

            ACTION_STOP -> stopTimer()
            null -> {
                if (preferences.getBoolean(KEY_ACTIVE, false)) {
                    startAsForeground(
                        if (paused) buildPausedNotification() else buildRunningNotification(),
                    )
                    if (!paused) {
                        scheduleTargetReached()
                        startGuardMonitoring()
                    }
                } else {
                    stopSelf()
                }
            }
        }
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        handler.removeCallbacks(targetReached)
        stopGuardMonitoring()
        removeGuardReminderImmediately()
        monitorExecutor.shutdownNow()
        super.onDestroy()
    }

    private fun pauseTimer() {
        pausedRemainingMillis = (endsAtEpochMillis - System.currentTimeMillis()).coerceAtLeast(0)
        paused = true
        handler.removeCallbacks(targetReached)
        stopGuardMonitoring()
        hideGuardReminder()
        persistState(active = true)
        notificationManager.notify(NOTIFICATION_ID, buildPausedNotification())
    }

    private fun stopTimer() {
        handler.removeCallbacks(targetReached)
        stopGuardMonitoring()
        removeGuardReminderImmediately()
        persistState(active = false)
        ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    private fun startAsForeground(notification: Notification) {
        val foregroundType = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE
        } else {
            0
        }
        ServiceCompat.startForeground(
            this,
            NOTIFICATION_ID,
            notification,
            foregroundType,
        )
    }

    private fun buildRunningNotification(): Notification {
        return baseNotification()
            .setContentTitle(title)
            .setContentText(if (mode == "guard") "守护模式计时中" else "专注计时中")
            .setWhen(endsAtEpochMillis)
            .setUsesChronometer(true)
            .setChronometerCountDown(true)
            .setOngoing(true)
            .build()
    }

    private fun buildPausedNotification(): Notification {
        val minutes = TimeUnit.MILLISECONDS.toMinutes(pausedRemainingMillis)
        val seconds = TimeUnit.MILLISECONDS.toSeconds(pausedRemainingMillis) % 60
        return baseNotification()
            .setContentTitle("专注已暂停")
            .setContentText("$title · 剩余 %02d:%02d".format(minutes, seconds))
            .setOngoing(true)
            .build()
    }

    private fun baseNotification(): NotificationCompat.Builder {
        return NotificationCompat.Builder(this, TIMER_CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_focus_notification)
            .setContentIntent(openAppPendingIntent())
            .setCategory(NotificationCompat.CATEGORY_STOPWATCH)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setOnlyAlertOnce(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
    }

    private fun startGuardMonitoring() {
        stopGuardMonitoring()
        if (mode != "guard" || paused) return
        val generation = guardMonitorGeneration
        monitorFuture = monitorExecutor.scheduleWithFixedDelay(
            { inspectForegroundApplication(generation) },
            0,
            MONITOR_INTERVAL_MILLIS,
            TimeUnit.MILLISECONDS,
        )
    }

    private fun stopGuardMonitoring() {
        guardMonitorGeneration += 1
        monitorFuture?.cancel(true)
        monitorFuture = null
    }

    private fun inspectForegroundApplication(generation: Long) {
        if (generation != guardMonitorGeneration || mode != "guard" || paused) return
        if (!isDeviceInteractive()) {
            handler.post {
                if (generation == guardMonitorGeneration) hideGuardReminder()
            }
            return
        }
        val foregroundPackage = latestForegroundPackage() ?: return
        val appLabel = applicationLabel(foregroundPackage)
        // State transitions and counters run on the service's main thread.
        // Results from a cancelled monitor cannot modify a subsequent session.
        handler.post {
            if (generation != guardMonitorGeneration || mode != "guard" || paused) return@post
            val previousPackage = lastForegroundPackage
            lastForegroundPackage = foregroundPackage
            if (isAllowed(foregroundPackage)) {
                hideGuardReminder()
                return@post
            }
            if (previousPackage == null || isAllowed(previousPackage)) {
                appExitCount += 1
                if (maxAppExits?.let { appExitCount > it } == true) {
                    interruptionCount += 1
                }
                persistGuardStats()
            }
            showGuardReminder(foregroundPackage, appLabel)
        }
    }

    private fun latestForegroundPackage(): String? {
        val now = System.currentTimeMillis()
        val events = usageStatsManager.queryEvents(now - EVENT_LOOKBACK_MILLIS, now)
        val event = UsageEvents.Event()
        var latestPackage: String? = null
        var latestTimestamp = Long.MIN_VALUE
        while (events.hasNextEvent()) {
            events.getNextEvent(event)
            val movedToForeground = event.eventType == UsageEvents.Event.MOVE_TO_FOREGROUND ||
                event.eventType == UsageEvents.Event.ACTIVITY_RESUMED
            if (movedToForeground && event.timeStamp >= latestTimestamp) {
                latestTimestamp = event.timeStamp
                latestPackage = event.packageName
            }
        }
        return latestPackage ?: lastForegroundPackage
    }

    private fun isAllowed(candidate: String): Boolean {
        return candidate == packageName || candidate in allowedPackageNames
    }

    private fun isDeviceInteractive(): Boolean {
        val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
        val keyguardManager = getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
        return powerManager.isInteractive && !keyguardManager.isKeyguardLocked
    }

    private fun applicationLabel(candidate: String): String {
        return runCatching {
            val application = packageManager.getApplicationInfo(candidate, 0)
            packageManager.getApplicationLabel(application).toString()
        }.getOrDefault(candidate)
    }

    private fun showGuardReminder(foregroundPackage: String, appLabel: String) {
        val message = "$appLabel 不在「$taskTypeName」白名单内"
        if (!Settings.canDrawOverlays(this)) {
            showGuardNotification(foregroundPackage, message)
            return
        }
        notificationManager.cancel(GUARD_NOTIFICATION_ID)
        lastNotifiedPackage = null
        overlayMessage?.text = message
        if (overlayView != null) return

        val root = FrameLayout(this).apply {
            setPadding(dp(12), dp(8), dp(12), 0)
        }
        val card = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(16), dp(12), dp(12), dp(12))
            background = roundedBackground(
                color(R.color.focus_guard_surface),
                dp(22).toFloat(),
            )
            elevation = dp(8).toFloat()
            contentDescription = "返回专注页。$message"
            isClickable = true
            isFocusable = true
            setOnClickListener { returnToFocus() }
        }
        val icon = ImageView(this).apply {
            setImageResource(R.drawable.ic_focus_notification)
            setColorFilter(color(R.color.focus_guard_on_surface))
            contentDescription = null
        }
        card.addView(icon, LinearLayout.LayoutParams(dp(28), dp(28)))

        val copy = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(12), 0, dp(8), 0)
        }
        copy.addView(TextView(this).apply {
            text = "返回专注"
            setTextColor(color(R.color.focus_guard_on_surface))
            textSize = 16f
            setTypeface(typeface, Typeface.BOLD)
            maxLines = 1
        })
        val messageView = TextView(this).apply {
            text = message
            setTextColor(color(R.color.focus_guard_on_surface_variant))
            textSize = 13f
            maxLines = 2
        }
        copy.addView(messageView)
        card.addView(
            copy,
            LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f),
        )

        val action = TextView(this).apply {
            text = "返回"
            gravity = Gravity.CENTER
            setTextColor(color(R.color.focus_guard_on_action))
            textSize = 14f
            setTypeface(typeface, Typeface.BOLD)
            minWidth = dp(72)
            minHeight = dp(48)
            setPadding(dp(16), 0, dp(16), 0)
            background = roundedBackground(
                color(R.color.focus_guard_action),
                dp(24).toFloat(),
            )
            contentDescription = "返回专注页"
            setOnClickListener { returnToFocus() }
        }
        card.addView(action)
        root.addView(
            card,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.WRAP_CONTENT,
            ),
        )

        val layoutParams = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL,
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.TOP or Gravity.CENTER_HORIZONTAL
            y = statusBarHeight()
        }
        overlayView = root
        overlayMessage = messageView
        root.alpha = 0f
        root.translationY = -dp(20).toFloat()
        runCatching { windowManager.addView(root, layoutParams) }
            .onSuccess {
                root.animate()
                    .alpha(1f)
                    .translationY(0f)
                    .setDuration(220)
                    .start()
            }
            .onFailure {
                overlayView = null
                overlayMessage = null
                showGuardNotification(foregroundPackage, message)
            }
    }

    private fun hideGuardReminder() {
        notificationManager.cancel(GUARD_NOTIFICATION_ID)
        lastNotifiedPackage = null
        val view = overlayView ?: return
        overlayView = null
        overlayMessage = null
        dismissingOverlayView = view
        view.animate()
            .alpha(0f)
            .translationY(-dp(16).toFloat())
            .setDuration(160)
            .withEndAction {
                runCatching { windowManager.removeView(view) }
                if (dismissingOverlayView === view) dismissingOverlayView = null
            }
            .start()
    }

    private fun removeGuardReminderImmediately() {
        notificationManager.cancel(GUARD_NOTIFICATION_ID)
        lastNotifiedPackage = null
        val views = listOfNotNull(overlayView, dismissingOverlayView).distinct()
        overlayView = null
        dismissingOverlayView = null
        overlayMessage = null
        for (view in views) {
            view.animate().cancel()
            runCatching { windowManager.removeView(view) }
        }
    }

    private fun showGuardNotification(foregroundPackage: String, message: String) {
        if (lastNotifiedPackage == foregroundPackage) return
        lastNotifiedPackage = foregroundPackage
        val notification = NotificationCompat.Builder(this, GUARD_CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_focus_notification)
            .setContentTitle("返回专注")
            .setContentText(message)
            .setContentIntent(openAppPendingIntent())
            .setCategory(NotificationCompat.CATEGORY_REMINDER)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setAutoCancel(true)
            .build()
        notificationManager.notify(GUARD_NOTIFICATION_ID, notification)
    }

    private fun returnToFocus() {
        runCatching { openAppPendingIntent().send() }
        hideGuardReminder()
    }

    private fun openAppPendingIntent(): PendingIntent {
        val openApp = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        return PendingIntent.getActivity(
            this,
            0,
            openApp,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun roundedBackground(color: Int, radius: Float): GradientDrawable {
        return GradientDrawable().apply {
            shape = GradientDrawable.RECTANGLE
            setColor(color)
            cornerRadius = radius
        }
    }

    private fun color(resourceId: Int): Int = ContextCompat.getColor(this, resourceId)

    private fun scheduleTargetReached() {
        handler.removeCallbacks(targetReached)
        val delay = (endsAtEpochMillis - System.currentTimeMillis()).coerceAtLeast(0)
        handler.postDelayed(targetReached, delay)
    }

    private fun createNotificationChannels() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val timerChannel = NotificationChannel(
            TIMER_CHANNEL_ID,
            "专注计时",
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "显示正在进行的专注会话"
            setShowBadge(false)
        }
        val guardChannel = NotificationChannel(
            GUARD_CHANNEL_ID,
            "守护提醒",
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = "守护模式下，打开白名单外的应用时提醒"
            setShowBadge(false)
        }
        notificationManager.createNotificationChannels(listOf(timerChannel, guardChannel))
    }

    private fun persistState(active: Boolean) {
        preferences.edit()
            .putBoolean(KEY_ACTIVE, active)
            .putBoolean(KEY_PAUSED, paused)
            .putString(KEY_TITLE, title)
            .putString(KEY_MODE, mode)
            .putLong(KEY_ENDS_AT, endsAtEpochMillis)
            .putLong(KEY_PAUSED_REMAINING, pausedRemainingMillis)
            .putStringSet(KEY_ALLOWED_PACKAGES, allowedPackageNames)
            .putString(KEY_TASK_TYPE_NAME, taskTypeName)
            .putInt(KEY_MAX_APP_EXITS, maxAppExits ?: -1)
            .putInt(KEY_APP_EXIT_COUNT, appExitCount)
            .putInt(KEY_INTERRUPTION_COUNT, interruptionCount)
            .putString(KEY_SESSION_ID, sessionId)
            .apply()
    }

    private fun persistGuardStats() {
        preferences.edit()
            .putInt(KEY_APP_EXIT_COUNT, appExitCount)
            .putInt(KEY_INTERRUPTION_COUNT, interruptionCount)
            .apply()
    }

    private fun restoreState() {
        title = preferences.getString(KEY_TITLE, getString(R.string.app_name)).orEmpty()
        mode = preferences.getString(KEY_MODE, "normal").orEmpty()
        endsAtEpochMillis = preferences.getLong(KEY_ENDS_AT, 0)
        pausedRemainingMillis = preferences.getLong(KEY_PAUSED_REMAINING, 0)
        paused = preferences.getBoolean(KEY_PAUSED, false)
        allowedPackageNames = preferences.getStringSet(KEY_ALLOWED_PACKAGES, emptySet())
            ?.toSet()
            .orEmpty()
        taskTypeName = preferences.getString(KEY_TASK_TYPE_NAME, "收集箱").orEmpty()
        maxAppExits = preferences.getInt(KEY_MAX_APP_EXITS, -1).takeIf { it >= 0 }
        appExitCount = preferences.getInt(KEY_APP_EXIT_COUNT, 0)
        interruptionCount = preferences.getInt(KEY_INTERRUPTION_COUNT, 0)
        sessionId = preferences.getString(KEY_SESSION_ID, null)
    }

    private fun dp(value: Int): Int = (value * resources.displayMetrics.density).toInt()

    private fun statusBarHeight(): Int {
        val identifier = resources.getIdentifier("status_bar_height", "dimen", "android")
        return if (identifier == 0) dp(8) else resources.getDimensionPixelSize(identifier)
    }

    private val notificationManager: NotificationManager
        get() = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

    private val usageStatsManager: UsageStatsManager
        get() = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager

    private val windowManager: WindowManager
        get() = getSystemService(Context.WINDOW_SERVICE) as WindowManager

    private val preferences
        get() = getSharedPreferences(PREFERENCES_NAME, Context.MODE_PRIVATE)

    companion object {
        const val ACTION_START = "com.example.pactick.action.START"
        const val ACTION_PAUSE = "com.example.pactick.action.PAUSE"
        const val ACTION_RESUME = "com.example.pactick.action.RESUME"
        const val ACTION_STOP = "com.example.pactick.action.STOP"
        private const val EXTRA_TITLE = "title"
        private const val EXTRA_ENDS_AT = "ends_at"
        private const val EXTRA_MODE = "mode"
        private const val EXTRA_ALLOWED_PACKAGES = "allowed_packages"
        private const val EXTRA_TASK_TYPE_NAME = "task_type_name"
        private const val EXTRA_MAX_APP_EXITS = "max_app_exits"
        private const val EXTRA_SESSION_ID = "session_id"
        private const val EXTRA_PAUSED = "paused"
        private const val EXTRA_APP_EXIT_COUNT = "app_exit_count"
        private const val EXTRA_INTERRUPTION_COUNT = "interruption_count"
        private const val TIMER_CHANNEL_ID = "focus_timer"
        private const val GUARD_CHANNEL_ID = "focus_guard_alert"
        private const val NOTIFICATION_ID = 1201
        private const val GUARD_NOTIFICATION_ID = 1202
        private const val PREFERENCES_NAME = "focus_timer_state"
        private const val KEY_ACTIVE = "active"
        private const val KEY_PAUSED = "paused"
        private const val KEY_TITLE = "title"
        private const val KEY_MODE = "mode"
        private const val KEY_ENDS_AT = "ends_at"
        private const val KEY_PAUSED_REMAINING = "paused_remaining"
        private const val KEY_ALLOWED_PACKAGES = "allowed_packages"
        private const val KEY_TASK_TYPE_NAME = "task_type_name"
        private const val KEY_MAX_APP_EXITS = "max_app_exits"
        private const val KEY_APP_EXIT_COUNT = "app_exit_count"
        private const val KEY_INTERRUPTION_COUNT = "interruption_count"
        private const val KEY_SESSION_ID = "session_id"
        private const val MONITOR_INTERVAL_MILLIS = 750L
        private const val EVENT_LOOKBACK_MILLIS = 15_000L

        fun intent(
            context: Context,
            action: String,
            title: String? = null,
            endsAtEpochMillis: Long? = null,
            mode: String? = null,
            allowedPackageNames: List<String>? = null,
            taskTypeName: String? = null,
            maxAppExits: Int? = null,
            sessionId: String? = null,
            paused: Boolean? = null,
            appExitCount: Int? = null,
            interruptionCount: Int? = null,
        ): Intent {
            return Intent(context, FocusTimerService::class.java).apply {
                this.action = action
                title?.let { putExtra(EXTRA_TITLE, it) }
                endsAtEpochMillis?.let { putExtra(EXTRA_ENDS_AT, it) }
                mode?.let { putExtra(EXTRA_MODE, it) }
                allowedPackageNames?.let {
                    putStringArrayListExtra(EXTRA_ALLOWED_PACKAGES, ArrayList(it))
                }
                taskTypeName?.let { putExtra(EXTRA_TASK_TYPE_NAME, it) }
                maxAppExits?.let { putExtra(EXTRA_MAX_APP_EXITS, it) }
                sessionId?.let { putExtra(EXTRA_SESSION_ID, it) }
                paused?.let { putExtra(EXTRA_PAUSED, it) }
                appExitCount?.let { putExtra(EXTRA_APP_EXIT_COUNT, it) }
                interruptionCount?.let { putExtra(EXTRA_INTERRUPTION_COUNT, it) }
            }
        }

        fun guardActivityStats(context: Context): Map<String, Any?> {
            val preferences = context.getSharedPreferences(
                PREFERENCES_NAME,
                Context.MODE_PRIVATE,
            )
            return mapOf(
                "appExitCount" to preferences.getInt(KEY_APP_EXIT_COUNT, 0),
                "interruptionCount" to preferences.getInt(KEY_INTERRUPTION_COUNT, 0),
                "sessionId" to preferences.getString(KEY_SESSION_ID, null),
            )
        }

        fun timerState(context: Context): Map<String, Any?> {
            val preferences = context.getSharedPreferences(PREFERENCES_NAME, Context.MODE_PRIVATE)
            return mapOf(
                "sessionId" to preferences.getString(KEY_SESSION_ID, null),
                "active" to preferences.getBoolean(KEY_ACTIVE, false),
            )
        }
    }
}
