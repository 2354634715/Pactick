package com.example.pactick

import java.time.Duration
import java.time.Instant
import java.time.LocalTime
import java.time.ZoneId
import java.time.ZoneOffset

/** Calendar Provider all-day values are UTC dates, not local UTC instants. */
internal object CalendarTimeCodec {
    private val zoneNames = ZoneId.getAvailableZoneIds()

    /** Plans use IANA names understood by both Android and the Go service. */
    fun planTimeZone(value: String): String = when {
        value == "UTC" || value == "GMT" -> "UTC"
        '/' in value && !value.startsWith("SystemV/") && value in zoneNames -> value
        else -> "UTC"
    }

    fun toDisplayMillis(value: Long, allDay: Boolean, zone: ZoneId = ZoneId.systemDefault()): Long =
        if (!allDay) value else Instant.ofEpochMilli(value).atZone(ZoneOffset.UTC)
            .toLocalDate().atStartOfDay(zone).toInstant().toEpochMilli()

    fun toProviderMillis(value: Long, allDay: Boolean, zone: ZoneId = ZoneId.systemDefault()): Long {
        if (!allDay) return value
        val local = Instant.ofEpochMilli(value).atZone(zone)
        require(local.toLocalTime() == LocalTime.MIDNIGHT) { "All-day values require local midnight" }
        return local.toLocalDate().atStartOfDay(ZoneOffset.UTC).toInstant().toEpochMilli()
    }

    fun durationMillis(value: String): Long {
        // RFC 2445 also permits a week-only form that java.time.Duration lacks.
        val weeks = Regex("^P([0-9]+)W$").matchEntire(value)
        return if (weeks != null) Duration.ofDays(Math.multiplyExact(weeks.groupValues[1].toLong(), 7)).toMillis()
        else Duration.parse(value).toMillis()
    }
}
