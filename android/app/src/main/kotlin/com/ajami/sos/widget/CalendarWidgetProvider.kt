package com.ajami.sos.widget

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.util.TypedValue
import android.view.View
import android.widget.RemoteViews
import com.ajami.sos.MainActivity
import com.ajami.sos.R
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Locale

/**
 * Month calendar widget — the Google/Microsoft style view the user asked for.
 *
 * Renders a 7 × 6 grid for the currently displayed month, with a coloured dot
 * per task (filled when done) and a grey dot when the day has a memo. Tapping a
 * day puts that day's tasks in the summary line; the ‹ › arrows change month
 * without opening the app. The month you picked is remembered per widget.
 *
 * Everything is composed of LinearLayout / TextView only, so it stays legal
 * for RemoteViews and cheap to inflate.
 */
class CalendarWidgetProvider : AppWidgetProvider() {

  override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
    for (id in ids) {
      manager.updateAppWidget(id, build(context, id))
    }
  }

  override fun onReceive(context: Context, intent: Intent) {
    super.onReceive(context, intent)
    when (intent.action) {
      ACTION_PREV, ACTION_NEXT -> {
        val id = intent.getIntExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, -1)
        if (id != -1) {
          shiftMonth(context, id, if (intent.action == ACTION_NEXT) 1 else -1)
          AppWidgetManager.getInstance(context)
            .updateAppWidget(id, build(context, id))
        }
      }
      ACTION_DAY -> {
        // Selecting a day both highlights it here and opens that day's page in
        // the app, where the tasks and the memo for the day are listed.
        val id = intent.getIntExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, -1)
        val day = intent.getStringExtra(EXTRA_DAY).orEmpty()
        if (day.isEmpty()) return
        if (id != -1) {
          prefs(context).edit().putString(selectedKey(id), day).apply()
          AppWidgetManager.getInstance(context).updateAppWidget(id, build(context, id))
        }
        openDay(context, day)
      }
      ACTION_OPEN_APP -> openApp(context)
      ACTION_OPEN_DAY -> {
        val day = intent.getStringExtra(EXTRA_DAY).orEmpty()
        if (day.isEmpty()) openApp(context) else openDay(context, day)
      }
    }
  }

  private fun prefs(context: Context) =
    context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

  private fun monthKey(id: Int) = "month_$id"
  private fun selectedKey(id: Int) = "sel_$id"

  /** Moves the displayed month and jumps the selection into it. */
  private fun shiftMonth(context: Context, id: Int, delta: Int) {
    val p = prefs(context)
    val current = p.getString(monthKey(id), null) ?: currentMonth()
    val cal = parseMonth(current)
    cal.add(Calendar.MONTH, delta)
    val newMonth = formatMonth(cal)
    p.edit().putString(monthKey(id), newMonth).apply()
    // Keep the selection inside the visible month.
    val today = Calendar.getInstance()
    val sel = p.getString(selectedKey(id), null)
    if (sel == null || !sel.startsWith(newMonth)) {
      val sameYearMonth = formatMonth(today) == newMonth
      p.edit().putString(
        selectedKey(id),
        if (sameYearMonth) keyOf(today) else "$newMonth-01",
      ).apply()
    }
  }

  /** Opens the app directly on the requested day. */
  private fun openDay(context: Context, day: String) {
    try {
      val pi = PendingIntent.getActivity(
        context,
        day.hashCode() and 0xFFFF,
        dayPageIntent(context, day),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
      )
      pi.send()
    } catch (_: Throwable) {
      openApp(context)
    }
  }

  private fun openApp(context: Context) {
    try {
      context.startActivity(
        Intent(context, MainActivity::class.java).apply {
          flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        },
      )
    } catch (_: Throwable) {
    }
  }

  companion object {
    const val ACTION_PREV = "com.ajami.sos.widget.CAL_PREV"
    const val ACTION_NEXT = "com.ajami.sos.widget.CAL_NEXT"
    const val ACTION_DAY = "com.ajami.sos.widget.CAL_DAY"
    const val ACTION_OPEN_DAY = "com.ajami.sos.widget.CAL_OPEN_DAY"
    const val ACTION_OPEN_APP = "com.ajami.sos.widget.CAL_OPEN_APP"
    const val EXTRA_DAY = "cal_day"

    private const val PREFS = "sos_calendar_widget"


    fun refresh(context: Context) {
      val manager = AppWidgetManager.getInstance(context)
      val ids = manager.getAppWidgetIds(
        ComponentName(context, CalendarWidgetProvider::class.java),
      )
      for (id in ids) manager.updateAppWidget(id, build(context, id))
    }

    // ---------- date helpers ----------

    private fun currentMonth(): String = formatMonth(Calendar.getInstance())

    private fun formatMonth(cal: Calendar): String =
      String.format(Locale.US, "%04d-%02d", cal.get(Calendar.YEAR), cal.get(Calendar.MONTH) + 1)

    private fun keyOf(cal: Calendar): String =
      String.format(Locale.US, "%04d-%02d-%02d", cal.get(Calendar.YEAR),
        cal.get(Calendar.MONTH) + 1, cal.get(Calendar.DAY_OF_MONTH))

    private fun parseMonth(month: String): Calendar {
      val cal = Calendar.getInstance()
      val parts = month.split("-")
      if (parts.size == 2) {
        val y = parts[0].toIntOrNull() ?: cal.get(Calendar.YEAR)
        val m = parts[1].toIntOrNull() ?: (cal.get(Calendar.MONTH) + 1)
        cal.set(y, m - 1, 1, 12, 0, 0)
        cal.set(Calendar.MILLISECOND, 0)
      }
      return cal
    }

    // ---------- build ----------

    fun build(context: Context, widgetId: Int): RemoteViews {
      val views = RemoteViews(context.packageName, R.layout.widget_calendar)
      val data = WidgetData.load(context)
      val scale = WidgetStyle.scale(data)
      val palette = WidgetStyle.palette(data)
      WidgetStyle.apply(context, views, data)

      val p = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
      val monthStr = p.getString("month_$widgetId", null) ?: currentMonth()
      val monthCal = parseMonth(monthStr)
      val year = monthCal.get(Calendar.YEAR)
      val month = monthCal.get(Calendar.MONTH) // 0-based
      val arabic = data.arabic
      val localized = WidgetStrings.of(context, data)

      // Header
      val monthLabel = SimpleDateFormat(
      "MMMM yyyy",
      if (arabic) Locale("ar") else Locale.US,
    ).format(monthCal.time)
      views.setTextViewText(R.id.cal_month, monthLabel)
      views.setTextColor(R.id.cal_month, palette.green)
      views.setTextColor(R.id.cal_prev, palette.green)
      views.setTextColor(R.id.cal_next, palette.green)
      WidgetStyle.tint(views, R.id.cal_accent, palette.green)
      views.setTextViewTextSize(
        R.id.cal_month, TypedValue.COMPLEX_UNIT_SP, WidgetStyle.sp(12f, scale),
      )

      // Weekday initials — Sunday first, matching the app.
      val weekdays = if (arabic) {
        listOf("أحد", "اثن", "ثلا", "أرب", "خمي", "جمع", "سبت")
      } else {
        listOf("S", "M", "T", "W", "T", "F", "S")
      }
      views.removeAllViews(R.id.cal_weekdays)
      for (name in weekdays) {
        val wd = RemoteViews(context.packageName, R.layout.widget_cal_weekday)
        wd.setTextViewText(R.id.wd_label, name)
        wd.setTextColor(R.id.wd_label, palette.mutedGreen)
        views.addView(R.id.cal_weekdays, wd)
      }

      // Grid
      views.removeAllViews(R.id.cal_grid)
      val firstOfMonth = Calendar.getInstance().apply {
        set(year, month, 1, 12, 0, 0)
        set(Calendar.MILLISECOND, 0)
      }
      val leading = firstOfMonth.get(Calendar.DAY_OF_WEEK) - Calendar.SUNDAY // 0..6
      val daysInMonth = firstOfMonth.getActualMaximum(Calendar.DAY_OF_MONTH)
      val todayKeyStr = keyOf(Calendar.getInstance())
      val selected = p.getString("sel_$widgetId", null)
        ?: if (todayKeyStr.startsWith(monthStr)) todayKeyStr else "$monthStr-01"

      val rows = ((leading + daysInMonth) + 6) / 7
      for (r in 0 until rows) {
        val row = RemoteViews(context.packageName, R.layout.widget_cal_row)
        for (c in 0 until 7) {
          val cell = RemoteViews(context.packageName, R.layout.widget_cal_cell)
          val index = r * 7 + c
          val dayOfMonth = index - leading + 1

          if (dayOfMonth < 1 || dayOfMonth > daysInMonth) {
            cell.setTextViewText(R.id.cell_day, "")
            for (dot in intArrayOf(R.id.cell_dot1, R.id.cell_dot2, R.id.cell_dot3, R.id.cell_memo)) {
              cell.setViewVisibility(dot, View.GONE)
            }
            row.addView(R.id.cell_row_slots, cell)
            continue
          }

          val key = String.format(Locale.US, "%s-%02d", monthStr, dayOfMonth)
          val day = data.days[key]
          val isToday = key == todayKeyStr
          val isSelected = key == selected

          cell.setTextViewText(R.id.cell_day, "$dayOfMonth")
          cell.setTextViewTextSize(
            R.id.cell_day, TypedValue.COMPLEX_UNIT_SP,
            WidgetStyle.sp(if (isSelected) 12f else 11f, scale),
          )
          cell.setTextColor(
            R.id.cell_day,
            when {
              isSelected -> palette.green
              isToday -> palette.aqua
              else -> palette.text
            },
          )

          // Task dots: one per task, up to three.
          // Each dot takes the colour of its task's category exactly as the
          // app paints it, and greys out once that task is done — so the
          // widget and the in-app month view read the same.
          val total = day?.total ?: 0
          val dots = intArrayOf(R.id.cell_dot1, R.id.cell_dot2, R.id.cell_dot3)
          for ((i, dotId) in dots.withIndex()) {
            if (i < total) {
              cell.setViewVisibility(dotId, View.VISIBLE)
              val done = day?.doneFlags?.getOrNull(i) ?: false
              val custom = day?.colors?.getOrNull(i) ?: 0
              val tint = when {
                done -> palette.muted
                custom != 0 -> custom
                else -> palette.green
              }
              cell.setTextColor(dotId, tint)
            } else {
              cell.setViewVisibility(dotId, View.GONE)
            }
          }
          cell.setViewVisibility(
            R.id.cell_memo,
            if (day?.hasMemo == true) View.VISIBLE else View.GONE,
          )
          cell.setTextColor(R.id.cell_memo, palette.amber)

          // Tap a day → show its tasks in the summary line.
          val tint = when {
            isSelected && palette.light -> 0x260E9E86
            isSelected -> 0x2525F4C8
            isToday && palette.light -> 0x1A2E86C8
            isToday -> 0x142E86C8
            else -> Color.TRANSPARENT
          }
          cell.setInt(R.id.cell_root, "setBackgroundColor", tint)

          cell.setOnClickPendingIntent(
            R.id.cell_root,
            dayIntent(context, widgetId, key),
          )
          row.addView(R.id.cell_row_slots, cell)
        }
        views.addView(R.id.cal_grid, row)
      }

      // Summary for the selected day
      val selDay = data.days[selected]
      val label = selected.takeLast(5)
      val summary = when {
        selDay == null -> "$label  ·  ${localized.getString(R.string.widget_cal_empty)}"
        else -> buildString {
          append(label)
          append("  ·  ")
          append(localized.getString(R.string.widget_cal_tasks))
          append(" ${selDay.total}")
          if (selDay.done > 0) append(" (${selDay.done} ✓)")
          if (selDay.titles.isNotEmpty()) {
            append("  ·  ")
            append(selDay.titles.joinToString(" / "))
          }
          if (selDay.hasMemo) append("  ·  📝")
        }
      }
      views.setTextViewText(R.id.cal_summary, summary)
      views.setTextColor(R.id.cal_summary, palette.muted)
      views.setTextViewTextSize(
        R.id.cal_summary, TypedValue.COMPLEX_UNIT_SP, WidgetStyle.sp(10f, scale),
      )

      // Navigation
      views.setOnClickPendingIntent(R.id.cal_prev, navIntent(context, widgetId, ACTION_PREV, 0))
      views.setOnClickPendingIntent(R.id.cal_next, navIntent(context, widgetId, ACTION_NEXT, 1))
      views.setOnClickPendingIntent(
        R.id.cal_month,
        PendingIntent.getActivity(
          context,
          WidgetKeys.REQ_CALENDAR + 2,
          Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
          },
          PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        ),
      )
      return views
    }

    private fun dayIntent(context: Context, widgetId: Int, day: String): PendingIntent {
      val intent = Intent(context, CalendarWidgetProvider::class.java).apply {
        action = ACTION_DAY
        putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, widgetId)
        putExtra(EXTRA_DAY, day)
      }
      // Unique request code per day so each cell keeps its own intent.
      val rc = WidgetKeys.REQ_CALENDAR + 100 + (day.hashCode() and 0xFFFF)
      return PendingIntent.getBroadcast(
        context, rc, intent,
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
      )
    }

    private fun navIntent(
      context: Context,
      widgetId: Int,
      action: String,
      offset: Int,
    ): PendingIntent = PendingIntent.getBroadcast(
      context,
      WidgetKeys.REQ_CALENDAR + offset,
      Intent(context, CalendarWidgetProvider::class.java).apply {
        this.action = action
        putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, widgetId)
      },
      PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )
  }
}
