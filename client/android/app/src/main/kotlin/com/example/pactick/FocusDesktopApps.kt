package com.example.pactick

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.graphics.drawable.Drawable
import java.text.Collator

data class FocusDesktopState(
    val sessionId: String?,
    val allowedPackageNames: Set<String>,
    val paused: Boolean,
    val endsAtEpochMillis: Long,
    val pausedRemainingMillis: Long,
)

data class FocusDesktopApp(
    val packageName: String,
    val component: ComponentName,
    val label: String,
    val icon: Drawable,
)

/** Shares the same rule with the guard monitor and rechecks before each launch. */
object FocusDesktopApps {
    fun allowsPackage(
        candidate: String,
        ownPackage: String,
        allowedPackages: Set<String>,
        desktopEnabled: Boolean,
        applicationFlags: Int,
    ): Boolean = candidate == ownPackage || candidate in allowedPackages ||
        (desktopEnabled && applicationFlags and
            (ApplicationInfo.FLAG_SYSTEM or ApplicationInfo.FLAG_UPDATED_SYSTEM_APP) != 0)

    fun isAllowed(
        context: Context,
        candidate: String,
        allowedPackages: Set<String>,
        desktopEnabled: Boolean = true,
    ): Boolean {
        if (candidate == context.packageName || candidate in allowedPackages) return true
        if (!desktopEnabled) return false
        val flags = runCatching {
            context.packageManager.getApplicationInfo(candidate, 0).flags
        }.getOrDefault(0)
        return allowsPackage(candidate, context.packageName, allowedPackages, true, flags)
    }

    fun load(context: Context, allowedPackages: Set<String>): List<FocusDesktopApp> {
        val manager = context.packageManager
        val launcher = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        val apps = manager.queryIntentActivities(launcher, 0).asSequence()
            .filter { it.activityInfo.enabled && it.activityInfo.exported && it.activityInfo.applicationInfo.enabled }
            .filter {
                allowsPackage(
                    it.activityInfo.packageName, context.packageName, allowedPackages,
                    true, it.activityInfo.applicationInfo.flags,
                )
            }
            .distinctBy { it.activityInfo.packageName }
            .mapNotNull {
                runCatching {
                    FocusDesktopApp(
                        packageName = it.activityInfo.packageName,
                        component = ComponentName(it.activityInfo.packageName, it.activityInfo.name),
                        label = it.loadLabel(manager).toString(),
                        icon = it.loadIcon(manager),
                    )
                }.getOrNull()
            }.toMutableList()
        if (apps.none { it.packageName == context.packageName }) {
            apps.add(FocusDesktopApp(
                context.packageName, ComponentName(context, MainActivity::class.java),
                manager.getApplicationLabel(context.applicationInfo).toString(),
                manager.getApplicationIcon(context.applicationInfo),
            ))
        }
        val collator = Collator.getInstance()
        return apps.sortedWith { first, second ->
            when {
                first.packageName == second.packageName -> 0
                first.packageName == context.packageName -> -1
                second.packageName == context.packageName -> 1
                else -> collator.compare(first.label, second.label).takeIf { it != 0 }
                    ?: first.packageName.compareTo(second.packageName)
            }
        }
    }
}
