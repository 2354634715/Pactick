package com.example.pactick

import android.content.Context
import android.content.res.Configuration
import java.util.Locale

/** Locale for app-owned notifications and overlays, including cold receivers. */
object PactickStrings {
    private const val PREFERENCES = "pactick_language"

    fun configure(context: Context, preference: String) {
        require(preference in setOf("system", "chinese", "english"))
        check(context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
            .edit().putString("preference", preference).commit()) {
            "Could not persist native language preference"
        }
    }

    fun text(context: Context, resource: Int, vararg arguments: Any): String {
        val preference = context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
            .getString("preference", "system")
        val language = when (preference) {
            "chinese" -> "zh"
            "english" -> "en"
            else -> context.resources.configuration.locales[0].language
        }
        val locale = if (language == "zh") Locale.SIMPLIFIED_CHINESE else Locale.ENGLISH
        val configuration = Configuration(context.resources.configuration).apply { setLocale(locale) }
        return context.createConfigurationContext(configuration).getString(resource, *arguments)
    }
}
