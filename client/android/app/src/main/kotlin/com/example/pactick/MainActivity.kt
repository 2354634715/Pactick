package com.example.pactick

import android.Manifest
import android.app.Activity
import android.app.AppOpsManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Process
import android.provider.Settings
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
    private var notificationPermissionResult: MethodChannel.Result? = null
    private var backupResult: MethodChannel.Result? = null
    private var backupContents: ByteArray? = null
    private val backupExecutor = Executors.newSingleThreadExecutor()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            FOCUS_CHANNEL,
        ).setMethodCallHandler(::handleFocusCall)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            BACKUP_CHANNEL,
        ).setMethodCallHandler(::handleBackupCall)
    }

    private fun handleBackupCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "saveJson" && call.method != "openJson") {
            result.notImplemented()
            return
        }
        if (backupResult != null) {
            result.error("backup_busy", "正在选择或读写文件，请等待当前操作完成。", null)
            return
        }
        val saving = call.method == "saveJson"
        if (saving) {
            val contents = call.argument<String>("contents")
            if (contents == null) {
                result.error("invalid_backup", "缺少备份内容。", null)
                return
            }
            val bytes = contents.toByteArray(Charsets.UTF_8)
            if (bytes.size > MAX_BACKUP_BYTES) {
                result.error("backup_too_large", "备份超过 50 MiB 限制。", null)
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
            result.error("file_picker_unavailable", "无法打开系统文件选择器。", null)
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
                                throw IllegalArgumentException("备份超过 50 MiB 限制。")
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
                        result.error("backup_io_error", "文件读写失败，请检查文件、可用空间和访问权限。备份文件须使用 UTF-8 编码，且不超过 50 MiB。", null)
                    }
                }
            }
        }
    }

    override fun onDestroy() {
        backupResult?.error("backup_interrupted", "文件操作已中断，请重试。", null)
        backupResult = null
        backupContents = null
        backupExecutor.shutdown()
        super.onDestroy()
    }

    private fun handleFocusCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "startTimer" -> {
                val title = call.argument<String>("title") ?: getString(R.string.app_name)
                val endsAt = call.argument<Number>("endsAtEpochMillis")?.toLong()
                    ?: System.currentTimeMillis()
                val mode = call.argument<String>("mode") ?: "normal"
                val allowedPackageNames =
                    call.argument<List<String>>("allowedPackageNames").orEmpty()
                val taskTypeName = call.argument<String>("taskTypeName") ?: "收集箱"
                val maxAppExits = call.argument<Number>("maxAppExits")?.toInt()
                val intent = FocusTimerService.intent(
                    context = this,
                    action = FocusTimerService.ACTION_START,
                    title = title,
                    endsAtEpochMillis = endsAt,
                    mode = mode,
                    allowedPackageNames = allowedPackageNames,
                    taskTypeName = taskTypeName,
                    maxAppExits = maxAppExits,
                    sessionId = call.argument<String>("sessionId"),
                    paused = call.argument<Boolean>("paused") ?: false,
                    appExitCount = call.argument<Number>("appExitCount")?.toInt() ?: 0,
                    interruptionCount = call.argument<Number>("interruptionCount")?.toInt() ?: 0,
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
                startService(FocusTimerService.intent(this, FocusTimerService.ACTION_STOP))
                result.success(null)
            }

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

            "requestNotificationPermission" -> requestNotificationPermission(result)
            else -> result.notImplemented()
        }
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

    private fun requestNotificationPermission(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            result.success(true)
            return
        }
        if (ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.POST_NOTIFICATIONS,
            ) == PackageManager.PERMISSION_GRANTED
        ) {
            result.success(true)
            return
        }
        notificationPermissionResult = result
        ActivityCompat.requestPermissions(
            this,
            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
            NOTIFICATION_PERMISSION_REQUEST,
        )
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != NOTIFICATION_PERMISSION_REQUEST) return
        notificationPermissionResult?.success(
            grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED,
        )
        notificationPermissionResult = null
    }

    companion object {
        private const val FOCUS_CHANNEL = "pactick/focus"
        private const val BACKUP_CHANNEL = "pactick/backup_files"
        private const val NOTIFICATION_PERMISSION_REQUEST = 901
        private const val SAVE_BACKUP_REQUEST = 902
        private const val OPEN_BACKUP_REQUEST = 903
        private const val MAX_BACKUP_BYTES = 50 * 1024 * 1024
    }
}
