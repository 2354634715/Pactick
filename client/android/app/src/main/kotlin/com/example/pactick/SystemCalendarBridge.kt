package com.example.pactick

import android.Manifest
import android.app.Activity
import android.content.ContentProviderOperation
import android.content.ContentProviderResult
import android.content.ContentUris
import android.content.ContentValues
import android.content.OperationApplicationException
import android.content.pm.PackageManager
import android.database.ContentObserver
import android.database.Cursor
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.os.CancellationSignal
import android.os.OperationCanceledException
import android.os.RemoteException
import android.provider.CalendarContract
import android.provider.CalendarContract.Calendars
import android.provider.CalendarContract.Events
import android.provider.CalendarContract.Instances
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject
import java.security.MessageDigest
import java.time.ZoneId
import java.util.concurrent.Executors

/** App-owned bridge: never impersonates the calendar account's sync adapter. */
internal class SystemCalendarBridge(
    private val activity: Activity,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {
    private val resolver = activity.contentResolver
    private val main = Handler(Looper.getMainLooper())
    private val executor = Executors.newSingleThreadExecutor()
    private val channel = MethodChannel(messenger, "pactick/system_calendar")
    private val events = EventChannel(messenger, "pactick/system_calendar_changes")
    private val pending = mutableSetOf<MethodChannel.Result>()
    private var permissionResult: MethodChannel.Result? = null
    private var sink: EventChannel.EventSink? = null
    private var observing = false
    @Volatile private var closed = false
    @Volatile private var generation = 0L
    @Volatile private var cancellation: CancellationSignal? = null
    private val operationGeneration = ThreadLocal<Long>()

    private val observer = object : ContentObserver(main) {
        override fun onChange(selfChange: Boolean) {
            if (closed) return
            if (!canRead()) {
                cancelPendingOperations()
                stopObserving()
            }
            sink?.success(null)
        }
    }

    init {
        channel.setMethodCallHandler(this)
        events.setStreamHandler(this)
    }

    override fun onListen(arguments: Any?, eventSink: EventChannel.EventSink) {
        sink = eventSink
        refreshObserver()
    }

    override fun onCancel(arguments: Any?) {
        sink = null
        cancelPendingOperations()
        stopObserving()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (closed) {
            result.error("calendar_interrupted", message(R.string.calendar_interrupted), null)
            return
        }
        when (call.method) {
            "permissions" -> {
                refreshObserver()
                result.success(permissions())
            }
            "requestPermissions" -> requestPermissions(call.argument<Boolean>("write") == true, result)
            "calendars", "readEvents", "upsertEvent", "deleteEvent" -> {
                val requestedGeneration = generation
                pending.add(result)
                executor.execute {
                    val signal = CancellationSignal()
                    cancellation = signal
                    operationGeneration.set(requestedGeneration)
                    try {
                        requireRead()
                        val response: Any? = when (call.method) {
                            "calendars" -> listCalendars()
                            "readEvents" -> readEvents(arguments(call))
                            "upsertEvent" -> { requireWrite(); upsert(arguments(call)) }
                            else -> { requireWrite(); delete(arguments(call)); null }
                        }
                        main.post {
                            if (pending.remove(result) && !closed) result.success(response)
                        }
                    } catch (error: Exception) {
                        val failure = when (error) {
                            is CalendarFailure -> error
                            is OperationCanceledException -> CalendarFailure("calendar_interrupted", R.string.calendar_interrupted)
                            is SecurityException -> CalendarFailure("calendar_permission_denied", R.string.calendar_permission_denied)
                            is OperationApplicationException -> CalendarFailure("calendar_conflict", R.string.calendar_conflict)
                            is RemoteException -> CalendarFailure("calendar_unavailable", R.string.calendar_unavailable)
                            else -> CalendarFailure("calendar_operation_failed", R.string.calendar_operation_failed)
                        }
                        // Provider exceptions can contain event/account contents. Return only
                        // stable codes and localized app text; never log the raw exception.
                        main.post {
                            if (pending.remove(result) && !closed) {
                                result.error(failure.code, message(failure.resource), null)
                            }
                        }
                    } finally {
                        operationGeneration.remove()
                        if (cancellation === signal) cancellation = null
                    }
                }
            }
            else -> result.notImplemented()
        }
    }

    private fun requestPermissions(write: Boolean, result: MethodChannel.Result) {
        if (!supported() || (canRead() && (!write || canWrite()))) {
            refreshObserver()
            result.success(permissions())
            return
        }
        if (permissionResult != null) {
            result.error("calendar_busy", message(R.string.calendar_busy), null)
            return
        }
        if (activity.isFinishing || activity.isDestroyed) {
            result.error("calendar_interrupted", message(R.string.calendar_interrupted), null)
            return
        }
        permissionResult = result
        try {
            ActivityCompat.requestPermissions(activity, if (write)
                arrayOf(Manifest.permission.READ_CALENDAR, Manifest.permission.WRITE_CALENDAR)
                else arrayOf(Manifest.permission.READ_CALENDAR), PERMISSION_REQUEST)
        } catch (_: Exception) {
            permissionResult = null
            result.error("calendar_permission_denied", message(R.string.calendar_permission_denied), null)
        }
    }

    fun onRequestPermissionsResult(requestCode: Int): Boolean {
        if (requestCode != PERMISSION_REQUEST) return false
        val result = permissionResult
        permissionResult = null
        refreshObserver()
        result?.success(permissions())
        return true
    }

    fun dispose() {
        if (closed) return
        closed = true
        cancelPendingOperations()
        stopObserving()
        sink = null
        permissionResult?.error("calendar_interrupted", message(R.string.calendar_interrupted), null)
        permissionResult = null
        for (result in pending.toList()) {
            result.error("calendar_interrupted", message(R.string.calendar_interrupted), null)
        }
        pending.clear()
        channel.setMethodCallHandler(null)
        events.setStreamHandler(null)
        executor.shutdownNow()
    }

    private fun refreshObserver() {
        if (closed || sink == null || !canRead()) {
            if (!canRead()) cancelPendingOperations()
            stopObserving()
            return
        }
        if (observing) return
        try {
            resolver.registerContentObserver(Events.CONTENT_URI, true, observer)
            resolver.registerContentObserver(Calendars.CONTENT_URI, true, observer)
            observing = true
        } catch (_: Exception) {
            // A manual sync/on-resume still works if an OEM provider cannot observe.
            runCatching { resolver.unregisterContentObserver(observer) }
        }
    }

    private fun stopObserving() {
        if (observing) runCatching { resolver.unregisterContentObserver(observer) }
        observing = false
    }

    private fun cancelPendingOperations() {
        generation++
        runCatching { cancellation?.cancel() }
    }

    private fun ensureActive() {
        if (closed || Thread.currentThread().isInterrupted ||
            operationGeneration.get()?.let { it != generation } == true) {
            fail("calendar_interrupted", R.string.calendar_interrupted)
        }
    }

    private fun supported(): Boolean = runCatching {
        activity.packageManager.resolveContentProvider(CalendarContract.AUTHORITY, 0) != null
    }.getOrDefault(false)

    private fun canRead() = ContextCompat.checkSelfPermission(activity, Manifest.permission.READ_CALENDAR) == PackageManager.PERMISSION_GRANTED
    private fun canWrite() = ContextCompat.checkSelfPermission(activity, Manifest.permission.WRITE_CALENDAR) == PackageManager.PERMISSION_GRANTED
    private fun permissions() = mapOf("supported" to supported(), "read" to canRead(), "write" to canWrite())
    private fun requireRead() {
        ensureActive()
        if (!supported()) fail("calendar_unavailable", R.string.calendar_unavailable)
        if (!canRead()) fail("calendar_permission_denied", R.string.calendar_permission_denied)
    }
    private fun requireWrite() {
        if (!canWrite()) fail("calendar_permission_denied", R.string.calendar_permission_denied)
    }

    private data class CalendarRow(val values: Map<String, Any?>) {
        val id get() = (values[Calendars._ID] as Number).toLong()
        val access get() = (values[Calendars.CALENDAR_ACCESS_LEVEL] as? Number)?.toInt() ?: 0
        val writable get() = access >= Calendars.CAL_ACCESS_CONTRIBUTOR
        val fingerprint get() = hash(CALENDAR_IDENTITY.map { values[it] })
        fun toMap() = mapOf(
            "id" to id.toString(), "fingerprint" to fingerprint,
            "displayName" to (values[Calendars.CALENDAR_DISPLAY_NAME] as? String).orEmpty(),
            "accountLabel" to (values[Calendars.ACCOUNT_NAME] as? String).orEmpty(),
            "writable" to writable,
        )
    }

    private fun listCalendars(): List<Map<String, Any?>> {
        val result = mutableListOf<Map<String, Any?>>()
        query(Calendars.CONTENT_URI, CALENDAR_COLUMNS,
            "${Calendars.VISIBLE} = 1 AND ${Calendars.CALENDAR_ACCESS_LEVEL} >= ?",
            arrayOf(Calendars.CAL_ACCESS_READ.toString()), "${Calendars._ID} ASC").use { cursor ->
            while (cursor.moveToNext()) result.add(CalendarRow(row(cursor)).toMap())
        }
        return result
    }

    private fun calendar(args: Map<String, Any?>, writing: Boolean = false): CalendarRow {
        val id = text(args, "calendarId").toLongOrNull() ?: invalid()
        val current = query(Calendars.CONTENT_URI, CALENDAR_COLUMNS,
            "${Calendars._ID} = ?", arrayOf(id.toString())).use { cursor ->
            if (cursor.moveToFirst()) CalendarRow(row(cursor)) else null
        } ?: fail("calendar_not_found", R.string.calendar_not_found)
        if (current.fingerprint != text(args, "calendarFingerprint")) {
            fail("calendar_changed", R.string.calendar_changed)
        }
        if ((current.values[Calendars.VISIBLE] as? Number)?.toInt() != 1 || current.access < Calendars.CAL_ACCESS_READ) {
            fail("calendar_unavailable", R.string.calendar_unavailable)
        }
        if (writing && !current.writable) fail("calendar_read_only", R.string.calendar_read_only)
        return current
    }

    private data class EventRow(val values: Map<String, Any?>) {
        fun number(name: String): Long? = (values[name] as? Number)?.toLong()
            ?: (values[name] as? String)?.toLongOrNull()
        fun string(name: String): String = (values[name] as? String).orEmpty()
        val id get() = number(Events._ID)!!
        val calendarId get() = number(Events.CALENDAR_ID)!!
        val allDay get() = number(Events.ALL_DAY) == 1L
        val seriesId get() = number(Events.ORIGINAL_ID)
        val originalStart get() = number(Events.ORIGINAL_INSTANCE_TIME)
        val repeating get() = string(Events.RRULE).isNotEmpty() || string(Events.RDATE).isNotEmpty()
        val removed get() = number(Events.DELETED) == 1L || number(Events.STATUS) == Events.STATUS_CANCELED.toLong()
        fun end(start: Long): Long = number(Events.DTEND)
            ?: Math.addExact(start, CalendarTimeCodec.durationMillis(string(Events.DURATION)))
    }

    private data class Occurrence(val row: EventRow, val begin: Long, val end: Long) {
        val seriesId: Long? get() = row.seriesId ?: if (row.repeating) row.id else null
        val originalStart: Long? get() = row.originalStart ?: if (row.repeating) begin else null
        val key get() = seriesId?.let { "$it:$originalStart" } ?: row.id.toString()
        val revision get() = hash(listOf(key, begin, end) + EVENT_COLUMNS.map { row.values[it] })
        val timeZone get() = CalendarTimeCodec.planTimeZone(
            if (row.allDay) ZoneId.systemDefault().id else row.string(Events.EVENT_TIMEZONE).ifEmpty { ZoneId.systemDefault().id })
        fun writable(calendar: CalendarRow, packageName: String): Boolean = calendar.writable && (
            calendar.access >= Calendars.CAL_ACCESS_EDITOR || row.number(Events.IS_ORGANIZER) == 1L ||
                row.number(Events.GUESTS_CAN_MODIFY) == 1L || row.string(Events.CUSTOM_APP_PACKAGE) == packageName) &&
            (!row.repeating || row.string(Events.RRULE).isNotEmpty())
        fun toMap(calendar: CalendarRow, packageName: String, from: Long = Long.MIN_VALUE, to: Long = Long.MAX_VALUE): Map<String, Any?> {
            val displayStart = CalendarTimeCodec.toDisplayMillis(begin, row.allDay)
            val displayEnd = CalendarTimeCodec.toDisplayMillis(end, row.allDay)
            return mapOf(
                "id" to row.id.toString(), "key" to key, "calendarId" to row.calendarId.toString(),
                "title" to row.string(Events.TITLE), "startsAtMillis" to displayStart,
                "endsAtMillis" to displayEnd,
                "timeZone" to timeZone,
                "allDay" to row.allDay, "revision" to revision, "recurring" to (seriesId != null),
                "seriesId" to seriesId?.toString(), "originalStartMillis" to originalStart,
                "appToken" to if (row.string(Events.CUSTOM_APP_PACKAGE) == packageName) row.string(Events.CUSTOM_APP_URI).ifEmpty { null } else null,
                "inWindow" to (displayEnd > from && displayStart < to),
                "writable" to writable(calendar, packageName),
            )
        }
    }

    private fun eventRow(id: Long): EventRow? = query(Events.CONTENT_URI, EVENT_COLUMNS,
        "${Events._ID} = ?", arrayOf(id.toString())).use { cursor ->
        if (cursor.moveToFirst()) EventRow(row(cursor)) else null
    }

    private fun exceptions(calendar: CalendarRow, seriesId: Long, originalStart: Long): List<EventRow> =
        query(Events.CONTENT_URI, EVENT_COLUMNS,
            "${Events.CALENDAR_ID} = ? AND ${Events.ORIGINAL_ID} = ? AND ${Events.ORIGINAL_INSTANCE_TIME} = ?",
            arrayOf(calendar.id.toString(), seriesId.toString(), originalStart.toString()), "${Events._ID} ASC").use { cursor ->
            val rows = mutableListOf<EventRow>()
            while (cursor.moveToNext()) {
                rows.add(EventRow(row(cursor)))
                if (rows.size > 1) fail("calendar_conflict", R.string.calendar_conflict)
            }
            rows
        }

    private fun queryInstances(calendar: CalendarRow, from: Long, to: Long, eventId: Long? = null): List<Occurrence> {
        val uri = Instances.CONTENT_URI.buildUpon().also {
            ContentUris.appendId(it, from)
            ContentUris.appendId(it, to)
        }.build()
        val selection = "${Instances.CALENDAR_ID} = ?" + if (eventId == null) "" else " AND ${Instances.EVENT_ID} = ?"
        val selectionArgs = mutableListOf(calendar.id.toString()).also { if (eventId != null) it.add(eventId.toString()) }
        val result = mutableListOf<Occurrence>()
        var count = 0
        // Instances exposes the event columns too. One cursor avoids an IPC
        // query for every occurrence and reads each row's fields consistently.
        val projection = arrayOf(Instances.EVENT_ID, Instances.BEGIN, Instances.END) + EVENT_COLUMNS.filter { it != Events._ID }
        query(uri, projection, selection,
            selectionArgs.toTypedArray(), "${Instances.BEGIN} ASC").use { cursor ->
            while (cursor.moveToNext()) {
                if (++count > MAX_EVENTS) fail("calendar_too_many_events", R.string.calendar_too_many_events)
                val id = cursor.getLong(0)
                val source = row(cursor)
                val event = EventRow(EVENT_COLUMNS.associateWith { if (it == Events._ID) id else source[it] })
                if (event.removed || event.calendarId != calendar.id) continue
                val begin = cursor.getLong(1)
                val end = cursor.getLong(2)
                if (end <= begin) fail("calendar_invalid_event", R.string.calendar_invalid_event)
                result.add(Occurrence(event, begin, end))
            }
        }
        return result
    }

    private fun trackedOccurrence(calendar: CalendarRow, existing: Map<String, Any?>): Occurrence? {
        if (existing["id"] == "" && existing["appToken"] is String) {
            val token = text(existing, "appToken")
            if (!TOKEN_PATTERN.matches(token)) invalid()
            val event = tokenRows(calendar, token).singleOrNull() ?: return null
            if (event.repeating) fail("calendar_conflict", R.string.calendar_conflict)
            val begin = event.number(Events.DTSTART) ?: invalid()
            return Occurrence(event, begin, event.end(begin))
        }
        if (text(existing, "calendarId") != calendar.id.toString()) invalid()
        if (existing["recurring"] == true) {
            val seriesId = text(existing, "seriesId").toLongOrNull() ?: invalid()
            val originalStart = number(existing, "originalStartMillis")
            val exception = exceptions(calendar, seriesId, originalStart).singleOrNull()
            if (exception != null) {
                if (exception.removed) return null
                val begin = exception.number(Events.DTSTART) ?: invalid()
                return Occurrence(exception, begin, exception.end(begin))
            }
            val series = eventRow(seriesId) ?: return null
            if (series.calendarId != calendar.id || series.removed || !series.repeating) return null
            val matching = queryInstances(calendar, originalStart - QUERY_PADDING, originalStart + QUERY_PADDING, seriesId)
                .filter { it.originalStart == originalStart }
            if (matching.size > 1) fail("calendar_conflict", R.string.calendar_conflict)
            return matching.singleOrNull()
        }
        val id = text(existing, "id").toLongOrNull() ?: invalid()
        val event = eventRow(id) ?: return null
        if (event.calendarId != calendar.id || event.removed) return null
        if (event.repeating || event.seriesId != null) fail("calendar_conflict", R.string.calendar_conflict)
        val begin = event.number(Events.DTSTART) ?: invalid()
        return Occurrence(event, begin, event.end(begin))
    }

    private fun readEvents(args: Map<String, Any?>): Map<String, Any?> {
        val calendar = calendar(args)
        val from = number(args, "fromMillis")
        val to = number(args, "toMillis")
        if (to <= from || to - from > MAX_RANGE) invalid()
        val tracked = (args["tracked"] as? List<*>) ?: emptyList<Any?>()
        if (tracked.size > MAX_EVENTS) fail("calendar_too_many_events", R.string.calendar_too_many_events)
        val selected = linkedMapOf<String, Occurrence>()
        for (event in queryInstances(calendar, from - QUERY_PADDING, to + QUERY_PADDING)) {
            val data = event.toMap(calendar, activity.packageName, from, to)
            if (data["inWindow"] == true) {
                val previous = selected.put(event.key, event)
                if (previous != null && previous.revision != event.revision) fail("calendar_conflict", R.string.calendar_conflict)
            }
        }
        val missing = mutableListOf<String>()
        for (value in tracked) {
            val previous = map(value)
            val key = text(previous, "key")
            // Read again, even for in-window rows, so a missing range row never
            // means deletion merely because the user moved an event elsewhere.
            val current = trackedOccurrence(calendar, previous)
            val tokenProbe = previous["id"] == "" && previous["appToken"] is String
            if (current == null) {
                selected.remove(key)
                missing.add(key)
            } else {
                if (!tokenProbe && current.key != key) fail("calendar_conflict", R.string.calendar_conflict)
                selected[current.key] = current
            }
        }
        if (selected.size > MAX_EVENTS) fail("calendar_too_many_events", R.string.calendar_too_many_events)
        // Detect calendar removal/account replacement before declaring any
        // tracked event missing. A failed/incomplete snapshot is never returned.
        calendar(args)
        requireRead()
        return mapOf("events" to selected.values.map { it.toMap(calendar, activity.packageName, from, to) },
            "missingKeys" to missing, "complete" to true)
    }

    private fun tokenRows(calendar: CalendarRow, token: String): List<EventRow> =
        query(Events.CONTENT_URI, EVENT_COLUMNS, TOKEN_SELECTION,
            arrayOf(calendar.id.toString(), activity.packageName, token), "${Events._ID} ASC").use { cursor ->
            val rows = mutableListOf<EventRow>()
            while (cursor.moveToNext()) {
                rows.add(EventRow(row(cursor)))
                if (rows.size > 1) fail("calendar_conflict", R.string.calendar_conflict)
            }
            rows
        }

    private fun desiredValues(event: Map<String, Any?>): ContentValues {
        val title = text(event, "title")
        val start = number(event, "startsAtMillis")
        val end = number(event, "endsAtMillis")
        val allDay = event["allDay"] == true
        if (title.length > 500 || end <= start || end - start > MAX_RANGE) invalid()
        val zone = if (allDay) "UTC" else text(event, "timeZone").also {
            try { ZoneId.of(it) } catch (_: Exception) { invalid() }
        }
        val providerStart = try { CalendarTimeCodec.toProviderMillis(start, allDay) } catch (_: Exception) { invalid() }
        val providerEnd = try { CalendarTimeCodec.toProviderMillis(end, allDay) } catch (_: Exception) { invalid() }
        return ContentValues().apply {
            put(Events.TITLE, title)
            put(Events.DTSTART, providerStart)
            put(Events.DTEND, providerEnd)
            put(Events.EVENT_TIMEZONE, zone)
            put(Events.EVENT_END_TIMEZONE, zone)
            put(Events.ALL_DAY, if (allDay) 1 else 0)
            putNull(Events.DURATION)
        }
    }

    private fun upsert(args: Map<String, Any?>): Map<String, Any?> {
        val calendar = calendar(args, writing = true)
        val desired = map(args["event"])
        val values = desiredValues(desired)
        val token = text(args, "token")
        if (!TOKEN_PATTERN.matches(token)) invalid()
        val previous = args["existing"]?.let(::map)
        if (previous == null) {
            val found = tokenRows(calendar, token).singleOrNull()
            if (found != null) {
                if (found.repeating) fail("calendar_conflict", R.string.calendar_conflict)
                val begin = found.number(Events.DTSTART) ?: invalid()
                val occurrence = Occurrence(found, begin, found.end(begin))
                val response = occurrence.toMap(calendar, activity.packageName)
                if (!sameContent(response, desired)) fail("calendar_conflict", R.string.calendar_conflict)
                return response
            }
            values.put(Events.CALENDAR_ID, calendar.id)
            values.put(Events.CUSTOM_APP_PACKAGE, activity.packageName)
            values.put(Events.CUSTOM_APP_URI, token)
            val results = applyCalendarBatch(arrayListOf(
                assertCalendar(calendar),
                ContentProviderOperation.newAssertQuery(Events.CONTENT_URI)
                    .withSelection(TOKEN_SELECTION, arrayOf(calendar.id.toString(), activity.packageName, token))
                    .withExpectedCount(0).build(),
                ContentProviderOperation.newInsert(Events.CONTENT_URI).withValues(values).build(),
            ))
            val id = results.last().uri?.let(ContentUris::parseId)
                ?: fail("calendar_operation_failed", R.string.calendar_operation_failed)
            val row = eventRow(id) ?: fail("calendar_operation_failed", R.string.calendar_operation_failed)
            return Occurrence(row, row.number(Events.DTSTART)!!, row.end(row.number(Events.DTSTART)!!))
                .toMap(calendar, activity.packageName)
        }
        val occurrence = trackedOccurrence(calendar, previous)
            ?: fail("calendar_conflict", R.string.calendar_conflict)
        if (occurrence.key != text(previous, "key") || occurrence.revision != text(previous, "revision")) {
            fail("calendar_conflict", R.string.calendar_conflict)
        }
        if (!occurrence.writable(calendar, activity.packageName)) fail("calendar_read_only", R.string.calendar_read_only)
        if (desired["allDay"] == occurrence.row.allDay && desired["timeZone"] == occurrence.timeZone &&
            occurrence.row.string(Events.EVENT_TIMEZONE).isNotEmpty()) {
            // Keep the provider's original start/end zone metadata when the
            // user did not change zones, including travel events with two zones.
            // A single-occurrence exception inherits these fields from its parent.
            values.remove(Events.EVENT_TIMEZONE)
            values.remove(Events.EVENT_END_TIMEZONE)
        }
        val operations = arrayListOf(assertCalendar(calendar), assertEvent(occurrence.row))
        if (occurrence.row.repeating) {
            // The exception URI clones the parent's non-owned fields. Omitting
            // RRULE intentionally selects only this occurrence, never the series.
            values.remove(Events.DTEND)
            val duration = values.getAsLong(Events.DTSTART).let { start ->
                val end = CalendarTimeCodec.toProviderMillis(number(desired, "endsAtMillis"), desired["allDay"] == true)
                (end - start) / 1000
            }
            values.put(Events.DURATION, "PT${duration}S")
            values.put(Events.ORIGINAL_INSTANCE_TIME, occurrence.originalStart!!)
            operations.add(assertNoException(calendar, occurrence.seriesId!!, occurrence.originalStart!!))
            operations.add(ContentProviderOperation.newInsert(ContentUris.withAppendedId(Events.CONTENT_EXCEPTION_URI, occurrence.seriesId!!))
                .withValues(values).build())
        } else {
            operations.add(ContentProviderOperation.newUpdate(Events.CONTENT_URI)
                .withSelection("${Events._ID} = ?", arrayOf(occurrence.row.id.toString()))
                .withValues(values).withExpectedCount(1).build())
        }
        applyCalendarBatch(operations)
        val updated = trackedOccurrence(calendar, previous)
            ?: fail("calendar_operation_failed", R.string.calendar_operation_failed)
        return updated.toMap(calendar, activity.packageName)
    }

    private fun delete(args: Map<String, Any?>) {
        val calendar = calendar(args, writing = true)
        val previous = map(args["existing"])
        val occurrence = trackedOccurrence(calendar, previous) ?: return
        if (occurrence.key != text(previous, "key") || occurrence.revision != text(previous, "revision")) {
            fail("calendar_conflict", R.string.calendar_conflict)
        }
        if (!occurrence.writable(calendar, activity.packageName)) fail("calendar_read_only", R.string.calendar_read_only)
        val operations = arrayListOf(assertCalendar(calendar), assertEvent(occurrence.row))
        if (occurrence.row.repeating) {
            val values = ContentValues().apply {
                put(Events.ORIGINAL_INSTANCE_TIME, occurrence.originalStart!!)
                put(Events.DTSTART, occurrence.begin)
                put(Events.DURATION, "PT${(occurrence.end - occurrence.begin) / 1000}S")
                put(Events.STATUS, Events.STATUS_CANCELED)
            }
            operations.add(assertNoException(calendar, occurrence.seriesId!!, occurrence.originalStart!!))
            operations.add(ContentProviderOperation.newInsert(ContentUris.withAppendedId(Events.CONTENT_EXCEPTION_URI, occurrence.seriesId!!))
                .withValues(values).build())
        } else if (occurrence.seriesId != null) {
            // Updating the exception status preserves cancellation of the
            // original occurrence; deleting its row could resurrect the series.
            operations.add(ContentProviderOperation.newUpdate(Events.CONTENT_URI)
                .withSelection("${Events._ID} = ?", arrayOf(occurrence.row.id.toString()))
                .withValue(Events.STATUS, Events.STATUS_CANCELED).withExpectedCount(1).build())
        } else {
            operations.add(ContentProviderOperation.newDelete(Events.CONTENT_URI)
                .withSelection("${Events._ID} = ?", arrayOf(occurrence.row.id.toString()))
                .withExpectedCount(1).build())
        }
        applyCalendarBatch(operations)
    }

    private fun assertCalendar(calendar: CalendarRow): ContentProviderOperation =
        ContentProviderOperation.newAssertQuery(Calendars.CONTENT_URI)
            .withSelection("${Calendars._ID} = ?", arrayOf(calendar.id.toString()))
            .withValues(contentValues(calendar.values)).withExpectedCount(1).build()

    private fun assertEvent(event: EventRow): ContentProviderOperation =
        ContentProviderOperation.newAssertQuery(Events.CONTENT_URI)
            .withSelection("${Events._ID} = ?", arrayOf(event.id.toString()))
            .withValues(contentValues(event.values)).withExpectedCount(1).build()

    private fun assertNoException(calendar: CalendarRow, seriesId: Long, originalStart: Long) =
        ContentProviderOperation.newAssertQuery(Events.CONTENT_URI)
            .withSelection("${Events.CALENDAR_ID} = ? AND ${Events.ORIGINAL_ID} = ? AND ${Events.ORIGINAL_INSTANCE_TIME} = ?",
                arrayOf(calendar.id.toString(), seriesId.toString(), originalStart.toString()))
            .withExpectedCount(0).build()

    private fun applyCalendarBatch(operations: ArrayList<ContentProviderOperation>): Array<ContentProviderResult> {
        // Already dispatched provider transactions may complete atomically; do
        // not start another one after the connection/foreground epoch changes.
        requireRead()
        requireWrite()
        return resolver.applyBatch(CalendarContract.AUTHORITY, operations)
    }

    private fun query(uri: Uri, projection: Array<String>, selection: String?, args: Array<String>?, sort: String? = null): Cursor {
        ensureActive()
        return resolver.query(uri, projection, selection, args, sort, cancellation)
            ?: fail("calendar_unavailable", R.string.calendar_unavailable)
    }

    private fun row(cursor: Cursor): Map<String, Any?> {
        ensureActive()
        return cursor.columnNames.associateWith { name ->
            val index = cursor.getColumnIndexOrThrow(name)
            when (cursor.getType(index)) {
                Cursor.FIELD_TYPE_NULL -> null
                Cursor.FIELD_TYPE_INTEGER -> cursor.getLong(index)
                Cursor.FIELD_TYPE_FLOAT -> cursor.getDouble(index)
                else -> cursor.getString(index)
            }
        }
    }

    private fun contentValues(values: Map<String, Any?>) = ContentValues().apply {
        for ((key, value) in values) when (value) {
            null -> putNull(key)
            is Long -> put(key, value)
            is Int -> put(key, value)
            is Double -> put(key, value)
            else -> put(key, value.toString())
        }
    }

    private fun message(resource: Int) = PactickStrings.text(activity, resource)
    private class CalendarFailure(val code: String, val resource: Int) : RuntimeException(code)
    private fun fail(code: String, resource: Int): Nothing = throw CalendarFailure(code, resource)
    private fun invalid(): Nothing = fail("calendar_invalid_event", R.string.calendar_invalid_event)
    private fun arguments(call: MethodCall): Map<String, Any?> = map(call.arguments)
    private fun map(value: Any?): Map<String, Any?> {
        if (value !is Map<*, *> || value.keys.any { it !is String }) invalid()
        @Suppress("UNCHECKED_CAST")
        return value as Map<String, Any?>
    }
    private fun text(values: Map<String, Any?>, key: String): String = values[key] as? String ?: invalid()
    private fun number(values: Map<String, Any?>, key: String): Long = (values[key] as? Number)?.toLong() ?: invalid()

    companion object {
        private const val PERMISSION_REQUEST = 904
        private const val MAX_EVENTS = 10_000
        private const val QUERY_PADDING = 2L * 86_400_000
        // The Dart window includes today plus up to 400 other local dates.
        // Leave room for its inclusive date and a daylight-saving transition.
        private const val MAX_RANGE = 402L * 86_400_000
        private val TOKEN_PATTERN = Regex("^pactick://calendar/[0-9a-fA-F-]{36}/[0-9a-fA-F-]{36}$")
        private val CALENDAR_IDENTITY = arrayOf(Calendars.ACCOUNT_NAME, Calendars.ACCOUNT_TYPE, Calendars.OWNER_ACCOUNT, Calendars.NAME)
        private val CALENDAR_COLUMNS = arrayOf(Calendars._ID, Calendars.ACCOUNT_NAME, Calendars.ACCOUNT_TYPE,
            Calendars.OWNER_ACCOUNT, Calendars.NAME, Calendars.CALENDAR_DISPLAY_NAME,
            Calendars.CALENDAR_ACCESS_LEVEL, Calendars.VISIBLE)
        private val EVENT_COLUMNS = arrayOf(Events._ID, Events.CALENDAR_ID, Events.TITLE, Events.DTSTART, Events.DTEND,
            Events.DURATION, Events.EVENT_TIMEZONE, Events.EVENT_END_TIMEZONE, Events.ALL_DAY,
            Events.RRULE, Events.RDATE, Events.EXRULE, Events.EXDATE, Events.ORIGINAL_ID,
            Events.ORIGINAL_INSTANCE_TIME, Events.ORIGINAL_ALL_DAY, Events.STATUS, Events.DELETED,
            Events.CUSTOM_APP_PACKAGE, Events.CUSTOM_APP_URI, Events.UID_2445, Events.IS_ORGANIZER, Events.GUESTS_CAN_MODIFY)
        private val TOKEN_SELECTION = "${Events.CALENDAR_ID} = ? AND ${Events.CUSTOM_APP_PACKAGE} = ? AND ${Events.CUSTOM_APP_URI} = ? AND ${Events.DELETED} = 0 AND (${Events.STATUS} IS NULL OR ${Events.STATUS} != ${Events.STATUS_CANCELED})"
        private fun hash(values: List<Any?>): String {
            val json = JSONArray().apply { values.forEach { put(it ?: JSONObject.NULL) } }.toString()
            return MessageDigest.getInstance("SHA-256").digest(json.toByteArray(Charsets.UTF_8))
                .joinToString("") { "%02x".format(it) }
        }
        private fun sameContent(left: Map<String, Any?>, right: Map<String, Any?>) =
            listOf("title", "startsAtMillis", "endsAtMillis", "timeZone", "allDay").all { left[it] == right[it] }
    }
}
