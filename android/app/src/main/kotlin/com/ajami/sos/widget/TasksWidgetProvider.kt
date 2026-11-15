package com.ajami.sos.widget

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.util.TypedValue
import android.view.View
import android.widget.RemoteViews
import com.ajami.sos.MainActivity
import com.ajami.sos.R

/**
 * Home-screen to-do widget.
 *
 * Shows today's tasks first, then the upcoming scheduled ones (the pre-defined
 * D1–D20 plan) so the user sees what is coming without opening the app.
 * Each row can be ticked straight from the launcher.
 */
class TasksWidgetProvider : AppWidgetProvider() {

  override fun onUpdate(
    context: Context,
    manager: AppWidgetManager,
    ids: IntArray,
  ) {
    val views = build(context)
    for (id in ids) manager.updateAppWidget(id, views)
  }

  override fun onReceive(context: Context, intent: Intent) {
    super.onReceive(context, intent)
    when (intent.action) {
      WidgetKeys.ACTION_TOGGLE -> {
        val taskId = intent.getIntExtra(WidgetKeys.EXTRA_TASK_ID, -1)
        val day = intent.getStringExtra(WidgetKeys.EXTRA_DAY).orEmpty()
        if (taskId >= 0 && day.isNotEmpty()) {
          WidgetActions.toggleTask(context, taskId, day)
        }
        refresh(context)
      }
      // Long-press opens the in-app widget settings.
      WidgetKeys.ACTION_SETTINGS -> openConfig(context)
    }
  }

  private fun openConfig(context: Context) {
    try {
      context.startActivity(
        Intent(context, MainActivity::class.java).apply {
          action = "com.ajami.sos.WIDGET_SETTINGS"
          flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        },
      )
    } catch (_: Throwable) {
      // ignore
    }
  }

  companion object {
    private const val DONE_TEXT = 0xFF7C8FAB.toInt()
    private const val ACTIVE_TEXT = 0xFFD7E6F5.toInt()
    private const val MISSION_TAG = 0xFF38BDF8.toInt()

    fun refresh(context: Context) {
      val manager = AppWidgetManager.getInstance(context)
      val ids = manager.getAppWidgetIds(
        ComponentName(context, TasksWidgetProvider::class.java),
      )
      if (ids.isEmpty()) return
      val views = build(context)
      for (id in ids) manager.updateAppWidget(id, views)
    }

    fun build(context: Context): RemoteViews {
      val views = RemoteViews(context.packageName, R.layout.widget_tasks)
      val data = WidgetData.load(context)
      val res = context.resources
      val scale = WidgetStyle.scale(data)

      WidgetStyle.apply(context, views, data)

      views.removeAllViews(R.id.w_rows)

      val todayKey = WidgetData.dayKey(0)
      val rows = mutableListOf<Pair<WidgetData.Task, Boolean>>() // task, isUpcoming

      data.today.take(4).forEach { rows += it to false }
      // Upcoming scheduled tasks (mission plan) fill the remaining space.
      val room = (4 - rows.size) + 2
      data.upcoming.take(room).forEach { rows += it to true }

      views.setViewVisibility(
        R.id.w_empty,
        if (rows.isEmpty()) View.VISIBLE else View.GONE,
      )

      for ((task, isUpcoming) in rows) {
        val row = RemoteViews(context.packageName, R.layout.widget_tasks_row)
        row.setTextViewText(R.id.row_title, task.title)
        row.setTextViewTextSize(
          R.id.row_title, TypedValue.COMPLEX_UNIT_SP, WidgetStyle.sp(12f, scale),
        )
        row.setImageViewResource(
          R.id.row_check,
          if (task.done) R.drawable.widget_check_on else R.drawable.widget_check_off,
        )
        row.setTextColor(R.id.row_title, if (task.done) DONE_TEXT else ACTIVE_TEXT)
        row.setViewVisibility(
          R.id.row_strike,
          if (task.done) View.VISIBLE else View.GONE,
        )

        val sub = buildString {
          if (isUpcoming) {
            append(friendlyDay(task.day))
            if (!task.time.isNullOrEmpty()) { append(" · "); append(task.time) }
          } else if (!task.time.isNullOrEmpty()) {
            append(task.time)
          }
          if (task.subtitle.isNotEmpty()) {
            if (isNotEmpty()) append("  ")
            append("☑ "); append(task.subtitle)
          }
          if (task.isPrivate) {
            if (isNotEmpty()) append("  ")
            append("🔒")
          }
        }
        if (sub.isNotEmpty()) {
          row.setViewVisibility(R.id.row_sub, View.VISIBLE)
          row.setTextViewText(R.id.row_sub, sub)
          row.setTextViewTextSize(
            R.id.row_sub, TypedValue.COMPLEX_UNIT_SP, WidgetStyle.sp(10f, scale),
          )
        } else {
          row.setViewVisibility(R.id.row_sub, View.GONE)
        }

        // Mission entries get a small blue dot instead of the red priority dot.
        if (task.priority >= 2) {
          row.setViewVisibility(R.id.row_tag, View.VISIBLE)
          row.setTextViewText(R.id.row_tag, "●")
          row.setTextColor(R.id.row_tag, 0xFFFF5470.toInt())
        } else if (task.isMission) {
          row.setViewVisibility(R.id.row_tag, View.VISIBLE)
          row.setTextViewText(R.id.row_tag, "◆")
          row.setTextColor(R.id.row_tag, MISSION_TAG)
        } else {
          row.setViewVisibility(R.id.row_tag, View.GONE)
        }

        row.setOnClickPendingIntent(R.id.row_title, openApp(context))
        row.setOnClickPendingIntent(
          R.id.row_check,
          toggleIntent(context, task.id, task.day.ifEmpty { todayKey }),
        )
        views.addView(R.id.w_rows, row)
      }

      val left = data.left
      views.setTextViewText(
        R.id.w_count,
        res.getString(R.string.widget_done_of) + " " +
          "${data.doneToday}/${data.scheduledToday}" +
          if (left > 0) "  ·  $left " + res.getString(R.string.widget_left) else "",
      )
      views.setTextViewTextSize(
        R.id.w_count, TypedValue.COMPLEX_UNIT_SP, WidgetStyle.sp(11f, scale),
      )
      views.setTextViewTextSize(
        R.id.w_title, TypedValue.COMPLEX_UNIT_SP, WidgetStyle.sp(12f, scale),
      )

      views.setOnClickPendingIntent(R.id.w_add, newTaskIntent(context))
      return views
    }

    /** "Today", "Tomorrow" or a short date for upcoming rows. */
    private fun friendlyDay(key: String): String = when (key) {
      WidgetData.dayKey(0) -> "·"
      WidgetData.dayKey(1) -> "↗"
      else -> key.takeLast(5) // MM-dd
    }

    private fun openApp(context: Context): PendingIntent {
      val intent = Intent(context, MainActivity::class.java).apply {
        action = Intent.ACTION_MAIN
        addCategory(Intent.CATEGORY_LAUNCHER)
        flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
      }
      return PendingIntent.getActivity(
        context, WidgetKeys.REQ_LIST, intent, pendingFlags(),
      )
    }

    private fun newTaskIntent(context: Context): PendingIntent {
      val intent = Intent(context, MainActivity::class.java).apply {
        action = "com.ajami.sos.NEW_TASK"
        flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
      }
      return PendingIntent.getActivity(
        context, WidgetKeys.REQ_LIST + 1, intent, pendingFlags(),
      )
    }

    private fun toggleIntent(
      context: Context,
      taskId: Int,
      day: String,
    ): PendingIntent {
      val intent = Intent(context, TasksWidgetProvider::class.java).apply {
        action = WidgetKeys.ACTION_TOGGLE
        putExtra(WidgetKeys.EXTRA_TASK_ID, taskId)
        putExtra(WidgetKeys.EXTRA_DAY, day)
      }
      return PendingIntent.getBroadcast(context, taskId, intent, pendingFlags())
    }

    private fun pendingFlags(): Int =
      PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
  }
}
