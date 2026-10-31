package com.example.pactick

import android.app.KeyguardManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.res.Configuration
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
import android.util.Log
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
    @Volatile private var titleKey: String? = null
    @Volatile private var mode: String = "normal"
    @Volatile private var endsAtEpochMillis: Long = 0
    @Volatile private var pausedRemainingMillis: Long = 0
    @Volatile private var paused = false
    @Volatile private var allowedPackageNames: Set<String> = emptySet()
    @Volatile private var focusDesktopEnabled = false
    @Volatile private var timerActive = false
    @Volatile private var taskTypeName: String = ""
    @Volatile private var taskTypeKey: String? = null
    @Volatile private var maxAppExits: Int? = null
    @Volatile private var appExitCount = 0
    @Volatile private var interruptionCount = 0
    @Volatile private var sessionId: String? = null
    @Volatile private var guardMonitorGeneration = 0L
    @Volatile private var lastForegroundPackage: String? = null
    private var targetSignalled = false

    private var overlayView: View? = null
    private var dismissingOverlayView: View? = null
    private var overlayMessage: TextView? = null
    private var lastNotifiedPackage: String? = null

    private val targetReached = Runnable {
        if (targetSignalled || paused) return@Runnable
        targetSignalled = true
        preferences.edit().putBoolean(KEY_TARGET_SIGNALLED, true).apply()
        FocusFeedback.play(this, "target")
        val notification = baseNotification()
            .setContentTitle(PactickStrings.text(this@FocusTimerService, R.string.focus_target_reached))
            .setContentText(localizedLabel(titleKey, title))
            .setOngoing(true)
            .build()
        notificationManager.notify(NOTIFICATION_ID, notification)
    }

    override fun onCreate() {
        super.onCreate()
        createNotificationChannels()
        restoreState()
        runningInstance = this
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> {
                val requestedSessionId = intent.getStringExtra(EXTRA_SESSION_ID)
                val sameSession = requestedSessionId != null && requestedSessionId == sessionId
                if (!sameSession) targetSignalled = false
                handler.removeCallbacks(targetReached)
                stopGuardMonitoring()
                removeGuardReminderImmediately()
                title = intent.getStringExtra(EXTRA_TITLE) ?: getString(R.string.app_name)
                titleKey = intent.getStringExtra(EXTRA_TITLE_KEY)
                mode = intent.getStringExtra(EXTRA_MODE) ?: "normal"
                endsAtEpochMillis = intent.getLongExtra(
                    EXTRA_ENDS_AT,
                    System.currentTimeMillis(),
                )
                allowedPackageNames = intent
                    .getStringArrayListExtra(EXTRA_ALLOWED_PACKAGES)
                    ?.toSet()
                    .orEmpty()
                focusDesktopEnabled = intent.getBooleanExtra(EXTRA_DESKTOP_ENABLED, false)
                taskTypeName = intent.getStringExtra(EXTRA_TASK_TYPE_NAME) ?: PactickStrings.text(this@FocusTimerService, R.string.inbox)
                taskTypeKey = intent.getStringExtra(EXTRA_TASK_TYPE_KEY)
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
                timerActive = true
                lastForegroundPackage = packageName
                persistState(active = true)
                startAsForeground(if (paused) buildPausedNotification() else buildRunningNotification())
                if (!paused) {
                    scheduleTargetReached()
                    startGuardMonitoring()
                }
                if (!sameSession && !paused && endsAtEpochMillis > System.currentTimeMillis()) {
                    FocusFeedback.play(this, "started")
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
                FocusFeedback.play(this, "resumed")
            }

            ACTION_STOP -> stopTimer()
            null -> {
                if (preferences.getBoolean(KEY_ACTIVE, false)) {
                    timerActive = true
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

    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)
        refreshNotificationLanguage()
    }

    // Rebuild only the running service. A persisted active flag can outlive it.
    private fun refreshNotificationLanguage() {
        runCatching {
            createNotificationChannels()
            if (!preferences.getBoolean(KEY_ACTIVE, false)) return@runCatching
            removeGuardReminderImmediately()
            val notification = when {
                paused -> buildPausedNotification()
                targetSignalled -> baseNotification()
                    .setContentTitle(PactickStrings.text(this@FocusTimerService, R.string.focus_target_reached))
                    .setContentText(localizedLabel(titleKey, title)).setOngoing(true).build()
                else -> buildRunningNotification()
            }
            notificationManager.notify(NOTIFICATION_ID, notification)
        }.onFailure { Log.w("FocusTimerService", "Could not refresh notification language", it) }
    }

    // Keys identify app-generated labels. Missing/unknown keys keep legacy and
    // user-provided text verbatim instead of guessing from a task/project name.
    private fun localizedLabel(key: String?, fallback: String): String {
        val resource = when (key) {
            "private_task" -> R.string.private_task
            "free_focus" -> R.string.free_focus
            "inbox" -> R.string.inbox
            else -> return fallback
        }
        return PactickStrings.text(this@FocusTimerService, resource)
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        timerActive = false
        if (runningInstance === this) runningInstance = null
        handler.removeCallbacks(targetReached)
        stopGuardMonitoring()
        removeGuardReminderImmediately()
        monitorExecutor.shutdownNow()
        super.onDestroy()
    }

    private fun pauseTimer() {
        if (mode == "strict") return
        pausedRemainingMillis = (endsAtEpochMillis - System.currentTimeMillis()).coerceAtLeast(0)
        paused = true
        handler.removeCallbacks(targetReached)
        stopGuardMonitoring()
        hideGuardReminder()
        persistState(active = true)
        notificationManager.notify(NOTIFICATION_ID, buildPausedNotification())
        FocusFeedback.play(this, "paused")
    }

    private fun stopTimer() {
        timerActive = false
        handler.removeCallbacks(targetReached)
        stopGuardMonitoring()
        removeGuardReminderImmediately()
        title = ""
        titleKey = null
        taskTypeName = ""
        taskTypeKey = null
        allowedPackageNames = emptySet()
        focusDesktopEnabled = false
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
            .setContentTitle(localizedLabel(titleKey, title))
            .setContentText(when (mode) {
                "guard" -> PactickStrings.text(this@FocusTimerService, R.string.focus_guard_running)
                "strict" -> PactickStrings.text(this@FocusTimerService, R.string.focus_strict_running)
                else -> PactickStrings.text(this@FocusTimerService, R.string.focus_running)
            })
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
            .setContentTitle(PactickStrings.text(this@FocusTimerService, R.string.focus_paused))
            .setContentText(PactickStrings.text(this@FocusTimerService, R.string.focus_paused_remaining, localizedLabel(titleKey, title), minutes, seconds))
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
        if (mode !in setOf("guard", "strict") || paused) return
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
        if (generation != guardMonitorGeneration || mode !in setOf("guard", "strict") || paused) return
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
            if (generation != guardMonitorGeneration || mode !in setOf("guard", "strict") || paused) return@post
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
                FocusFeedback.play(this, "guard")
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
        return FocusDesktopApps.isAllowed(this, candidate, allowedPackageNames, focusDesktopEnabled)
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
        val message = PactickStrings.text(this@FocusTimerService, R.string.guard_app_blocked, appLabel, localizedLabel(taskTypeKey, taskTypeName))
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
            contentDescription = PactickStrings.text(this@FocusTimerService, R.string.return_focus_message, message)
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
            text = PactickStrings.text(this@FocusTimerService, R.string.return_focus)
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
            text = PactickStrings.text(this@FocusTimerService, R.string.return_back)
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
            contentDescription = PactickStrings.text(this@FocusTimerService, R.string.return_focus_page)
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
            .setContentTitle(PactickStrings.text(this@FocusTimerService, R.string.return_focus))
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
        if (targetSignalled) return
        val delay = (endsAtEpochMillis - System.currentTimeMillis()).coerceAtLeast(0)
        handler.postDelayed(targetReached, delay)
    }

    private fun createNotificationChannels() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val timerChannel = NotificationChannel(
            TIMER_CHANNEL_ID,
            PactickStrings.text(this@FocusTimerService, R.string.focus_timer_channel),
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = PactickStrings.text(this@FocusTimerService, R.string.focus_timer_channel_description)
            setShowBadge(false)
        }
        val guardChannel = NotificationChannel(
            GUARD_CHANNEL_ID,
            PactickStrings.text(this@FocusTimerService, R.string.focus_guard_channel),
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = PactickStrings.text(this@FocusTimerService, R.string.focus_guard_channel_description)
            setShowBadge(false)
        }
        notificationManager.createNotificationChannels(listOf(timerChannel, guardChannel))
    }

    private fun persistState(active: Boolean) {
        preferences.edit()
            .putBoolean(KEY_ACTIVE, active)
            .putBoolean(KEY_PAUSED, paused)
            .putString(KEY_TITLE, title)
            .putString(KEY_TITLE_KEY, titleKey)
            .putString(KEY_MODE, mode)
            .putLong(KEY_ENDS_AT, endsAtEpochMillis)
            .putLong(KEY_PAUSED_REMAINING, pausedRemainingMillis)
            .putStringSet(KEY_ALLOWED_PACKAGES, allowedPackageNames)
            .putBoolean(KEY_DESKTOP_ENABLED, focusDesktopEnabled)
            .putString(KEY_TASK_TYPE_NAME, taskTypeName)
            .putString(KEY_TASK_TYPE_KEY, taskTypeKey)
            .putInt(KEY_MAX_APP_EXITS, maxAppExits ?: -1)
            .putInt(KEY_APP_EXIT_COUNT, appExitCount)
            .putInt(KEY_INTERRUPTION_COUNT, interruptionCount)
            .putString(KEY_SESSION_ID, sessionId)
            .putBoolean(KEY_TARGET_SIGNALLED, targetSignalled)
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
        titleKey = preferences.getString(KEY_TITLE_KEY, null)
        mode = preferences.getString(KEY_MODE, "normal").orEmpty()
        endsAtEpochMillis = preferences.getLong(KEY_ENDS_AT, 0)
        pausedRemainingMillis = preferences.getLong(KEY_PAUSED_REMAINING, 0)
        paused = preferences.getBoolean(KEY_PAUSED, false)
        allowedPackageNames = preferences.getStringSet(KEY_ALLOWED_PACKAGES, emptySet())
            ?.toSet()
            .orEmpty()
        focusDesktopEnabled = preferences.getBoolean(KEY_DESKTOP_ENABLED, false)
        taskTypeName = preferences.getString(KEY_TASK_TYPE_NAME, PactickStrings.text(this@FocusTimerService, R.string.inbox)).orEmpty()
        taskTypeKey = preferences.getString(KEY_TASK_TYPE_KEY, null)
        maxAppExits = preferences.getInt(KEY_MAX_APP_EXITS, -1).takeIf { it >= 0 }
        appExitCount = preferences.getInt(KEY_APP_EXIT_COUNT, 0)
        interruptionCount = preferences.getInt(KEY_INTERRUPTION_COUNT, 0)
        sessionId = preferences.getString(KEY_SESSION_ID, null)
        targetSignalled = preferences.getBoolean(KEY_TARGET_SIGNALLED, false)
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
        @Volatile private var runningInstance: FocusTimerService? = null

        fun refreshLanguage() {
            val service = runningInstance ?: return
            service.handler.post {
                if (runningInstance === service) service.refreshNotificationLanguage()
            }
        }
        private const val EXTRA_TITLE = "title"
        private const val EXTRA_TITLE_KEY = "title_key"
        private const val EXTRA_ENDS_AT = "ends_at"
        private const val EXTRA_MODE = "mode"
        private const val EXTRA_ALLOWED_PACKAGES = "allowed_packages"
        private const val EXTRA_DESKTOP_ENABLED = "focus_desktop_enabled"
        private const val EXTRA_TASK_TYPE_NAME = "task_type_name"
        private const val EXTRA_TASK_TYPE_KEY = "task_type_key"
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
        private const val KEY_TITLE_KEY = "title_key"
        private const val KEY_MODE = "mode"
        private const val KEY_ENDS_AT = "ends_at"
        private const val KEY_PAUSED_REMAINING = "paused_remaining"
        private const val KEY_ALLOWED_PACKAGES = "allowed_packages"
        private const val KEY_DESKTOP_ENABLED = "focus_desktop_enabled"
        private const val KEY_TASK_TYPE_NAME = "task_type_name"
        private const val KEY_TASK_TYPE_KEY = "task_type_key"
        private const val KEY_MAX_APP_EXITS = "max_app_exits"
        private const val KEY_APP_EXIT_COUNT = "app_exit_count"
        private const val KEY_INTERRUPTION_COUNT = "interruption_count"
        private const val KEY_SESSION_ID = "session_id"
        private const val KEY_TARGET_SIGNALLED = "target_signalled"
        private const val MONITOR_INTERVAL_MILLIS = 750L
        private const val EVENT_LOOKBACK_MILLIS = 15_000L

        fun intent(
            context: Context,
            action: String,
            title: String? = null,
            titleKey: String? = null,
            endsAtEpochMillis: Long? = null,
            mode: String? = null,
            allowedPackageNames: List<String>? = null,
            taskTypeName: String? = null,
            taskTypeKey: String? = null,
            maxAppExits: Int? = null,
            sessionId: String? = null,
            paused: Boolean? = null,
            appExitCount: Int? = null,
            interruptionCount: Int? = null,
            focusDesktopEnabled: Boolean? = null,
        ): Intent {
            return Intent(context, FocusTimerService::class.java).apply {
                this.action = action
                title?.let { putExtra(EXTRA_TITLE, it) }
                titleKey?.let { putExtra(EXTRA_TITLE_KEY, it) }
                endsAtEpochMillis?.let { putExtra(EXTRA_ENDS_AT, it) }
                mode?.let { putExtra(EXTRA_MODE, it) }
                allowedPackageNames?.let {
                    putStringArrayListExtra(EXTRA_ALLOWED_PACKAGES, ArrayList(it))
                }
                focusDesktopEnabled?.let { putExtra(EXTRA_DESKTOP_ENABLED, it) }
                taskTypeName?.let { putExtra(EXTRA_TASK_TYPE_NAME, it) }
                taskTypeKey?.let { putExtra(EXTRA_TASK_TYPE_KEY, it) }
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

        /** A live service is required: a persisted active flag can outlive it. */
        fun desktopState(): FocusDesktopState? {
            val service = runningInstance ?: return null
            if (!service.timerActive || !service.focusDesktopEnabled) return null
            return FocusDesktopState(
                sessionId = service.sessionId,
                allowedPackageNames = service.allowedPackageNames.toSet(),
                paused = service.paused,
                endsAtEpochMillis = service.endsAtEpochMillis,
                pausedRemainingMillis = service.pausedRemainingMillis,
            )
        }

        fun configureDesktop(enabled: Boolean) {
            val service = runningInstance ?: return
            service.focusDesktopEnabled = enabled
            service.preferences.edit().putBoolean(KEY_DESKTOP_ENABLED, enabled).apply()
            service.removeGuardReminderImmediately()
        }
    }
}
