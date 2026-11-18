package com.ajami.sos.widget

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale

/**
 * Read side of the widget bridge.
 *
 * The Flutter side (lib/services/widget_bridge.dart) writes a small JSON
 * snapshot after every change, so the widgets render instantly and safely
 * without ever touching the encrypted database or its key.
 *
 * Widget writes (ticking a task, adding a memo) go into a queue in
 * SharedPreferences and the Flutter side drains that queue into the database.
 */
object WidgetData {
  private const val PREFS = "FlutterSharedPreferences"
  private const val SNAPSHOT = "sos_widget.json"

  /** Queue keys, also read by Dart. */
  const val KEY_TOGGLES = "flutter.sos_widget_toggles"

  // ---------- models ----------

  data class Task(
    val id: Int,
    val title: String,
    val subtitle: String,
    val done: Boolean,
    val priority: Int,
    val isPrivate: Boolean,
    val time: String?,
    val day: String = "",
    val isMission: Boolean = false,
  )

  /** One entry of the notes widget: title + preview + colour. */
  data class NoteEntry(
    val id: Int,
    val title: String,
    val preview: String,
    val day: String,
    val color: String?,
    val pinned: Boolean,
    val group: String = "",
  )

  /** One calendar cell: how many tasks, how many done, whether a memo exists. */
  data class Day(
    val key: String,
    val total: Int,
    val done: Int,
    val hasMemo: Boolean,
    val titles: List<String> = emptyList(),
    val doneFlags: List<Boolean> = emptyList(),
    /** Per-task colour (ARGB), matching the app's category colour. */
    val colors: List<Int> = emptyList(),
  )

  data class Snapshot(
    val today: List<Task> = emptyList(),
    val overdue: List<Task> = emptyList(),
    val doneToday: Int = 0,
    val scheduledToday: Int = 0,
    val doneYesterday: Int = 0,
    val scheduledYesterday: Int = 0,
    val done7: Int = 0,
    val scheduled7: Int = 0,
    val notes: List<NoteEntry> = emptyList(),
    val upcoming: List<Task> = emptyList(),
    val days: Map<String, Day> = emptyMap(),
    val textScale: Float = 1f,
    val opacity: Float = 0.85f,
    val arabic: Boolean = false,
    val lightMode: Boolean = false,
    val generatedAt: Long = 0,
    val hasAppData: Boolean = false,
  ) {
    val rateToday: Int
      get() = if (scheduledToday == 0) 0 else (doneToday * 100 / scheduledToday)
    val rate7: Int get() = if (scheduled7 == 0) 0 else (done7 * 100 / scheduled7)
    val left: Int get() = (scheduledToday - doneToday).coerceAtLeast(0)
  }

  // ---------- loading ----------

  fun load(context: Context): Snapshot {
    val file = snapshotFile(context) ?: return Snapshot()
    if (!file.exists() || file.length() < 2) return Snapshot()
    val text = try {
      file.readText()
    } catch (_: Throwable) {
      return Snapshot()
    }
    return try {
      parseSnapshot(JSONObject(text), file.lastModified())
    } catch (_: Throwable) {
      // A malformed snapshot must never leave the widget blank forever.
      Snapshot()
    }
  }

  /** '#AARRGGBB' or '#RRGGBB' → ARGB int. 0 when unparseable. */
  fun parseColor(raw: String?): Int {
    if (raw.isNullOrBlank()) return 0
    val hex = raw.removePrefix("#")
    return try {
      val v = hex.toLong(16)
      if (hex.length <= 6) (0xFF000000L or v).toInt() else v.toInt()
    } catch (_: Throwable) {
      0
    }
  }

  /** Timestamp of the last snapshot the app wrote, 0 when there is none. */
  fun lastWrite(context: Context): Long =
    try {
      snapshotFile(context)?.takeIf { it.exists() }?.lastModified() ?: 0L
    } catch (_: Throwable) {
      0L
    }

  private fun snapshotFile(context: Context): File? {
    val ext = context.getExternalFilesDir(null)
    if (ext != null) {
      val f = File(ext, SNAPSHOT)
      if (f.exists()) return f
    }
    return File(context.filesDir, SNAPSHOT)
  }

  private fun parseSnapshot(o: JSONObject, modified: Long): Snapshot {
    fun taskOf(t: JSONObject?): Task? {
      if (t == null) return null
      return Task(
        id = t.optInt("id"),
        title = t.optString("title"),
        subtitle = t.optString("subtitle"),
        done = t.optBoolean("done"),
        priority = t.optInt("priority"),
        isPrivate = t.optBoolean("private"),
        time = t.optString("time").takeIf { it.isNotEmpty() },
        day = t.optString("day"),
        isMission = t.optBoolean("isMission"),
      )
    }
    fun tasks(key: String): List<Task> {
      val arr = o.optJSONArray(key) ?: return emptyList()
      return (0 until arr.length()).mapNotNull { i ->
        try {
          taskOf(arr.optJSONObject(i))
        } catch (_: Throwable) {
          null
        }
      }
    }

    val daysObj = o.optJSONObject("days")
    val days = LinkedHashMap<String, Day>()
    if (daysObj != null) {
      for (key in daysObj.keys()) {
        val d = daysObj.optJSONObject(key) ?: continue
        val titles = mutableListOf<String>()
        val flags = mutableListOf<Boolean>()
        val arr = d.optJSONArray("t")
        val dArr = d.optJSONArray("done")
        if (arr != null) {
          for (i in 0 until arr.length()) {
            titles += arr.optString(i)
            flags += dArr?.optBoolean(i) ?: false
          }
        }
        val colors = mutableListOf<Int>()
        val cArr = d.optJSONArray("c")
        if (cArr != null) {
          for (i in 0 until cArr.length()) {
            colors += parseColor(cArr.optString(i))
          }
        }
        days[key] = Day(
          key = key,
          total = d.optInt("n"),
          done = d.optInt("d"),
          hasMemo = d.optInt("m") == 1,
          titles = titles,
          doneFlags = flags,
          colors = colors,
        )
      }
    }

    val settings = o.optJSONObject("settings")
    val notesArr = o.optJSONArray("notes")
    val notes = mutableListOf<NoteEntry>()
    if (notesArr != null) {
      for (i in 0 until notesArr.length()) {
        val n = notesArr.optJSONObject(i) ?: continue
        notes += NoteEntry(
          id = n.optInt("id"),
          title = n.optString("title"),
          preview = n.optString("preview"),
          day = n.optString("day"),
          color = n.optString("color").takeIf { it.isNotEmpty() && it != "null" },
          pinned = n.optBoolean("pinned"),
          group = n.optString("group"),
        )
      }
    }
    return Snapshot(
      today = tasks("today"),
      overdue = tasks("overdue"),
      upcoming = tasks("upcoming"),
      days = days,
      textScale = (settings?.optDouble("textScale", 1.0) ?: 1.0).toFloat(),
      opacity = (settings?.optDouble("opacity", 0.85) ?: 0.85).toFloat(),
      arabic = settings?.optBoolean("arabic") ?: false,
      lightMode = settings?.optBoolean("lightMode") ?: false,
      doneToday = o.optInt("doneToday"),
      scheduledToday = o.optInt("scheduledToday"),
      doneYesterday = o.optInt("doneYesterday"),
      scheduledYesterday = o.optInt("scheduledYesterday"),
      done7 = o.optInt("done7"),
      scheduled7 = o.optInt("scheduled7"),
      notes = notes,
      generatedAt = o.optLong("generatedAt", modified),
      hasAppData = true,
    )
  }

  // ---------- queued widget actions ----------

  /** Marks a task ticked from the launcher, waiting for the app to apply it. */
  fun queueToggle(context: Context, taskId: Int, day: String) {
    if (taskId < 0 || day.isEmpty()) return
    val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
    val arr = JSONArray()
    // Collapse repeated taps on the same task/day to the final intent.
    var pendingDone: Boolean? = null
    val existing = pendingToggles(context)
    for (t in existing) {
      if (t.first == taskId && t.second == day) {
        pendingDone = !t.third
      } else {
        arr.put(JSONObject().put("id", t.first).put("day", t.second).put("done", t.third))
      }
    }
    // The snapshot's current value plus one flip decides the target state.
    val current = load(context).today.firstOrNull { it.id == taskId }?.done ?: false
    val target = pendingDone ?: !current
    arr.put(JSONObject().put("id", taskId).put("day", day).put("done", target))
    prefs.edit().putString(KEY_TOGGLES, arr.toString()).apply()
  }

  /** Triple of (taskId, day, done). */
  fun pendingToggles(context: Context): List<Triple<Int, String, Boolean>> {
    val raw = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
      .getString(KEY_TOGGLES, null) ?: return emptyList()
    return try {
      val arr = JSONArray(raw)
      (0 until arr.length()).mapNotNull { i ->
        val o = arr.optJSONObject(i) ?: return@mapNotNull null
        Triple(o.optInt("id"), o.optString("day"), o.optBoolean("done"))
      }
    } catch (_: Throwable) {
      emptyList()
    }
  }

  /**
   * Mirrors the queued ticks onto the cached snapshot so a checkbox flips as
   * soon as it is tapped, instead of waiting for the app to drain the queue.
   * The real database is still updated by the Flutter side.
   */
  fun applyQueuedToggles(context: Context) {
    val toggles = pendingToggles(context)
    if (toggles.isEmpty()) return
    val file = snapshotFile(context) ?: return
    if (!file.exists()) return
    try {
      val root = JSONObject(file.readText())
      for ((id, day, done) in toggles) {
        for (key in listOf("today", "upcoming", "overdue")) {
          val arr = root.optJSONArray(key) ?: continue
          for (i in 0 until arr.length()) {
            val o = arr.optJSONObject(i) ?: continue
            if (o.optInt("id") == id && (day.isEmpty() || o.optString("day") == day)) {
              o.put("done", done)
            }
          }
        }
      }
      file.writeText(root.toString())
    } catch (_: Throwable) {
      // A broken cache must never break the widget.
    }
  }

  // ---------- helpers ----------

  fun dayKey(offset: Int): String =
    SimpleDateFormat("yyyy-MM-dd", Locale.US).format(addDays(Date(), offset))

  private fun addDays(d: Date, n: Int): Date {
    val c = Calendar.getInstance().apply { time = d; add(Calendar.DAY_OF_YEAR, n) }
    return c.time
  }
}
