package com.example.pactick

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.res.Configuration
import android.graphics.Typeface
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.widget.Button
import android.widget.FrameLayout
import android.widget.GridLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import android.widget.Toast
import androidx.core.content.ContextCompat
import java.util.Locale
import java.util.concurrent.Executors
import kotlin.math.ceil

/** An in-app launcher for a live focus session; it does not replace Android Home. */
class FocusDesktopActivity : Activity() {
    private val handler = Handler(Looper.getMainLooper())
    private val executor = Executors.newSingleThreadExecutor()
    private var sessionId: String? = null
    private var visiblePackages: Set<String>? = null
    private var loadGeneration = 0
    private var resumed = false
    private lateinit var timer: TextView
    private lateinit var status: TextView
    private lateinit var grid: GridLayout

    private val refresh = object : Runnable {
        override fun run() {
            if (!resumed || isFinishing || isDestroyed) return
            val state = currentState() ?: return
            refreshClock(state)
            if (visiblePackages != state.allowedPackageNames) loadApps(state)
            handler.postDelayed(this, 500L)
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        sessionId = intent.getStringExtra(EXTRA_SESSION_ID)
        // The desktop never receives task titles. Prevent its app switcher image
        // from exposing an application allowlist belonging to a private session.
        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        if (currentState() == null) return
        buildContent()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        sessionId = intent.getStringExtra(EXTRA_SESSION_ID)
        visiblePackages = null
        if (currentState() != null) buildContent()
    }

    override fun onResume() {
        super.onResume()
        resumed = true
        if (currentState() == null) return
        // App install/remove, labels, locale or permissions can change while an
        // external app is open. Reload from PackageManager on each return.
        visiblePackages = null
        handler.removeCallbacks(refresh)
        handler.post(refresh)
    }

    override fun onPause() {
        resumed = false
        handler.removeCallbacks(refresh)
        super.onPause()
    }

    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)
        loadGeneration++
        visiblePackages = null
        if (currentState() != null) buildContent()
    }

    override fun onDestroy() {
        handler.removeCallbacksAndMessages(null)
        loadGeneration++
        executor.shutdownNow()
        super.onDestroy()
    }

    private fun currentState(): FocusDesktopState? {
        val state = FocusTimerService.desktopState()
        if (state == null || state.sessionId != sessionId) {
            finish()
            return null
        }
        return state
    }

    private fun buildContent() {
        val surface = color(R.color.focus_guard_surface)
        val foreground = color(R.color.focus_guard_on_surface)
        val secondary = color(R.color.focus_guard_on_surface_variant)
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(surface)
            setPadding(dp(20), dp(12), dp(20), dp(12))
        }
        // Scroll the entire page so landscape, long English text and large text
        // settings retain access to both the client action and the app grid.
        val scroll = ScrollView(this).apply {
            isFillViewport = true
            setBackgroundColor(surface)
            // Android 15+ enforces edge-to-edge for this target SDK. Keep app
            // controls below status bars and above gesture/navigation areas.
            setOnApplyWindowInsetsListener { view, insets ->
                view.setPadding(
                    insets.systemWindowInsetLeft, insets.systemWindowInsetTop,
                    insets.systemWindowInsetRight, insets.systemWindowInsetBottom,
                )
                insets
            }
        }
        scroll.addView(root, FrameLayout.LayoutParams(-1, -2))
        root.addView(TextView(this).apply {
            text = text(R.string.focus_desktop_eyebrow)
            textSize = 12f
            letterSpacing = 0.12f
            setTextColor(secondary)
        })
        root.addView(TextView(this).apply {
            text = text(R.string.focus_desktop_title)
            textSize = 28f
            typeface = runCatching {
                Typeface.createFromAsset(assets, "flutter_assets/assets/fonts/NotoSerifSC.ttf")
            }.getOrElse { Typeface.create("serif", Typeface.NORMAL) }
            setTextColor(foreground)
            setPadding(0, dp(12), 0, dp(8))
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) isAccessibilityHeading = true
        })
        timer = TextView(this).apply {
            typeface = Typeface.create("sans-serif", Typeface.NORMAL)
            textSize = 44f
            setTextColor(foreground)
            setPadding(0, 0, 0, dp(8))
            isSingleLine = false
        }
        root.addView(timer)
        status = TextView(this).apply {
            textSize = 14f
            setTextColor(secondary)
            setPadding(0, 0, 0, dp(12))
        }
        root.addView(status)
        root.addView(Button(this).apply {
            text = text(R.string.focus_desktop_open_client)
            minHeight = dp(48)
            isAllCaps = false
            setOnClickListener { openClient() }
        }, LinearLayout.LayoutParams(-1, -2))
        root.addView(TextView(this).apply {
            text = text(R.string.focus_desktop_description)
            textSize = 14f
            setTextColor(secondary)
            setPadding(0, dp(16), 0, dp(16))
        })
        root.addView(View(this).apply { setBackgroundColor(secondary) }, LinearLayout.LayoutParams(-1, dp(1)))
        grid = GridLayout(this).apply {
            val scaledWidth = 104f * resources.configuration.fontScale.coerceAtLeast(1f)
            columnCount = ((resources.configuration.screenWidthDp - 40) / scaledWidth).toInt().coerceIn(1, 6)
            setPadding(0, dp(16), 0, dp(16))
        }
        root.addView(grid, LinearLayout.LayoutParams(-1, -2))
        setContentView(scroll)
        scroll.requestApplyInsets()
        currentState()?.let(::refreshClock)
    }

    private fun refreshClock(state: FocusDesktopState) {
        val millis = if (state.paused) state.pausedRemainingMillis else state.endsAtEpochMillis - System.currentTimeMillis()
        val seconds = ceil(millis.coerceAtLeast(0) / 1000.0).toLong()
        timer.text = String.format(Locale.ROOT, "%02d:%02d", seconds / 60, seconds % 60)
        timer.contentDescription = text(R.string.focus_desktop_remaining, timer.text.toString())
        status.text = text(when {
            state.paused -> R.string.focus_paused
            millis <= 0 -> R.string.focus_target_reached
            else -> R.string.focus_running
        })
    }

    private fun loadApps(state: FocusDesktopState) {
        visiblePackages = state.allowedPackageNames
        val generation = ++loadGeneration
        executor.execute {
            val result = runCatching { FocusDesktopApps.load(this, state.allowedPackageNames) }
            runOnUiThread {
                if (isDestroyed || isFinishing || generation != loadGeneration || currentState() == null) return@runOnUiThread
                result.onSuccess(::showApps).onFailure {
                    grid.removeAllViews()
                    grid.addView(Button(this).apply {
                        text = text(R.string.focus_desktop_retry)
                        minHeight = dp(48)
                        isAllCaps = false
                        contentDescription = text(R.string.focus_desktop_load_failed)
                        setOnClickListener { currentState()?.let(::loadApps) }
                    })
                    Toast.makeText(this, text(R.string.focus_desktop_load_failed), Toast.LENGTH_LONG).show()
                }
            }
        }
    }

    private fun showApps(apps: List<FocusDesktopApp>) {
        grid.removeAllViews()
        apps.forEachIndexed { index, app ->
            val cell = LinearLayout(this).apply {
                orientation = LinearLayout.VERTICAL
                gravity = Gravity.CENTER
                minimumHeight = dp(112)
                setPadding(dp(8), dp(12), dp(8), dp(12))
                isFocusable = true
                isClickable = true
                contentDescription = app.label
                val resolved = android.util.TypedValue()
                theme.resolveAttribute(android.R.attr.selectableItemBackground, resolved, true)
                setBackgroundResource(resolved.resourceId)
                setOnClickListener { launch(app) }
            }
            cell.addView(ImageView(this).apply {
                setImageDrawable(app.icon)
                importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
            }, LinearLayout.LayoutParams(dp(44), dp(44)))
            cell.addView(TextView(this).apply {
                text = app.label
                textSize = 14f
                gravity = Gravity.CENTER
                setTextColor(color(R.color.focus_guard_on_surface))
                setPadding(0, dp(8), 0, 0)
                importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
            }, LinearLayout.LayoutParams(-1, -2))
            grid.addView(cell, GridLayout.LayoutParams().apply {
                width = 0
                height = GridLayout.LayoutParams.WRAP_CONTENT
                columnSpec = GridLayout.spec(index % grid.columnCount, 1f)
                rowSpec = GridLayout.spec(index / grid.columnCount)
            })
        }
    }

    private fun launch(app: FocusDesktopApp) {
        val state = currentState() ?: return
        if (!FocusDesktopApps.isAllowed(this, app.packageName, state.allowedPackageNames)) {
            visiblePackages = null
            Toast.makeText(this, text(R.string.focus_desktop_app_unavailable), Toast.LENGTH_LONG).show()
            return
        }
        if (app.packageName == packageName) {
            openClient()
            return
        }
        try {
            startActivity(Intent(Intent.ACTION_MAIN).apply {
                addCategory(Intent.CATEGORY_LAUNCHER)
                component = app.component
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED)
            })
        } catch (_: Exception) {
            visiblePackages = null
            Toast.makeText(this, text(R.string.focus_desktop_app_unavailable), Toast.LENGTH_LONG).show()
        }
    }

    private fun openClient() {
        try {
            startActivity(Intent(this, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
            })
            finish()
        } catch (_: Exception) {
            Toast.makeText(this, text(R.string.focus_desktop_unavailable), Toast.LENGTH_LONG).show()
        }
    }

    private fun text(id: Int, vararg args: Any): String = PactickStrings.text(this, id, *args)
    private fun color(id: Int): Int = ContextCompat.getColor(this, id)
    private fun dp(value: Int): Int = (value * resources.displayMetrics.density).toInt()

    companion object {
        private const val EXTRA_SESSION_ID = "focus_session_id"
        fun intent(context: Context, sessionId: String?): Intent = Intent(context, FocusDesktopActivity::class.java).apply {
            putExtra(EXTRA_SESSION_ID, sessionId)
            addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
        }
    }
}
