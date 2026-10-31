package com.example.pactick

import android.Manifest
import android.app.Activity
import android.app.AppOpsManager
import android.app.NotificationManager
import android.content.Context
import android.content.res.Configuration
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.Process
import android.provider.Settings
import android.util.Log
import android.view.WindowManager
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.nio.ByteBuffer
import java.nio.charset.CodingErrorAction
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val notificationPermissionCallbacks = mutableListOf<() -> Unit>()
    private var notificationPermissionInFlight = false
    private var openTasksRequested = false
    private var backupResult: MethodChannel.Result? = null
    private var backupContents: ByteArray? = null
    private val backupExecutor = Executors.newSingleThreadExecutor()
    private var systemCalendarBridge: SystemCalendarBridge? = null
    private var focusDesktopRequestGeneration = 0
    private var lastRequestedFocusSessionId: String? = null
    private var activityResumed = false

    override fun onResume() {
        super.onResume()
        activityResumed = true
    }

    override fun onPause() {
        activityResumed = false
        super.onPause()
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        openTasksRequested = intent?.action == TaskReminderManager.ACTION_OPEN_TASKS
        super.onCreate(savedInstanceState)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        if (intent.action == TaskReminderManager.ACTION_OPEN_TASKS) {
            openTasksRequested = true
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        systemCalendarBridge?.dispose()
        systemCalendarBridge = SystemCalendarBridge(this, flutterEngine.dartExecutor.binaryMessenger)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "pactick/language",
        ).setMethodCallHandler { call, result ->
            if (call.method == "configure") {
                try {
                    PactickStrings.configure(this, call.argument<String>("preference") ?: "system")
                    refreshNativeLanguage()
                    result.success(null)
                } catch (error: Exception) {
                    result.error("language_update_failed", error.message, null)
                }
            } else result.notImplemented()
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            FOCUS_CHANNEL,
        ).setMethodCallHandler(::handleFocusCall)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            BACKUP_CHANNEL,
        ).setMethodCallHandler(::handleBackupCall)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            TASK_REMINDERS_CHANNEL,
        ).setMethodCallHandler(::handleTaskReminderCall)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "pactick/private_vault",
        ).setMethodCallHandler { call, result ->
            if (call.method == "setSecure") {
                val enabled = call.argument<Boolean>("enabled")
                    ?: call.argument<Boolean>("secure") ?: true
                if (enabled) window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                else window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                result.success(null)
            } else result.notImplemented()
        }
    }

    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)
        refreshNativeLanguage()
    }

    private fun refreshNativeLanguage() {
        TaskReminderManager.refreshLocalization(this)
        FocusTimerService.refreshLanguage()
    }

    private fun handleTaskReminderCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "update" -> {
                try {
                    val enabled = call.argument<Boolean>("enabled") ?: true
                    val count = call.argument<Number>("openTaskCount")?.toInt()?.coerceAtLeast(0) ?: 0
                    val workspaceId = call.argument<String>("workspaceId") ?: ""
                    val allowed = TaskReminderManager.update(this, enabled, count, workspaceId)
                    val wantsPermission = call.argument<Boolean>("requestPermission") ?: false
                    val automatic = call.argument<Boolean>("automatic") ?: true
                    val mayRequest = !automatic ||
                        !TaskReminderManager.hasAutomaticallyRequestedPermission(this)
                    val mayAutomaticallyRequest = enabled && count > 0 && workspaceId.isNotEmpty()
                    if (wantsPermission && mayRequest && (!automatic || mayAutomaticallyRequest)
                    ) {
                        requestNotificationPermission {
                            try {
                                result.success(TaskReminderManager.refresh(this))
                            } catch (error: Exception) {
                                taskReminderUpdateFailed(result, error)
                            }
                        }
                    } else {
                        result.success(allowed)
                    }
                } catch (error: Exception) {
                    taskReminderUpdateFailed(result, error)
                }
            }

            "clearWorkspace" -> {
                try {
                    TaskReminderManager.update(this, false, 0, "")
                    TaskReminderManager.updateSchedule(this, false, "", emptyList())
                    result.success(null)
                } catch (error: Exception) {
                    taskReminderUpdateFailed(result, error)
                }
            }

            "updateSchedule" -> {
                try {
                    val enabled = call.argument<Boolean>("enabled") ?: true
                    val workspaceId = call.argument<String>("workspaceId") ?: ""
                    val reminders = call.argument<List<Map<String, Any?>>>("reminders") ?: emptyList()
                    val allowed = TaskReminderManager.updateSchedule(this, enabled, workspaceId, reminders)
                    val wantsPermission = call.argument<Boolean>("requestPermission") ?: false
                    val automatic = call.argument<Boolean>("automatic") ?: true
                    val mayRequest = !automatic ||
                        !TaskReminderManager.hasAutomaticallyRequestedPermission(this)
                    if (wantsPermission && mayRequest &&
                        (!automatic || (enabled && workspaceId.isNotEmpty() && reminders.isNotEmpty()))
                    ) {
                        requestNotificationPermission {
                            try {
                                result.success(TaskReminderManager.refreshSchedule(this))
                            } catch (error: Exception) {
                                taskReminderUpdateFailed(result, error)
                            }
                        }
                    } else {
                        result.success(allowed)
                    }
                } catch (error: Exception) {
                    taskReminderUpdateFailed(result, error)
                }
            }

            "openNotificationSettings" -> {
                val channelSettings = Intent(Settings.ACTION_CHANNEL_NOTIFICATION_SETTINGS).apply {
                    putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                    putExtra(Settings.EXTRA_CHANNEL_ID,
                        if (call.argument<Boolean>("scheduled") == true)
                            TaskReminderManager.SCHEDULED_CHANNEL_ID else TaskReminderManager.CHANNEL_ID)
                }
                try {
                    startActivity(channelSettings)
                    result.success(null)
                } catch (_: Exception) {
                    try {
                        startActivity(Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).apply {
                            putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                        })
                        result.success(null)
                    } catch (_: Exception) {
                        result.error("notification_settings_unavailable", PactickStrings.text(this@MainActivity, R.string.notification_settings_unavailable), null)
                    }
                }
            }

            "takeOpenTasksRequest" -> {
                val requested = openTasksRequested
                openTasksRequested = false
                if (intent?.action == TaskReminderManager.ACTION_OPEN_TASKS) {
                    intent.action = Intent.ACTION_MAIN
                }
                result.success(requested)
            }

            else -> result.notImplemented()
        }
    }

    private fun taskReminderUpdateFailed(result: MethodChannel.Result, error: Exception) {
        Log.w("TaskReminders", "Could not update task reminder", error)
        result.error("task_reminder_update_failed", PactickStrings.text(this@MainActivity, R.string.task_reminder_update_failed), null)
    }

    private fun handleBackupCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "saveJson" && call.method != "openJson") {
            result.notImplemented()
            return
        }
        if (backupResult != null) {
            result.error("backup_busy", PactickStrings.text(this@MainActivity, R.string.backup_busy), null)
            return
        }
        val saving = call.method == "saveJson"
        if (saving) {
            val contents = call.argument<String>("contents")
            if (contents == null) {
                result.error("invalid_backup", PactickStrings.text(this@MainActivity, R.string.invalid_backup), null)
                return
            }
            val bytes = contents.toByteArray(Charsets.UTF_8)
            if (bytes.size > MAX_BACKUP_BYTES) {
                result.error("backup_too_large", PactickStrings.text(this@MainActivity, R.string.backup_too_large), null)
                return
            }
            backupContents = bytes
        }
        val intent = Intent(if (saving) Intent.ACTION_CREATE_DOCUMENT else Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = if (saving) "application/json" else "*/*"
            if (saving) {
                val suggested = call.argument<String>("suggestedName") ?: "pactick-backup.json"
                putExtra(Intent.EXTRA_TITLE, suggested.substringAfterLast('/').substringAfterLast('\\'))
            }
        }
        backupResult = result
        try {
            startActivityForResult(intent, if (saving) SAVE_BACKUP_REQUEST else OPEN_BACKUP_REQUEST)
        } catch (error: Exception) {
            backupResult = null
            backupContents = null
            result.error("file_picker_unavailable", PactickStrings.text(this@MainActivity, R.string.file_picker_unavailable), null)
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != SAVE_BACKUP_REQUEST && requestCode != OPEN_BACKUP_REQUEST) return
        val result = backupResult ?: return
        val saving = requestCode == SAVE_BACKUP_REQUEST
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            backupResult = null
            backupContents = null
            result.success(if (saving) false else null)
            return
        }
        val contents = backupContents
        backupContents = null
        // Document providers can perform slow disk or network I/O.
        backupExecutor.execute {
            try {
                val response: Any = if (saving) {
                    val bytes = contents ?: throw IllegalStateException("Missing backup")
                    contentResolver.openOutputStream(uri, "wt")?.use { output ->
                        output.write(bytes)
                        output.flush()
                    } ?: throw IllegalStateException("Cannot open output")
                    true
                } else {
                    val bytes = contentResolver.openInputStream(uri)?.use { input ->
                        val output = ByteArrayOutputStream()
                        val buffer = ByteArray(8192)
                        while (true) {
                            val read = input.read(buffer)
                            if (read < 0) break
                            if (output.size() + read > MAX_BACKUP_BYTES) {
                                throw IllegalArgumentException(PactickStrings.text(this@MainActivity, R.string.backup_too_large))
                            }
                            output.write(buffer, 0, read)
                        }
                        output.toByteArray()
                    } ?: throw IllegalStateException("Cannot open input")
                    Charsets.UTF_8.newDecoder()
                        .onMalformedInput(CodingErrorAction.REPORT)
                        .onUnmappableCharacter(CodingErrorAction.REPORT)
                        .decode(ByteBuffer.wrap(bytes)).toString()
                }
                runOnUiThread {
                    if (backupResult === result) {
                        backupResult = null
                        result.success(response)
                    }
                }
            } catch (error: Exception) {
                runOnUiThread {
                    if (backupResult === result) {
                        backupResult = null
                        result.error("backup_io_error", PactickStrings.text(this@MainActivity, R.string.backup_io_error), null)
                    }
                }
            }
        }
    }

    override fun onDestroy() {
        systemCalendarBridge?.dispose()
        systemCalendarBridge = null
        finishNotificationPermissionRequests()
        backupResult?.error("backup_interrupted", PactickStrings.text(this@MainActivity, R.string.backup_interrupted), null)
        backupResult = null
        backupContents = null
        backupExecutor.shutdown()
        super.onDestroy()
    }

    private fun handleFocusCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "configureFeedback" -> {
                FocusFeedback.configure(
                    this,
                    call.argument<Boolean>("enabled") ?: true,
                    call.argument<String>("notificationMode") ?: "vibrate",
                )
                result.success(null)
            }
            "feedback" -> {
                FocusFeedback.play(this, call.argument<String>("event").orEmpty())
                result.success(null)
            }
            "startTimer" -> {
                lastRequestedFocusSessionId = call.argument<String>("sessionId")
                val title = call.argument<String>("title") ?: getString(R.string.app_name)
                val endsAt = call.argument<Number>("endsAtEpochMillis")?.toLong()
                    ?: System.currentTimeMillis()
                val mode = call.argument<String>("mode") ?: "normal"
                val allowedPackageNames =
                    call.argument<List<String>>("allowedPackageNames").orEmpty()
                val taskTypeName = call.argument<String>("taskTypeName") ?: PactickStrings.text(this@MainActivity, R.string.inbox)
                val maxAppExits = call.argument<Number>("maxAppExits")?.toInt()
                val intent = FocusTimerService.intent(
                    context = this,
                    action = FocusTimerService.ACTION_START,
                    title = title,
                    titleKey = call.argument<String>("titleKey"),
                    endsAtEpochMillis = endsAt,
                    mode = mode,
                    allowedPackageNames = allowedPackageNames,
                    taskTypeName = taskTypeName,
                    taskTypeKey = call.argument<String>("taskTypeKey"),
                    maxAppExits = maxAppExits,
                    sessionId = call.argument<String>("sessionId"),
                    paused = call.argument<Boolean>("paused") ?: false,
                    appExitCount = call.argument<Number>("appExitCount")?.toInt() ?: 0,
                    interruptionCount = call.argument<Number>("interruptionCount")?.toInt() ?: 0,
                    focusDesktopEnabled = call.argument<Boolean>("focusDesktopEnabled") ?: false,
                )
                ContextCompat.startForegroundService(this, intent)
                result.success(null)
            }

            "pauseTimer" -> {
                startService(FocusTimerService.intent(this, FocusTimerService.ACTION_PAUSE))
                result.success(null)
            }

            "resumeTimer" -> {
                val endsAt = call.argument<Number>("endsAtEpochMillis")?.toLong()
                    ?: System.currentTimeMillis()
                startService(
                    FocusTimerService.intent(
                        context = this,
                        action = FocusTimerService.ACTION_RESUME,
                        endsAtEpochMillis = endsAt,
                    ),
                )
                result.success(null)
            }

            "stopTimer" -> {
                focusDesktopRequestGeneration++
                startService(FocusTimerService.intent(this, FocusTimerService.ACTION_STOP))
                result.success(null)
            }

            "configureFocusDesktop" -> {
                focusDesktopRequestGeneration++
                FocusTimerService.configureDesktop(call.argument<Boolean>("enabled") ?: false)
                result.success(null)
            }

            "openFocusDesktop" -> openFocusDesktop(result)

            "hasUsageAccess" -> result.success(hasUsageAccess())
            "openUsageAccessSettings" -> {
                val intent = Intent(
                    Settings.ACTION_USAGE_ACCESS_SETTINGS,
                    Uri.parse("package:$packageName"),
                )
                startActivity(intent)
                result.success(null)
            }

            "hasOverlayPermission" -> result.success(hasOverlayPermission())
            "openOverlayPermissionSettings" -> {
                openOverlayPermissionSettings()
                result.success(null)
            }

            "getInstalledApplications" -> result.success(getInstalledApplications())
            "getGuardActivityStats" -> result.success(FocusTimerService.guardActivityStats(this))
            "getTimerState" -> result.success(FocusTimerService.timerState(this))

            "requestNotificationPermission" -> requestNotificationPermission {
                result.success(appNotificationsAllowed())
            }
            else -> result.notImplemented()
        }
    }

    private fun openFocusDesktop(result: MethodChannel.Result) {
        val generation = ++focusDesktopRequestGeneration
        val expectedSessionId = lastRequestedFocusSessionId
        val handler = Handler(Looper.getMainLooper())
        fun attempt(remaining: Int) {
            if (generation != focusDesktopRequestGeneration || isFinishing || isDestroyed || !activityResumed) {
                result.success(false)
                return
            }
            val state = FocusTimerService.desktopState()
            if (state != null && (expectedSessionId == null || state.sessionId == expectedSessionId)) {
                try {
                    startActivity(FocusDesktopActivity.intent(this, state.sessionId))
                    result.success(true)
                } catch (_: Exception) {
                    result.error("focus_desktop_unavailable", PactickStrings.text(this, R.string.focus_desktop_unavailable), null)
                }
            } else if (remaining > 0) {
                // Starting a foreground service is asynchronous. Do not restore or
                // launch from background; wait briefly for this explicit request.
                handler.postDelayed({ attempt(remaining - 1) }, 40L)
            } else result.success(false)
        }
        attempt(25)
    }

    private fun hasUsageAccess(): Boolean {
        val appOps = getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
        val mode = appOps.checkOpNoThrow(
            AppOpsManager.OPSTR_GET_USAGE_STATS,
            Process.myUid(),
            packageName,
        )
        return mode == AppOpsManager.MODE_ALLOWED
    }

    private fun hasOverlayPermission(): Boolean {
        return Build.VERSION.SDK_INT < Build.VERSION_CODES.M || Settings.canDrawOverlays(this)
    }

    private fun openOverlayPermissionSettings() {
        val intent = Intent(
            Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
            Uri.parse("package:$packageName"),
        )
        startActivity(intent)
    }

    private fun getInstalledApplications(): List<Map<String, String>> {
        val launcherIntent = Intent(Intent.ACTION_MAIN).apply {
            addCategory(Intent.CATEGORY_LAUNCHER)
        }
        return packageManager.queryIntentActivities(launcherIntent, 0)
            .asSequence()
            .map { it.activityInfo.applicationInfo }
            .filter { it.packageName != packageName }
            .distinctBy { it.packageName }
            .map {
                mapOf(
                    "packageName" to it.packageName,
                    "label" to packageManager.getApplicationLabel(it).toString(),
                )
            }
            .sortedBy { it.getValue("label").lowercase() }
            .toList()
    }

    private fun appNotificationsAllowed(): Boolean = runCatching {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.areNotificationsEnabled() &&
            (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
                ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) ==
                PackageManager.PERMISSION_GRANTED)
    }.getOrDefault(false)

    private fun requestNotificationPermission(onComplete: () -> Unit) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU || isFinishing || isDestroyed ||
            ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.POST_NOTIFICATIONS,
            ) == PackageManager.PERMISSION_GRANTED
        ) {
            onComplete()
            return
        }
        notificationPermissionCallbacks.add(onComplete)
        if (notificationPermissionInFlight) return
        notificationPermissionInFlight = true
        try {
            TaskReminderManager.markPermissionRequested(this)
            ActivityCompat.requestPermissions(
                this,
                arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                NOTIFICATION_PERMISSION_REQUEST,
            )
        } catch (error: Exception) {
            Log.w("TaskReminders", "Could not request notification permission", error)
            finishNotificationPermissionRequests()
        }
    }

    private fun finishNotificationPermissionRequests() {
        notificationPermissionInFlight = false
        val callbacks = notificationPermissionCallbacks.toList()
        notificationPermissionCallbacks.clear()
        for (callback in callbacks) {
            runCatching(callback)
                .onFailure { Log.w("TaskReminders", "Could not return notification permission state", it) }
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (systemCalendarBridge?.onRequestPermissionsResult(requestCode) == true) return
        if (requestCode != NOTIFICATION_PERMISSION_REQUEST) return
        finishNotificationPermissionRequests()
    }

    companion object {
        private const val FOCUS_CHANNEL = "pactick/focus"
        private const val BACKUP_CHANNEL = "pactick/backup_files"
        private const val TASK_REMINDERS_CHANNEL = "pactick/task_reminders"
        private const val NOTIFICATION_PERMISSION_REQUEST = 901
        private const val SAVE_BACKUP_REQUEST = 902
        private const val OPEN_BACKUP_REQUEST = 903
        private const val MAX_BACKUP_BYTES = 50 * 1024 * 1024
    }
}
